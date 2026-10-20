import Foundation

/// Settings the agent policy reads (stored in `MochiSettings`).
public struct TodoAgentSettings: Sendable, Equatable {
    public var todosEnabled: Bool
    public var wrapUpHour: Int
    public var wrapUpMinute: Int
    /// Off: only the morning list and timed reminders.
    public var nudges: Bool

    public init(todosEnabled: Bool = true, wrapUpHour: Int = 17, wrapUpMinute: Int = 30, nudges: Bool = true) {
        self.todosEnabled = todosEnabled
        self.wrapUpHour = wrapUpHour
        self.wrapUpMinute = wrapUpMinute
        self.nudges = nudges
    }
}

public enum TodoNudgeKind: Sendable, Equatable {
    case reminderSoon, reminderNow, checkIn, wrapUp, morning, breakSuggestion, celebrate
}

public struct TodoNudge: Sendable, Equatable {
    public var kind: TodoNudgeKind
    /// Bubble line. May contain `{name}`; the caller runs it through `Chatter.fill`.
    public var text: String
    /// A follow-up card is expected (check-in, wrap-up): the caller keeps the bubble up longer.
    /// Tapping any to-do bubble opens the card.
    public var openCard: Bool
    /// Show the line in the bubble (false when the user is away or a break is waiting).
    public var showBubble: Bool
    /// Local notification body (the to-do's title only), for timed reminders.
    public var notificationTitle: String?
    public var notificationBody: String?
    public var itemID: UUID?

    public init(kind: TodoNudgeKind, text: String, openCard: Bool = false, showBubble: Bool = true,
                notificationTitle: String? = nil, notificationBody: String? = nil, itemID: UUID? = nil) {
        self.kind = kind; self.text = text; self.openCard = openCard; self.showBubble = showBubble
        self.notificationTitle = notificationTitle; self.notificationBody = notificationBody; self.itemID = itemID
    }
}

/// What Mochi has already said. Holds ids, days and counts only, never titles.
public struct TodoAgentMemory: Codable, Equatable, Sendable {
    public var morningDay: Date?
    public var wrapUpDay: Date?
    public var celebrateDay: Date?
    public var pendingCelebrate = false
    public var lastLeft: Int?
    public var lastDone: Int?
    public var lastLeftDay: Date?
    /// "<uuid>.<yyyymmdd>.soon" / ".now"
    public var reminded: Set<String> = []
    /// item id -> day it was last asked about
    public var checkedIn: [String: Date] = [:]
    public var lastCheckIn: Date?
    public init() {}
}

/// Mochi's local, rule-based to-do "agent": decides if and what to say. No AI, no network.
/// Priority: timed reminder > celebrate > check-in > wrap-up > morning > break suggestion.
/// The check-in and the break suggestion both ride on `.breakStarted`; only one shows per break.
/// No bubble is ever produced during `.breakDue` (reminders then notify only).
public struct TodoAgent: Sendable {
    public var memory: TodoAgentMemory
    public var calendar: Calendar
    /// 0..<1; injected so checks are deterministic.
    public var random: @Sendable () -> Double

    public static let morningHour = 6
    public static let reminderLead: TimeInterval = 10 * 60
    /// Stop reminding about a timed item this long after its time.
    public static let reminderGrace: TimeInterval = 60 * 60
    public static let minBreakForSuggestion: TimeInterval = 5 * 60
    public static let checkInGap: TimeInterval = 60 * 60

