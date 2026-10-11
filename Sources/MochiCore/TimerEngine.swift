import Foundation
import Observation

public enum ResumeTarget: Sendable, Equatable { case focusing, onBreak }

public enum Phase: Sendable, Equatable {
    case idle
    case focusing(end: Date)
    case breakDue(since: Date, snoozes: Int)
    case snoozed(end: Date, snoozes: Int)
    case onBreak(end: Date)
    case paused(remaining: TimeInterval, resume: ResumeTarget)
}

public enum EngineEvent: Sendable, Equatable { case almostDone, breakDue, breakStarted, breakEnded, breakCompleted }
// `breakEnded` fires whenever a break ends (natural, skip, reset, stop, start); `breakCompleted` additionally
// fires only when the break timer ran out on its own.

@MainActor @Observable
public final class TimerEngine {
    public private(set) var phase: Phase = .idle {
        didSet { if Self.tag(oldValue) != Self.tag(phase) { phaseStartedAt = now } }
    }
    /// When the current phase kind began (adjusting time does not change it).
    public private(set) var phaseStartedAt: Date
    /// Total length of the current focus/break period, including adjustments.
    public private(set) var periodDuration: TimeInterval = 0
    public private(set) var now: Date
    public private(set) var completedBreaks: Int = 0
    /// Tip for the upcoming/current break. Set on entering breakDue (or break-now), nil while focusing.
    public private(set) var currentTip: String?
    /// Changing the preset resets `completedBreaks`. Focusing (or paused while focusing) restarts
    /// fresh; break phases keep the current break and the new preset applies from the next focus.
    public var preset: Preset {
        didSet {
            guard oldValue != preset else { return }
            // Editing custom minutes in place: new lengths apply from the next period.
            if oldValue.id == "custom" && preset.id == "custom" { return }
            completedBreaks = 0
            switch phase {
            case .focusing:
                beginFocus()
            case .paused(_, .focusing):
                almostDoneFired = false
                periodDuration = currentSpec.focus
                phase = .paused(remaining: currentSpec.focus, resume: .focusing)
            default: break
            }
        }
    }

    public static let maxSnoozes = 2
    public static let almostDoneWindow: TimeInterval = 120

    @ObservationIgnored public var onEvent: (@MainActor (EngineEvent) -> Void)?
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let focusOverride: TimeInterval?
    @ObservationIgnored private let breakOverride: TimeInterval?
    @ObservationIgnored private var almostDoneFired = false
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    public init(preset: Preset = .gentle,
                clock: @escaping @Sendable () -> Date = { Date() },
                focusOverride: TimeInterval? = nil,
                breakOverride: TimeInterval? = nil) {
        self.preset = preset
        self.clock = clock
        self.focusOverride = focusOverride
        self.breakOverride = breakOverride
        let t = clock()
        self.now = t
        self.phaseStartedAt = t
    }

    public var currentSpec: BreakSpec {
        let s = preset.spec(forCycle: completedBreaks)
        return BreakSpec(focus: focusOverride ?? s.focus, rest: breakOverride ?? s.rest, kind: s.kind)
    }

    public var remaining: TimeInterval {
        switch phase {
        case .focusing(let end), .onBreak(let end), .snoozed(let end, _): return max(0, end.timeIntervalSince(now))
        case .paused(let r, _): return r
        case .idle, .breakDue: return 0
        }
    }

    public var progress: Double {
        switch phase {
        case .idle: return 0
        case .breakDue, .snoozed: return 1
        case .focusing, .onBreak, .paused:
            guard periodDuration > 0 else { return 1 }
            return min(1, max(0, 1 - remaining / periodDuration))
        }
    }

    public var isRunning: Bool {
        switch phase {
        case .idle, .paused: return false
        default: return true
        }
    }

    // MARK: Actions

    public func start() {
        restartFocus()
    }

    public func pause() {
        step(force: true)
        switch phase {
        case .focusing: phase = .paused(remaining: remaining, resume: .focusing)
        case .onBreak: phase = .paused(remaining: remaining, resume: .onBreak)
        default: break
        }
    }

    public func resume() {
        refresh()
        guard case .paused(let r, let target) = phase else { return }
        switch target {
        case .focusing: phase = .focusing(end: now.addingTimeInterval(r))
        case .onBreak: phase = .onBreak(end: now.addingTimeInterval(r))
        }
    }

    public func startBreak() {
        refresh()
        switch phase {
        case .breakDue, .snoozed, .focusing:
            if currentTip == nil { currentTip = Tips.random(for: currentSpec.kind) }
            periodDuration = currentSpec.rest
            phase = .onBreak(end: now.addingTimeInterval(currentSpec.rest))
            fire(.breakStarted)
        default: break
        }
    }

    public func skipBreak() {
        refresh()
        switch phase {
        case .breakDue, .snoozed, .onBreak:
            let wasBreak = isOnBreak
            completedBreaks += 1
            beginFocus()
            if wasBreak { fire(.breakEnded) }
        default: break
        }
    }

