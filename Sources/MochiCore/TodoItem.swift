import Foundation

/// One to-do. Stored only on this Mac (see `TodoStore`); never sent anywhere.
public struct TodoItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    /// The day this to-do belongs to (start of day, local time).
    public var day: Date
    /// Exact time if the user gave one ("call mom 3pm"); nil for all-day to-dos.
    public var time: Date?
    public var done: Bool
    public var doneAt: Date?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, day: Date, time: Date? = nil,
                done: Bool = false, doneAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.day = day
        self.time = time
        self.done = done
        self.doneAt = doneAt
        self.createdAt = createdAt
    }

    /// True when the to-do is unfinished and its day is before `today`'s day.
    public func isCarriedOver(today: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        !done && day < calendar.startOfDay(for: today)
    }
}