    public init(memory: TodoAgentMemory = .init(), calendar: Calendar = .autoupdatingCurrent,
                random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }) {
        self.memory = memory
        self.calendar = calendar
        self.random = random
    }

    public mutating func decide(now: Date, items: [TodoItem], phase: Phase, event: EngineEvent?,
                                userActive: Bool, settings: TodoAgentSettings) -> TodoNudge? {
        guard settings.todosEnabled else { return nil }
        let today = calendar.startOfDay(for: now)
        let list = TodoList.today(items, now: now, calendar: calendar)
        let open = list.filter { !$0.done }
        let done = list.count - open.count
        housekeeping(today: today, items: items)

        // Track the left-count so ticking off the last item can be celebrated.
        // Only a real tick (done went up) of the last open item counts: not a delete, add or move.
        if let prev = memory.lastLeft, prev > 0, open.isEmpty, done > (memory.lastDone ?? .max), memory.celebrateDay != today {
            memory.pendingCelebrate = true
        }
        if !open.isEmpty { memory.pendingCelebrate = false }
        memory.lastLeft = open.count
        memory.lastDone = done

        var isDue = false
        if case .breakDue = phase { isDue = true }

        // 1. Timed reminders (also while the user is away: notification only).
        if let n = reminder(now: now, today: today, open: open, showBubble: userActive && !isDue) { return n }

        guard userActive else { return nil }

        // 2. Celebrate / check-in / wrap-up / morning / break suggestion.
        if settings.nudges, !isDue, memory.pendingCelebrate {
            memory.pendingCelebrate = false
            memory.celebrateDay = today
            return TodoNudge(kind: .celebrate, text: "All done for today! 🎉 You're amazing ✨")
        }
        if settings.nudges, event == .breakStarted, !isDue, now.timeIntervalSince(memory.lastCheckIn ?? .distantPast) >= Self.checkInGap,
           let item = open.first(where: { memory.checkedIn[$0.id.uuidString] != today }) {
            memory.checkedIn[item.id.uuidString] = today
            memory.lastCheckIn = now
            return TodoNudge(kind: .checkIn, text: "Did you get to '\(Self.short(item.title))'? Tap me to tick it off ✅",
                             openCard: true, itemID: item.id)
        }
        if isDue { return nil }

        if settings.nudges, memory.wrapUpDay != today,
           let at = calendar.date(bySettingHour: settings.wrapUpHour, minute: settings.wrapUpMinute, second: 0, of: today),
           now >= at {
            memory.wrapUpDay = today
            if open.isEmpty, done > 0 {
                return TodoNudge(kind: .wrapUp, text: "You finished \(Self.things(done)) today 🎉", openCard: true)
            }
            if !open.isEmpty {
                let text = done > 0
                    ? "Finished \(done) today 🎉 \(open.count) left: move to tomorrow? Tap me 🌙"
                    : "\(open.count) left, move them to tomorrow? Tap me 🌙"
                return TodoNudge(kind: .wrapUp, text: text, openCard: true)
            }
        }
        if memory.morningDay != today, calendar.component(.hour, from: now) >= Self.morningHour {
            memory.morningDay = today
            // A first sighting after noon is no longer "morning": stay quiet.
            if !open.isEmpty, calendar.component(.hour, from: now) < 12 {
                return TodoNudge(kind: .morning, text: "Good morning! \(Self.things(open.count)) today 🌱 Tap me to see!")
            }
        }
        if settings.nudges, event == .breakStarted, case .onBreak(let end) = phase,
           end.timeIntervalSince(now) >= Self.minBreakForSuggestion - 10,
           let item = open.first(where: { $0.time == nil }), random() < 0.5 {
            return TodoNudge(kind: .breakSuggestion, text: "Quick win while you rest? ✨ \(Self.short(item.title))",
                             itemID: item.id)
        }
        return nil
    }

    // MARK: Pieces

    private mutating func housekeeping(today: Date, items: [TodoItem]) {
        if memory.lastLeftDay != today {
            memory.lastLeftDay = today
            memory.lastLeft = nil
            memory.lastDone = nil
            memory.pendingCelebrate = false
            memory.checkedIn = memory.checkedIn.filter { $0.value >= today }
        }
        let ids = Set(items.map { $0.id.uuidString })
        memory.reminded = memory.reminded.filter { ids.contains(String($0.prefix(36))) }
        memory.checkedIn = memory.checkedIn.filter { ids.contains($0.key) }
    }

    private mutating func reminder(now: Date, today: Date, open: [TodoItem], showBubble: Bool) -> TodoNudge? {
        let timed = open.filter { $0.day == today && $0.time != nil }.sorted { $0.time! < $1.time! }
        for item in timed {
            let time = item.time!
            let id = item.id.uuidString
            // The day is part of the key: a to-do moved to another day reminds again.
            let ymd = calendar.dateComponents([.year, .month, .day], from: item.day)
            let tag = "\(id).\((ymd.year ?? 0) * 10000 + (ymd.month ?? 0) * 100 + (ymd.day ?? 0))"
            let soon = tag + ".soon", at = tag + ".now"
            let title = Self.short(item.title)
            if now >= time, now < time.addingTimeInterval(Self.reminderGrace), !memory.reminded.contains(at) {
                memory.reminded.formUnion([soon, at])
                return TodoNudge(kind: .reminderNow, text: "⏰ Now: \(title)", showBubble: showBubble,
                                 notificationTitle: "⏰ Now", notificationBody: item.title, itemID: item.id)
            }
            let lead = time.timeIntervalSince(now)
            if lead > 0, lead <= Self.reminderLead, !memory.reminded.contains(soon) {
                memory.reminded.insert(soon)
                let mins = max(1, Int((lead / 60).rounded(.up)))
                return TodoNudge(kind: .reminderSoon, text: "⏰ In \(mins) min: \(title)", showBubble: showBubble,
                                 notificationTitle: "⏰ In \(mins) min", notificationBody: item.title, itemID: item.id)
            }
        }
        return nil
    }

    /// Short, placeholder-safe title for the bubble.
    static func short(_ title: String, max: Int = 28) -> String {
        let clean = title.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
        return clean.count <= max ? clean : String(clean.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func things(_ n: Int) -> String { n == 1 ? "1 thing" : "\(n) things" }
}
