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
/// - to-do titles (clipped), done state, day and time, for today, the next six days, and what is later
/// Nothing else: no ids, no creation times, no file paths, no other apps' data.
public enum AgentSnapshot {
    public static let maxItems = 30
    public static let maxTitleLength = 80
    public static let maxNameLength = 30

    public static func make(now: Date, calendar: Calendar = .autoupdatingCurrent, name: String, items: [TodoItem],
                            phase: Phase, remaining: TimeInterval, stats: TimerStats,
                            events: [CalendarEvent] = []) -> String {
        let hourMinute = clock(now, calendar)
        var lines: [String] = []
        lines.append("Now: \(weekday(now, calendar)) \(hourMinute), \(partName(DayPart(hour: calendar.component(.hour, from: now))))")
        let cleanName = clip(name, maxNameLength)
        if !cleanName.isEmpty { lines.append("Friend's name: \(cleanName)") }
        lines.append("Timer: \(describe(phase, remaining: remaining))")
        let s = stats.today(now: now, calendar: calendar)
        lines.append("Today so far: \(s.focus) focus session\(s.focus == 1 ? "" : "s") finished, \(s.breaks) break\(s.breaks == 1 ? "" : "s") taken")

        let week = TodoList.week(items, now: now, calendar: calendar, events: events)
        let later = TodoList.later(items, now: now, calendar: calendar)
        let today = week[0].items
        let open = week[0].openCount
        lines.append("Today (\(open) open, \(today.count - open) done):")
        var shown = 0
        func row(_ item: TodoItem, label: String?) {
            guard shown < maxItems else { return }
            shown += 1
            var when: [String] = []
            if let label { when.append(label) }
            else if item.isCarriedOver(today: now, calendar: calendar) {
                when.append(TodoList.dayLabel(item.day, now: now, calendar: calendar))
            }
            if let t = item.time { when.append(clock(t, calendar)) }
            let suffix = when.isEmpty ? "" : " (\(when.joined(separator: " ")))"
            lines.append("- [\(item.done ? "x" : " ")] \(clip(item.title, maxTitleLength))\(suffix)")
        }
        if today.isEmpty { lines.append("(none)") }
        today.forEach { row($0, label: nil) }
        if !week[0].events.isEmpty { lines.append("Meetings today: \(MeetingPolicy.line(week[0].events, calendar: calendar))") }
        var total = today.count
        for day in week.dropFirst() {
            total += day.items.count
            let n = day.openCount
            lines.append("\(longDayLabel(day.date, calendar)) (\(n == 0 ? "free" : n == 1 ? "1 open to-do" : "\(n) open to-dos")):")
            if day.items.isEmpty { lines.append("(nothing)") }
            day.items.forEach { row($0, label: nil) }
            if !day.events.isEmpty { lines.append("Meetings: \(MeetingPolicy.line(day.events, calendar: calendar))") }
        }
        if !later.isEmpty {
            lines.append("Later:")
            later.forEach { row($0, label: TodoList.dayLabel($0.day, now: now, calendar: calendar)) }
            total += later.count
        }
        if total > shown { lines.append("(+\(total - shown) more not shown)") }
        return lines.joined(separator: "\n")
    }

    /// A titles-free snapshot for kind words: only the time, day part, name and counts. To-do titles
    /// never reach the model that writes unprompted lines.
    public static func makeCounts(now: Date, calendar: Calendar = .autoupdatingCurrent, name: String, items: [TodoItem],
                                  stats: TimerStats, events: [CalendarEvent] = []) -> String {
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
        let meetings = CalendarDays.meetings(events, on: now, calendar: calendar).count
        if meetings > 0 { lines.append("Meetings today: \(meetings)") }   // a count only, never titles
        return lines.joined(separator: "\n")
    }

    /// One line, no control characters, at most `max` characters.
    public static func clip(_ s: String, _ max: Int) -> String {
        let flat = s.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined().split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return flat.count <= max ? flat : String(flat.prefix(max - 1)) + "…"
    }

    /// Facts for "plan my week", computed here so the model doesn't have to read dates:
    /// the busiest day and the free days (today onward, titles never included).
    public static func weekFacts(now: Date, calendar: Calendar = .autoupdatingCurrent, items: [TodoItem]) -> String {
        let week = TodoList.week(items, now: now, calendar: calendar)
        var parts: [String] = []
        if let busiest = week.max(by: { $0.openCount < $1.openCount }), busiest.openCount > 0 {
            parts.append("Busiest day: \(longDayLabel(busiest.date, calendar)) with \(busiest.openCount) open to-do\(busiest.openCount == 1 ? "" : "s").")
        } else {
            parts.append("The whole week is free.")
        }
        let free = week.filter { $0.openCount == 0 }.map { longDayLabel($0.date, calendar) }
        if !free.isEmpty { parts.append("Free days: \(free.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }

    /// A short, warm "plan my week" overview written entirely in code from the week's counts (the small
    /// on-device model kept misreading dates). No titles: just the busiest day and a day to rest.
    public static func weekSummary(now: Date, calendar: Calendar = .autoupdatingCurrent, items: [TodoItem],
                                   events: [CalendarEvent] = []) -> String {
        let week = TodoList.week(items, now: now, calendar: calendar, events: events)
        func load(_ d: TodoWeekDay) -> Int { d.openCount + d.events.filter { !$0.isAllDay }.count }
        func name(_ d: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone
            f.dateFormat = "EEEE (MMM d)"
            return f.string(from: d)
        }
        guard let busiest = week.max(by: { load($0) < load($1) }), load(busiest) > 0 else {
            return "Your week is wide open! A lovely time to start something small, or simply rest 🌱"
        }
        func describe(_ d: TodoWeekDay) -> String {
            let m = d.events.filter { !$0.isAllDay }.count, t = d.openCount
            let meetings = "\(m) meeting\(m == 1 ? "" : "s")"
            if m == 0 { return "\(t) open to-do\(t == 1 ? "" : "s")" }
            return t == 0 ? meetings : "\(meetings) and \(t) to-do\(t == 1 ? "" : "s")"
        }
        var parts = ["\(busiest.isToday ? "Today" : name(busiest.date)) is your busiest day with \(describe(busiest))."]
        let rest = week.dropFirst().first { load($0) == 0 && $0.date != busiest.date } ?? week.first { load($0) == 0 && $0.date != busiest.date }
        if let rest { parts.append("\(rest.isToday ? "Today" : name(rest.date)) is free, a lovely day to rest.") }
        let total = week.reduce(0) { $0 + load($1) }
        parts.append(total <= 3 ? "A gentle week, you've got this 🌱" : "One day at a time, you've got this 🌱")
        return parts.joined(separator: " ")
    }

    /// "Thu Oct 23"
    private static func longDayLabel(_ d: Date, _ cal: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = cal.timeZone
        f.dateFormat = "EEE MMM d"
        return f.string(from: d)
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
