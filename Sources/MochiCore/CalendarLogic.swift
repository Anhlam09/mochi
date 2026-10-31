import Foundation

// Read-only calendar awareness: the pure logic. Events come from the Mac's Calendar app (EventKit) and
// live in memory only; this file never touches disk, network or EventKit.

public enum CalendarDays {
    /// Events that touch `day`: all-day ones first, then by start time, then title.
    public static func events(_ all: [CalendarEvent], on day: Date, calendar: Calendar = .autoupdatingCurrent) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return all.filter { $0.start < end && ($0.end > start || $0.start >= start) }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return ($0.start, $0.title) < ($1.start, $1.title)
            }
    }

    /// Seven days from today.
    public static func week(_ all: [CalendarEvent], now: Date, calendar: Calendar = .autoupdatingCurrent) -> [[CalendarEvent]] {
        let start = calendar.startOfDay(for: now)
        return (0..<7).map { events(all, on: calendar.date(byAdding: .day, value: $0, to: start)!, calendar: calendar) }
    }

    /// Timed (not all-day) events on `day`.
    public static func meetings(_ all: [CalendarEvent], on day: Date, calendar: Calendar = .autoupdatingCurrent) -> [CalendarEvent] {
        events(all, on: day, calendar: calendar).filter { !$0.isAllDay }
    }
}

public struct MeetingMemory: Sendable, Equatable {
    /// "<event id>.soon" / "<event id>.start": ids only, never titles.
    public var notified: Set<String> = []
    public var morningDay: Date?
    public init() {}
}

public struct MeetingNudge: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case soon, start }
    public var kind: Kind
    public var text: String
    public var notificationTitle: String
    public var notificationBody: String
    public var eventID: String
    fileprivate var keys: [String]
}

public enum MeetingPolicy {
    public static let leadOptions = [5, 10, 15, 30]
    public static let defaultLead = 30
    /// Still say "starting now" for this long after the start.
    public static let startGrace: TimeInterval = 5 * 60

    static func short(_ title: String, max: Int = 28) -> String {
        let clean = title.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return clean.count <= max ? clean : String(clean.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func clock(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// The event happening right now, if any (all-day events never count). While one is, Mochi stays quiet.
    public static func inMeeting(now: Date, events: [CalendarEvent]) -> CalendarEvent? {
        events.first { $0.isHappening(at: now) }
    }

    /// A heads-up `leadMinutes` before a timed event, and again when it starts; each once per event.
    /// All-day events get none. Looks without consuming: call `commit` once it was shown.
    public static func headsUp(now: Date, events: [CalendarEvent], leadMinutes: Int, memory: MeetingMemory,
                               calendar: Calendar = .autoupdatingCurrent) -> MeetingNudge? {
        let lead = Double(max(1, leadMinutes)) * 60
        for e in events.filter({ !$0.isAllDay }).sorted(by: { $0.start < $1.start }) {
            let soon = e.id + ".soon", start = e.id + ".start"
            let title = short(e.title)
            if now >= e.start, now < e.start.addingTimeInterval(startGrace), !memory.notified.contains(start) {
                return MeetingNudge(kind: .start, text: "Starting now: \(title) 🌱", notificationTitle: "Starting now",
                                    notificationBody: e.title, eventID: e.id, keys: [soon, start])
            }
            let until = e.start.timeIntervalSince(now)
            if until > 0, until <= lead, !memory.notified.contains(soon) {
                let mins = max(1, Int((until / 60).rounded(.up)))
                return MeetingNudge(kind: .soon, text: "\(title) in \(mins) minute\(mins == 1 ? "" : "s") ☕️",
                                    notificationTitle: "In \(mins) min", notificationBody: e.title, eventID: e.id, keys: [soon])
            }
        }
        return nil
    }

    public static func commit(_ nudge: MeetingNudge, to memory: inout MeetingMemory) {
        memory.notified.formUnion(nudge.keys)
    }

    /// "You have 3 meetings today. First up: Standup at 10:00 🌱", or nil when none are left today.
    public static func morningSummary(now: Date, events: [CalendarEvent], calendar: Calendar = .autoupdatingCurrent) -> String? {
        let left = CalendarDays.meetings(events, on: now, calendar: calendar).filter { $0.end > now }
        guard let first = left.first else { return nil }
        let n = left.count
        return "You have \(n) meeting\(n == 1 ? "" : "s") today. First up: \(short(first.title)) at \(clock(first.start, calendar)) 🌱"
    }

    /// Whether the once-a-day summary is still unused today (and marks it used).
    public static func takeMorningSummary(now: Date, events: [CalendarEvent], memory: inout MeetingMemory,
                                          calendar: Calendar = .autoupdatingCurrent) -> String? {
        let day = calendar.startOfDay(for: now)
        guard memory.morningDay != day, let text = morningSummary(now: now, events: events, calendar: calendar) else { return nil }
        memory.morningDay = day
        return text
    }

    /// One line for the snapshot, e.g. "10:00–10:30 Standup; 14:00–15:00 Team sync" (all-day first).
    static func line(_ events: [CalendarEvent], calendar: Calendar, titleMax: Int = 60) -> String {
        events.map { e in
            let t = AgentSnapshot.clip(e.title, titleMax)
            return e.isAllDay ? "all day \(t)" : "\(clock(e.start, calendar))–\(clock(e.end, calendar)) \(t)"
        }.joined(separator: "; ")
    }
}
