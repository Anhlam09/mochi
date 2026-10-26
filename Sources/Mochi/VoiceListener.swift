@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech
import MochiCore

/// One turn of listening, ON-DEVICE ONLY.
///
/// - macOS 26+: `SpeechAnalyzer` + `SpeechTranscriber`, used only if the language's model is already
///   installed (`SpeechTranscriber.installedLocales`). Mochi never asks the system to download one.
/// - Otherwise `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`, used only when
///   `supportsOnDeviceRecognition` is true. Server recognition is never created.
/// - If neither is possible the turn fails with `.unsupportedLanguage` and nothing is recorded.
/// Audio goes from the microphone straight into the recognizer in memory. It is never written to disk,
/// and transcripts are never logged or saved.
@MainActor
final class VoiceListener {
    enum Failure: Error, Equatable { case micDenied, speechDenied, unsupportedLanguage, failed }

    var onLiveText: (@MainActor (String) -> Void)?
    var onSpeechStarted: (@MainActor () -> Void)?
    /// The turn's transcript ("" if nothing was heard). Called once per `start()`.
    var onFinal: (@MainActor (String) -> Void)?
    var onFailure: (@MainActor (Failure) -> Void)?

    private var engine: AVAudioEngine?
    private var backend: (any SpeechBackend)?
    private var generation = 0
    private var watchTask: Task<Void, Never>?
    private var live = ""
    private var started = Date()
    private var lastChange = Date()
    private var heard = false
    private var finishing = false

    static let silenceEnd = ConversationMachine.silenceEnd
    static let maxTurn = ConversationMachine.maxTurn

    var isRunning: Bool { engine != nil }

    func start() {
        cancel()
        generation += 1
        let gen = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.begin(gen)
            } catch let failure as Failure {
                if gen == self.generation { self.teardown(); self.onFailure?(failure) }
            } catch {
                if gen == self.generation { self.teardown(); self.onFailure?(.failed) }
            }
        }
    }

    /// End the turn now (hold released, or the silence/time limit): deliver what was heard.
    func stop() {
        guard engine != nil, !finishing else { return }
        finishing = true
        let gen = generation
        stopAudio()
        let b = backend
        Task { @MainActor [weak self] in
            let text = await b?.finish() ?? ""
            guard let self, gen == self.generation else { return }
            let result = text.isEmpty ? self.live : text
            self.teardown()
            self.onFinal?(result)
        }
    }

    /// Discard everything: no result is delivered.
    func cancel() {
        generation += 1
        teardown()
    }

    // MARK: Internals

    private func begin(_ gen: Int) async throws {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { throw Failure.failed }
        guard await Self.requestMic() else { throw Failure.micDenied }
        guard gen == generation else { return }

        let locale = Locale.current
        var chosen: (any SpeechBackend)?
        let handler: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in self?.heardText(text, gen: gen) }
        }
        if #available(macOS 26, *) { chosen = await AnalyzerBackend.make(locale: locale, onText: handler) }
        if chosen == nil {
            guard await Self.requestSpeech() else { throw Failure.speechDenied }
            guard let sf = SFBackend.make(locale: locale, onText: handler) else { throw Failure.unsupportedLanguage }
            chosen = sf
        }
        guard gen == generation, let backend = chosen else { return }
        self.backend = backend

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw Failure.failed }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            backend.append(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        started = Date(); lastChange = started; live = ""; heard = false; finishing = false

        watchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, gen == self.generation, !self.finishing else { return }
                let now = Date()
                if (self.heard && now.timeIntervalSince(self.lastChange) >= Self.silenceEnd)
                    || now.timeIntervalSince(self.started) >= Self.maxTurn {
                    self.stop()
                    return
                }
            }
        }
    }

    private func heardText(_ text: String, gen: Int) {
        guard gen == generation, !finishing else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t != live else { return }
        live = t
        lastChange = Date()
        if !t.isEmpty, !heard { heard = true; onSpeechStarted?() }
        onLiveText?(t)
    }

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        watchTask?.cancel()
        watchTask = nil
    }

    private func teardown() {
        stopAudio()
        backend?.cancel()
        backend = nil
        finishing = false
        live = ""
        heard = false
    }

    private static func requestMic() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private static func requestSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}

