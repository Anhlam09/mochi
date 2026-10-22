import Foundation

/// Today's timer counters. Kept in memory only (never saved); resets each day and on relaunch.
public struct TimerStats: Sendable, Equatable {
    public private(set) var day: Date?
    public private(set) var focusSessions = 0
    public private(set) var breaksTaken = 0
    public init() {}

    public mutating func record(_ event: EngineEvent, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        let today = calendar.startOfDay(for: now)
        if day != today { day = today; focusSessions = 0; breaksTaken = 0 }
        switch event {
        case .breakDue: focusSessions += 1      // a focus period ran to its end
        case .breakStarted: breaksTaken += 1
        default: break
        }
    }

    /// Counters for `now`'s day (zero if nothing was recorded today).
    public func today(now: Date, calendar: Calendar = .autoupdatingCurrent) -> (focus: Int, breaks: Int) {
        day == calendar.startOfDay(for: now) ? (focusSessions, breaksTaken) : (0, 0)
    }
}

/// The ONLY text the on-device model ever sees about the user's day. One pure function so it can be
/// audited in one place. It contains exactly:
/// - the time, weekday and part of day
/// - the user's chosen name (clipped)
/// - the timer phase and today's focus/break counts
/// - to-do titles (clipped), done state, day and time
/// Nothing else: no ids, no creation times, no file paths, no other apps' data.
public enum AgentSnapshot {
    public static let maxItems = 30
    public static let maxTitleLength = 80
    public static let maxNameLength = 30

    public static func make(now: Date, calendar: Calendar = .autoupdatingCurrent, name: String, items: [TodoItem],
                            phase: Phase, remaining: TimeInterval, stats: TimerStats) -> String {
        let hourMinute = clock(now, calendar)
        var lines: [String] = []
        lines.append("Now: \(weekday(now, calendar)) \(hourMinute), \(partName(DayPart(hour: calendar.component(.hour, from: now))))")
        let cleanName = clip(name, maxNameLength)
        if !cleanName.isEmpty { lines.append("Friend's name: \(cleanName)") }
        lines.append("Timer: \(describe(phase, remaining: remaining))")
        let s = stats.today(now: now, calendar: calendar)
        lines.append("Today so far: \(s.focus) focus session\(s.focus == 1 ? "" : "s") finished, \(s.breaks) break\(s.breaks == 1 ? "" : "s") taken")

        let today = TodoList.today(items, now: now, calendar: calendar)
        let later = TodoList.later(items, now: now, calendar: calendar)
        let open = today.filter { !$0.done }.count
        lines.append("To-dos today (\(open) open, \(today.count - open) done):")
        var shown = 0
        func row(_ item: TodoItem, later isLater: Bool) {
            guard shown < maxItems else { return }
            shown += 1
            var when: [String] = []
            if isLater || item.isCarriedOver(today: now, calendar: calendar) {
                when.append(TodoList.dayLabel(item.day, now: now, calendar: calendar))
            }
            if let t = item.time { when.append(clock(t, calendar)) }
            let suffix = when.isEmpty ? "" : " (\(when.joined(separator: " ")))"
            lines.append("- [\(item.done ? "x" : " ")] \(clip(item.title, maxTitleLength))\(suffix)")
        }
        if today.isEmpty { lines.append("(none)") }
        today.forEach { row($0, later: false) }
        if !later.isEmpty {
            lines.append("Later:")
            later.forEach { row($0, later: true) }
        }
        let total = today.count + later.count
        if total > shown { lines.append("(+\(total - shown) more not shown)") }
        return lines.joined(separator: "\n")
    }

    /// A titles-free snapshot for kind words: only the time, day part, name and counts. To-do titles
    /// never reach the model that writes unprompted lines.
    public static func makeCounts(now: Date, calendar: Calendar = .autoupdatingCurrent, name: String, items: [TodoItem],
                                  stats: TimerStats) -> String {
        var lines = ["Now: \(weekday(now, calendar)) \(clock(now, calendar)), \(partName(DayPart(hour: calendar.component(.hour, from: now))))"]
        let cleanName = clip(name, maxNameLength)
        if !cleanName.isEmpty { lines.append("Friend's name: \(cleanName)") }
        let s = stats.today(now: now, calendar: calendar)
        lines.append("Focus sessions finished today: \(s.focus)")
        lines.append("Breaks taken today: \(s.breaks)")
        let c = TodoList.counts(items, now: now, calendar: calendar)
        lines.append("To-dos done today: \(c.done)")
        lines.append("To-dos left today: \(c.left)")
        lines.append("All to-dos done: \(c.left == 0 && c.done > 0 ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    /// One line, no control characters, at most `max` characters.
    static func clip(_ s: String, _ max: Int) -> String {
        let flat = s.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined().split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return flat.count <= max ? flat : String(flat.prefix(max - 1)) + "…"
    }

    private static func clock(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func weekday(_ d: Date, _ cal: Calendar) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][max(0, min(6, cal.component(.weekday, from: d) - 1))]
    }

    private static func partName(_ p: DayPart) -> String {
        switch p { case .morning: "morning"; case .afternoon: "afternoon"; case .evening: "evening"; case .night: "night" }
    }

    private static func describe(_ phase: Phase, remaining: TimeInterval) -> String {
        let mins = Int((remaining / 60).rounded(.up))
        switch phase {
        case .idle: return "not running"
        case .focusing: return "focusing, \(mins) min left"
        case .breakDue: return "a break is due"
        case .snoozed: return "break snoozed"
        case .onBreak: return "on a break, \(mins) min left"
        case .paused: return "paused"
        }
    }
}
