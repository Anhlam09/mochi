import Foundation

/// A meeting or event read (read-only) from the Mac's Calendar app via EventKit. It stays in memory:
/// never written to disk, never sent anywhere, and titles are never logged.
public struct CalendarEvent: Sendable, Equatable, Identifiable {
    /// EventKit's identifier plus the start time (recurring events share an identifier).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The calendar's color as "#RRGGBB", for a small dot in the list.
    public var colorHex: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.colorHex = colorHex
    }

    /// True while the event is happening (all-day events never count as "in a meeting").
    public func isHappening(at now: Date) -> Bool {
        !isAllDay && start <= now && now < end
    }
}
