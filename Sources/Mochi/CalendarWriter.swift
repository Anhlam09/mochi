import EventKit
import Foundation
import MochiCore

/// Adds ONE new event to the user's calendar when they tap 📅 on a to-do.
///
/// Write policy: the only write API used anywhere in Mochi is `EKEventStore.save(_:span:commit:)` on an
/// `EKEvent` created right here from a to-do. Existing events are never modified or deleted, nothing is
/// ever removed, and the new event has no alarms, invitees or notes. Reading stays in `CalendarSource`.
@MainActor
final class CalendarWriter {
    /// Where to connect Google (Internet Accounts) in System Settings.
    static let internetAccountsURL = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!

    enum Failure: Error { case noEvent, noWritableCalendar }

    private let source: CalendarSource
    private let settings: MochiSettings

    init(source: CalendarSource, settings: MochiSettings) {
        self.source = source
        self.settings = settings
    }

    // MARK: Calendars

    private var allCalendars: [EKCalendar] {
        source.status == .authorized ? source.store.calendars(for: .event) : []
    }

    private static func describe(_ c: EKCalendar) -> CalendarDescriptor {
        let kind: CalendarDescriptor.SourceKind
        switch c.source?.sourceType {
        case .calDAV: kind = .calDAV
        case .local: kind = .local
        case .exchange: kind = .exchange
        case .subscribed: kind = .subscribed
        case .birthdays: kind = .birthdays
        default: kind = .other
        }
        return CalendarDescriptor(id: c.calendarIdentifier, title: c.title, sourceTitle: c.source?.title ?? "", sourceKind: kind,
                                  allowsModifications: c.allowsContentModifications,
                                  isSubscription: c.isSubscribed || c.type == .subscription || c.type == .birthday)
    }

    /// Calendars Mochi may add to (writable; no subscriptions, birthdays or holidays).
    var writableCalendars: [CalendarDescriptor] { CalendarTarget.writable(allCalendars.map(Self.describe)) }

    private var targetID: String? {
        let defaultID = source.status == .authorized ? source.store.defaultCalendarForNewEvents?.calendarIdentifier : nil
        return CalendarTarget.choose(from: allCalendars.map(Self.describe), defaultID: defaultID, preferredID: settings.calendarAddTarget)
    }

    /// Calendars on, access granted, and somewhere to write.
    var canAdd: Bool { settings.calendarEnabled && source.status == .authorized && targetID != nil }

    /// Whether access is there but there is nowhere writable (e.g. only a read-only subscription).
    var hasNoWritableCalendar: Bool { source.status == .authorized && targetID == nil }

    // MARK: Writing

    /// Creates the event and returns its identifier.
    func add(_ item: TodoItem) throws -> String {
        guard let id = targetID, let calendar = source.store.calendar(withIdentifier: id) else { throw Failure.noWritableCalendar }
        let spec = CalendarEventSpec.make(for: item)
        let event = EKEvent(eventStore: source.store)
        event.calendar = calendar
        event.title = spec.title
        event.isAllDay = spec.isAllDay
        event.startDate = spec.start
        event.endDate = spec.end
        // No alarms, attendees or notes are ever set.
        try source.store.save(event, span: .thisEvent, commit: true)
        guard let eventID = event.eventIdentifier else { throw Failure.noEvent }
        return eventID
    }
}
