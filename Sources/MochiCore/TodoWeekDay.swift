import Foundation

/// One day in the to-do card's week strip (today + the next 6 days).
public struct TodoWeekDay: Sendable, Equatable, Identifiable {
    /// Start of the day (local time).
    public var date: Date
    /// That day's to-dos, already ordered for display. For today this matches the
    /// "today" list (carried-over items first, done items last).
    public var items: [TodoItem]
    /// Unfinished to-dos on that day (drives the little dot in the strip).
    public var openCount: Int
    public var isToday: Bool
    /// That day's calendar events (all-day first, then by start time). Empty when calendars are off.
    public var events: [CalendarEvent]

    public var id: Date { date }

    public init(date: Date, items: [TodoItem], openCount: Int, isToday: Bool, events: [CalendarEvent] = []) {
        self.date = date
        self.items = items
        self.openCount = openCount
        self.isToday = isToday
        self.events = events
    }
}
