import AppKit
import CoreGraphics
import MochiCore

/// Turns idle time, screen lock and sleep into natural breaks (via `AwayPolicy`).
@MainActor
final class SystemMonitor {
    private let engine: TimerEngine
    private let threshold: TimeInterval
    private var idle = IdleTracker()
    private var away = AwayTracker()
    private var gate = NaturalBreakGate()
    private var pollTask: Task<Void, Never>?
    private var wasIdle = false
    /// Called when the user comes back after being away at least `threshold` seconds.
    var onReturn: (@MainActor (TimeInterval) -> Void)?
    private var lastIdleSeconds: TimeInterval = 0
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(engine: TimerEngine, threshold: TimeInterval = 300) {
        self.engine = engine
        self.threshold = threshold
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.pollIdle()
            }
        }
        let dist = DistributedNotificationCenter.default()
        let ws = NSWorkspace.shared.notificationCenter
        observe(dist, "com.apple.screenIsLocked") { $0.away.lock(at: Date()) }
        observe(dist, "com.apple.screenIsUnlocked") { $0.returned($0.away.unlock(at: Date())) }
        observe(ws, NSWorkspace.willSleepNotification.rawValue) { $0.away.sleep(at: Date()) }
        observe(ws, NSWorkspace.screensDidSleepNotification.rawValue) { $0.away.sleep(at: Date()) }
        observe(ws, NSWorkspace.didWakeNotification.rawValue) { $0.returned($0.away.wake(at: Date())) }
        observe(ws, NSWorkspace.screensDidWakeNotification.rawValue) { $0.returned($0.away.wake(at: Date())) }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tokens.forEach { $0.center.removeObserver($0.token) }
        tokens.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: String,
                         _ body: @escaping @MainActor (SystemMonitor) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { body(self) }
            }
        }
        tokens.append((center, token))
    }

    private func returned(_ awayFor: TimeInterval?) {
        guard let awayFor else { return }
        wasIdle = false   // this return is handled here, not again by the idle poll
        if awayFor >= threshold { onReturn?(awayFor) }
        let age = Date().timeIntervalSince(engine.phaseStartedAt)
        if AwayPolicy.action(awayFor: awayFor, phase: engine.phase, threshold: threshold, phaseAge: age) == .naturalBreak {
            triggerNaturalBreak()
        }
    }

    private func pollIdle() {
        if away.isAway { return }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                              eventType: CGEventType(rawValue: ~0)!)
        if wasIdle, seconds < threshold { onReturn?(lastIdleSeconds) }
        wasIdle = seconds >= threshold
        lastIdleSeconds = seconds
        let age = Date().timeIntervalSince(engine.phaseStartedAt)
        if idle.update(idleFor: seconds, phase: engine.phase, threshold: threshold, phaseAge: age) == .naturalBreak {
            triggerNaturalBreak()
        }
    }

    private func triggerNaturalBreak() {
        guard gate.allow(at: Date(), threshold: threshold) else { return }
        engine.naturalBreak()
    }
}