    @discardableResult
    public func snooze(minutes: Int) -> Bool {
        refresh()
        guard case .breakDue(_, let n) = phase, n < Self.maxSnoozes else { return false }
        phase = .snoozed(end: now.addingTimeInterval(Double(max(1, minutes)) * 60), snoozes: n + 1)
        return true
    }

    /// Shifts the current period's end (or paused remaining) by `seconds`, keeping remaining within 10 s…3 h.
    /// Works in focusing, onBreak, snoozed and paused; no-op (false) otherwise. Fires no events itself.
    @discardableResult
    public func adjust(by seconds: TimeInterval) -> Bool {
        let kind = Self.tag(phase)
        step(force: true)
        guard Self.tag(phase) == kind else { return false }
        let old = remaining
        let new = min(3 * 3600, max(min(old, 10), old + seconds))
        switch phase {
        case .focusing:
            phase = .focusing(end: now.addingTimeInterval(new))
            if new > Self.almostDoneWindow { almostDoneFired = false }
        case .onBreak: phase = .onBreak(end: now.addingTimeInterval(new))
        case .snoozed(_, let n): phase = .snoozed(end: now.addingTimeInterval(new), snoozes: n)
        case .paused(_, let t):
            phase = .paused(remaining: new, resume: t)
            if t == .focusing, new > Self.almostDoneWindow { almostDoneFired = false }
        default: return false
        }
        if case .snoozed = phase {} else { periodDuration += new - old }
        return true
    }

    /// Back to `.idle`: fires `.breakEnded` if a break was running; clears the tip.
    public func stop() {
        refresh()
        let wasBreak = isOnBreak
        currentTip = nil
        almostDoneFired = false
        periodDuration = 0
        phase = .idle
        if wasBreak { fire(.breakEnded) }
    }

    public func reset() {
        restartFocus()
    }

    public func naturalBreak() {
        refresh()
        switch phase {
        case .focusing, .breakDue, .snoozed:
            completedBreaks += 1
            beginFocus()
        default: break
        }
    }

    /// Derives transitions from the clock. `now` (and so observers) only update about once a
    /// second, or when a transition is due.
    public func tick() { step(force: false) }

    private func step(force: Bool) {
        let t = clock()
        if !force {
            let sameSecond = Int(t.timeIntervalSinceReferenceDate.rounded(.down)) == Int(now.timeIntervalSinceReferenceDate.rounded(.down))
            if sameSecond && !transitionDue(at: t) { return }
        }
        now = t
        switch phase {
        case .focusing(let end):
            if now >= end {
                currentTip = Tips.random(for: currentSpec.kind)
                phase = .breakDue(since: now, snoozes: 0)
                fire(.breakDue)
            } else if !almostDoneFired, periodDuration > Self.almostDoneWindow,
                      end.timeIntervalSince(now) <= Self.almostDoneWindow {
                almostDoneFired = true
                fire(.almostDone)
            }
        case .snoozed(let end, let n):
            if now >= end {
                phase = .breakDue(since: now, snoozes: n)
                fire(.breakDue)
            }
        case .onBreak(let end):
            if now >= end {
                completedBreaks += 1
                beginFocus()
                fire(.breakEnded)
                fire(.breakCompleted)
            }
        default: break
        }
    }

    public func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250), tolerance: .milliseconds(100))
                guard let self else { return }
                self.tick()
            }
        }
    }

    public func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: Helpers

    private func transitionDue(at t: Date) -> Bool {
        switch phase {
        case .focusing(let end):
            return t >= end || (!almostDoneFired && periodDuration > Self.almostDoneWindow
                                && end.timeIntervalSince(t) <= Self.almostDoneWindow)
        case .snoozed(let end, _), .onBreak(let end): return t >= end
        default: return false
        }
    }

    private func refresh() { now = clock() }

    private static func tag(_ p: Phase) -> Int {
        switch p {
        case .idle: return 0
        case .focusing: return 1
        case .breakDue: return 2
        case .snoozed: return 3
        case .onBreak: return 4
        case .paused(_, let t): return t == .focusing ? 1 : 4
        }
    }

    private var isOnBreak: Bool {
        switch phase {
        case .onBreak, .paused(_, .onBreak): return true
        default: return false
        }
    }

    /// Fresh focus without counting a break; fires `.breakEnded` if a break was in progress.
    private func restartFocus() {
        let wasBreak = isOnBreak
        beginFocus()
        if wasBreak { fire(.breakEnded) }
    }

    private func beginFocus() {
        refresh()
        currentTip = nil
        almostDoneFired = false
        periodDuration = currentSpec.focus
        phase = .focusing(end: now.addingTimeInterval(currentSpec.focus))
        phaseStartedAt = now
    }

    private func fire(_ e: EngineEvent) { onEvent?(e) }
}
