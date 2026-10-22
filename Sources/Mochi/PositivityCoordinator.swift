import CoreGraphics
import Foundation
import Observation
import MochiCore

/// Mochi's unprompted kind words. `PositivityPolicy` decides WHEN; the on-device model (if on and
/// available) writes the line, otherwise a fixed cheer line is used. Nothing is logged or saved.
@MainActor
final class PositivityCoordinator {
    private let engine: TimerEngine
    private let settings: MochiSettings
    private let companion: Companion
    private let context: AgentContext
    private var policy = PositivityPolicy()
    private var loopTask: Task<Void, Never>?
    private var generating = false
    private var pendingWin: (win: PositivityWin, at: Date)?
    private var lastDone: Int?

    static let focusWinLife: TimeInterval = 15 * 60
    static let tickWinLife: TimeInterval = 3 * 60

    init(engine: TimerEngine, settings: MochiSettings, companion: Companion, context: AgentContext) {
        self.engine = engine
        self.settings = settings
        self.companion = companion
        self.context = context
    }

    func start() {
        guard loopTask == nil else { return }
        lastDone = context.store.counts(now: Date()).done
        trackStore()
        loopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                self?.evaluate()
                try? await Task.sleep(for: .seconds(45), tolerance: .seconds(15))
            }
        }
    }

    func handle(_ event: EngineEvent) {
        if event == .breakDue { pendingWin = (.focusFinished, Date()) }
    }

    /// A to-do ticked off (done count went up) is a win; ticking the last one is a bigger win.
    private func trackStore() {
        withObservationTracking {
            _ = context.store.items
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let c = self.context.store.counts(now: Date())
                if let last = self.lastDone, c.done > last {
                    self.pendingWin = (c.left == 0 ? .allDone : .todoTicked, Date())
                }
                self.lastDone = c.done
                self.trackStore()
            }
        }
    }

    private func evaluate() {
        let now = Date()
        guard !generating, settings.showMascot, settings.chat != .off, companion.isQuiet else { return }
        let away = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            >= Companion.awayAfter
        var win: PositivityWin?
        if let p = pendingWin {
            let life = p.win == .focusFinished ? Self.focusWinLife : Self.tickWinLife
            if now.timeIntervalSince(p.at) > life { pendingWin = nil } else { win = p.win }
        }
        guard let decision = policy.peek(now: now, level: settings.positivityLevel, win: win, phase: engine.phase,
                                         userActive: !away, wrapUpHour: settings.todoWrapUpHour,
                                         wrapUpMinute: settings.todoWrapUpMinute) else { return }
        speak(decision, now: now)
    }

    /// The policy slot (and a pending win) is only used up once a line was really shown.
    private func speak(_ decision: PositivityPolicy.Decision, now: Date) {
        func shown() {
            policy.commit(decision)
            if case .win = decision.moment { pendingWin = nil }
        }
        guard settings.smartMochi, SmartMochi.isAvailable, #available(macOS 26, *) else {
            if companion.sayCheer() { shown() }
            return
        }
        MochiBrain.prewarm()
        generating = true
        let snapshot = context.countsSnapshot()
        Task { @MainActor [weak self] in
            defer { self?.generating = false }
            let line = await MochiBrain.positiveLine(snapshot: snapshot, moment: decision.moment, now: now)
            guard let self else { return }
            let ok = line.map { self.companion.sayPositive($0) } ?? self.companion.sayCheer()
            if ok { shown() }
        }
    }
}
