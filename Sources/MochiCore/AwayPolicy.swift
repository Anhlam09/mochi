import Foundation

public enum AwayAction: Sendable, Equatable { case none, naturalBreak }

/// Pure decision: was the user away long enough that it counts as a break?
public enum AwayPolicy {
    public static func action(awayFor: TimeInterval, phase: Phase, threshold: TimeInterval) -> AwayAction {
        guard awayFor >= threshold else { return .none }
        switch phase {
        case .focusing, .breakDue, .snoozed: return .naturalBreak
        case .idle, .onBreak, .paused: return .none
        }
    }
}

/// Fires at most once per idle stretch; re-arms when activity resumes (idle < threshold).
public struct IdleTracker: Sendable {
    private var armed = true
    public init() {}

    public mutating func update(idleFor: TimeInterval, phase: Phase, threshold: TimeInterval) -> AwayAction {
        if idleFor < threshold { armed = true; return .none }
        guard armed else { return .none }
        armed = false   // consumed even if resting, so a finished break doesn't fire mid-stretch
        return AwayPolicy.action(awayFor: idleFor, phase: phase, threshold: threshold)
    }
}

/// Tracks lock/sleep → unlock/wake. Ignores wake events while the screen is still locked.
public struct AwayTracker: Sendable {
    private var since: Date?
    private var locked = false
    public init() {}

    public mutating func lock(at date: Date) { locked = true; since = since ?? date }
    public mutating func sleep(at date: Date) { since = since ?? date }

    /// Returns how long the user was away, or nil if nothing to evaluate.
    public mutating func unlock(at date: Date) -> TimeInterval? { locked = false; return finish(date) }
    public mutating func wake(at date: Date) -> TimeInterval? { locked ? nil : finish(date) }

    private mutating func finish(_ date: Date) -> TimeInterval? {
        defer { since = nil }
        return since.map { date.timeIntervalSince($0) }
    }
}