/// One on-device recognizer. Buffers arrive on the audio thread.
protocol SpeechBackend: AnyObject, Sendable {
    func append(_ buffer: AVAudioPCMBuffer)
    /// Finishes the audio and returns the final text.
    func finish() async -> String
    func cancel()
}

// MARK: SFSpeechRecognizer (on-device only)

final class SFBackend: SpeechBackend, @unchecked Sendable {
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var text = ""
    private var isFinal = false

    /// nil unless on-device recognition is supported for the locale.
    static func make(locale: Locale, onText: @escaping @Sendable (String) -> Void) -> SFBackend? {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { return nil }
        let b = SFBackend()
        b.request.requiresOnDeviceRecognition = true   // never the server
        b.request.shouldReportPartialResults = true
        b.request.addsPunctuation = false
        b.task = recognizer.recognitionTask(with: b.request) { [weak b] result, error in
            guard let b else { return }
            if let result {
                let t = result.bestTranscription.formattedString
                b.lock.lock(); b.text = t; if result.isFinal { b.isFinal = true }; b.lock.unlock()
                onText(t)
            }
            if error != nil { b.lock.lock(); b.isFinal = true; b.lock.unlock() }
        }
        return b
    }

    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }

    func finish() async -> String {
        request.endAudio()
        for _ in 0..<15 {
            if lock.withLock({ isFinal }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return lock.withLock { text }
    }

    func cancel() { task?.cancel(); request.endAudio() }
}

// MARK: SpeechAnalyzer / SpeechTranscriber (macOS 26, on-device)

@available(macOS 26, *)
final class AnalyzerBackend: SpeechBackend, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?
    private let lock = NSLock()
    private var finalized = ""
    private var volatile = ""

    private init(analyzer: SpeechAnalyzer, format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.analyzer = analyzer
        self.format = format
        self.continuation = continuation
    }

    /// nil unless the language model is ALREADY installed. Mochi never triggers a model download.
    static func make(locale: Locale, onText: @escaping @Sendable (String) -> Void) async -> AnalyzerBackend? {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == supported.identifier(.bcp47) }) else { return nil }
        let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return nil }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        do { try await analyzer.start(inputSequence: stream) } catch { return nil }
        let backend = AnalyzerBackend(analyzer: analyzer, format: format, continuation: continuation)
        backend.resultsTask = Task { [weak backend] in
            do {
                for try await result in transcriber.results {
                    guard let backend else { return }
                    let text = String(result.text.characters)
                    let isFinal = result.range.end <= result.resultsFinalizationTime
                    let all = backend.lock.withLock { () -> String in
                        if isFinal {
                            backend.finalized += (backend.finalized.isEmpty ? "" : " ") + text
                            backend.volatile = ""
                        } else {
                            backend.volatile = text
                        }
                        return [backend.finalized, backend.volatile].filter { !$0.isEmpty }.joined(separator: " ")
                    }
                    onText(all)
                }
            } catch {}
        }
        return backend
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        if buffer.format == format {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if converter == nil { converter = AVAudioConverter(from: buffer.format, to: format) }
        guard let converter else { return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        let supplied = SuppliedFlag()
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied.value { status.pointee = .noDataNow; return nil }
            supplied.value = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
    }

    func finish() async -> String {
        continuation.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = await resultsTask?.value
        return lock.withLock { [finalized, volatile].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    func cancel() {
        continuation.finish()
        resultsTask?.cancel()
        Task { await analyzer.cancelAndFinishNow() }
    }
}

private final class SuppliedFlag: @unchecked Sendable { var value = false }
