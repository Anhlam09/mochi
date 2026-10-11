import Foundation
import Observation
import MochiCore

/// Mochi's friendly voice: greets once a day, checks in now and then, and reacts to breaks,
/// returns and taps. Lines show in the mascot's speech bubble for a few seconds.
@MainActor @Observable
final class Companion {
    /// The line Mochi is saying right now, if any.
    private(set) var message: String?

    @ObservationIgnored private let engine: TimerEngine
    @ObservationIgnored private let settings: MochiSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var chatter = Chatter()
    @ObservationIgnored private var nextChat: Date?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    /// `MOCHI_CHAT_SECONDS` shortens the gap between unprompted lines (demo mode).
    @ObservationIgnored private let intervalOverride: TimeInterval?

    static let showFor: TimeInterval = 9
    private static let greetingKey = "lastGreeting"

    init(engine: TimerEngine, settings: MochiSettings, defaults: UserDefaults = .standard,
         intervalOverride: TimeInterval? = nil) {
        self.engine = engine
        self.settings = settings
        self.defaults = defaults
        self.intervalOverride = intervalOverride
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            // Let the panel appear before the first hello.
            try? await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                self?.tick(Date())
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func handle(_ event: EngineEvent) {
        if event == .breakCompleted { say(.breakDone) }
    }

    /// Back from idle, lock or sleep: a new day's hello, or a welcome back.
    func userReturned() {
        if !greetIfNewDay(Date()) { say(.welcomeBack) }
    }

    /// Says a line for `moment` now (unless chatting is off) and pushes back the next check-in.
    func say(_ moment: ChatMoment) {
        guard settings.chat != .off else { return }
        let now = Date()
        chatter.name = settings.friendName
        let line = chatter.line(for: moment, at: now)
        message = line
        scheduleNext(from: now)
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.showFor))
            guard !Task.isCancelled, let self, self.message == line else { return }
            self.message = nil
        }
    }

    private func tick(_ now: Date) {
        guard settings.chat != .off, settings.showMascot, canChatNow else { return }
        if greetIfNewDay(now) { return }
        guard let nextChat else { scheduleNext(from: now); return }
        if now >= nextChat { say([.checkIn, .checkIn, .cheer, .cheer, .funFact].randomElement()!) }
    }

    /// Only chat when Mochi isn't already busy with a break or about to call one.
    private var canChatNow: Bool {
        switch engine.phase {
        case .idle: true
        case .focusing: engine.remaining > TimerEngine.almostDoneWindow
        case .breakDue, .snoozed, .onBreak, .paused: false
        }
    }

    @discardableResult
    private func greetIfNewDay(_ now: Date) -> Bool {
        guard settings.chat != .off,
              ChatSchedule.needsGreeting(lastGreeting: defaults.object(forKey: Self.greetingKey) as? Date, now: now)
        else { return false }
        defaults.set(now, forKey: Self.greetingKey)
        say(.greeting)
        return true
    }

    private func scheduleNext(from now: Date) {
        guard let interval = intervalOverride ?? settings.chat.interval else { nextChat = nil; return }
        nextChat = ChatSchedule.next(after: now, interval: interval, jitter: .random(in: 0...1))
    }
}
