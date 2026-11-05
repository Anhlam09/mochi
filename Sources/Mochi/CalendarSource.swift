import AppKit
import EventKit
import Foundation
import Observation
import MochiCore

enum CalendarStatus: Equatable {
    case off, notDetermined, denied, authorized
}

/// READ-ONLY view of the Mac's Calendar app (EventKit; Google works if it was added in System Settings,
/// Internet Accounts). Events from the start of today to 7 days ahead are held in memory only: never
/// saved, never logged, never sent anywhere. Mochi never creates, edits or deletes events.
@MainActor @Observable
final class CalendarSource {
    private(set) var events: [CalendarEvent] = []
    private(set) var status: CalendarStatus = .off

    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private let settings: MochiSettings
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var lastDay = Calendar.autoupdatingCurrent.startOfDay(for: Date())

    static let refreshEvery: Duration = .seconds(300)
    static let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!

    init(settings: MochiSettings) {
        self.settings = settings
        status = Self.currentStatus(enabled: settings.calendarEnabled)
    }

    /// What the rest of Mochi uses: nothing unless the user turned calendars on and allowed access.
    var activeEvents: [CalendarEvent] { settings.calendarEnabled && status == .authorized ? events : [] }

    func inMeeting(_ now: Date = Date()) -> CalendarEvent? { MeetingPolicy.inMeeting(now: now, events: activeEvents) }
    var isInMeeting: Bool { inMeeting() != nil }
    func currentMeetingEnd(_ now: Date = Date()) -> Date? { inMeeting(now)?.end }

    func start() {
        // Permission is never requested here: only when the user turns the setting on.
        trackEnabled(initial: true)
        refresh()
        let ws = NSWorkspace.shared.notificationCenter
        for (center, name) in [(NotificationCenter.default, EKEventStore.changedNotificationName),
                               (ws, NSWorkspace.didWakeNotification.rawValue)] {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((center, token))
        }
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshEvery, tolerance: .seconds(30))
                self?.refresh()
            }
        }
    }

    private func trackEnabled(initial: Bool) {
        let on = withObservationTracking {
            settings.calendarEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackEnabled(initial: false) }
        }
        if initial {
            // Turned on but never answered (e.g. the setting was on before the prompt could show):
            // ask now. If the user already said yes or no, this does nothing.
            if on, Self.rawStatus() == .notDetermined { Task { await requestAccess() } }
            return
        }
        if on {
            Task { await requestAccess() }
        } else {
            events = []
            status = .off
        }
    }

    /// Asks macOS for (read) access to the calendar. Called when the user turns the setting on.
    func requestAccess() async {
        if Self.rawStatus() == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        refresh()
    }

    func refresh() {
        let now = Date()
        let cal = Calendar.autoupdatingCurrent
        lastDay = cal.startOfDay(for: now)
        status = Self.currentStatus(enabled: settings.calendarEnabled)
        guard status == .authorized else { events = []; return }
        let end = cal.date(byAdding: .day, value: 7, to: lastDay)!
        let predicate = store.predicateForEvents(withStart: lastDay, end: end, calendars: nil)
        events = store.events(matching: predicate).compactMap(Self.map)
    }

    // MARK: Mapping

    private nonisolated static func rawStatus() -> EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    private static func currentStatus(enabled: Bool) -> CalendarStatus {
        guard enabled else { return .off }
        switch rawStatus() {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Skips canceled events and ones the user declined.
    private static func map(_ e: EKEvent) -> CalendarEvent? {
        if e.status == .canceled { return nil }
        if e.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined { return nil }
        guard let start = e.startDate, let end = e.endDate else { return nil }
        let id = (e.eventIdentifier ?? UUID().uuidString) + "@" + String(Int(start.timeIntervalSince1970))
        return CalendarEvent(id: id, title: e.title ?? "Busy", start: start, end: end, isAllDay: e.isAllDay, colorHex: hex(e.calendar?.cgColor))
    }

    private static func hex(_ cg: CGColor?) -> String? {
        guard let cg, let c = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

extension EKEventStore {
    /// `.EKEventStoreChanged` as a plain name string.
    static var changedNotificationName: String { Notification.Name.EKEventStoreChanged.rawValue }
}

/// Meeting heads-ups ("Team sync in 30 minutes ☕️", "Starting now") and the once-a-day morning summary.
/// `MeetingPolicy` (pure, checked) decides when; this shows the line, or a notification when the mascot
/// is hidden or you are away. Only event ids are remembered, never titles.
@MainActor
final class MeetingCoordinator {
    private let calendar: CalendarSource
    private let settings: MochiSettings
    private let companion: Companion
    private let engine: TimerEngine
    private let nudger: Nudger
    private var memory = MeetingMemory()
    private var loopTask: Task<Void, Never>?
    var openCard: () -> Void = {}

    init(calendar: CalendarSource, settings: MochiSettings, companion: Companion, engine: TimerEngine, nudger: Nudger) {
        self.calendar = calendar
        self.settings = settings
        self.companion = companion
        self.engine = engine
        self.nudger = nudger
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                self?.evaluate(Date())
                try? await Task.sleep(for: .seconds(30), tolerance: .seconds(10))
            }
        }
    }

    /// The summary line for the morning greeting, once per day (nil when there are no meetings).
    func takeMorningSummary() -> String? {
        MeetingPolicy.takeMorningSummary(now: Date(), events: calendar.activeEvents, memory: &memory)
    }

    private func evaluate(_ now: Date) {
        guard settings.calendarEnabled else { return }
        guard let nudge = MeetingPolicy.headsUp(now: now, events: calendar.activeEvents, leadMinutes: settings.meetingLeadMinutes,
                                                memory: memory) else { return }
        let away = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            >= Companion.awayAfter
        var breakDue = false
        if case .breakDue = engine.phase { breakDue = true }

        if settings.showMascot, !away {
            // Shown in the bubble; waits (not consumed) during a break prompt or a voice chat.
            guard !breakDue, !companion.conversationActive else { return }
            companion.sayTodo(nudge.text, longer: false) { [weak self] in self?.openCard() }
        } else if settings.todoNotificationText {
            nudger.postMeetingReminder(id: nudge.eventID, title: nudge.notificationTitle, body: nudge.notificationBody)
        } else {
            nudger.postMeetingReminder(id: nudge.eventID, title: "⏰ You have a meeting soon", body: "")
        }
        MeetingPolicy.commit(nudge, to: &memory)
    }
}
