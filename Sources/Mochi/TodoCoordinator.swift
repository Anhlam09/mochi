import CoreGraphics
import Foundation
import Observation
import MochiCore
import MochiUI

/// Bumped at midnight so views that show "left today" counts refresh.
@MainActor @Observable
final class DayClock {
    private(set) var day: Date
    init(now: Date = Date()) { day = Calendar.autoupdatingCurrent.startOfDay(for: now) }
    func update(_ now: Date) {
        let d = Calendar.autoupdatingCurrent.startOfDay(for: now)
        if d != day { day = d }
    }
}

/// Runs Mochi's to-do "agent": every 30 s, on every engine event and whenever the list changes it asks
/// `TodoAgent` whether to speak, then shows the line in the bubble and (for timed reminders) posts a
/// local notification. Everything stays on this Mac: no network, and titles are never logged.
@MainActor
final class TodoCoordinator {
    let store: TodoStore
    private let engine: TimerEngine
    private let settings: MochiSettings
    private let companion: Companion
    private let nudger: Nudger
    private let defaults: UserDefaults
    private var agent: TodoAgent
    private var card: TodoCardController?
    private let context: AgentContext
    /// A fresh Ask Mochi conversation per card-open; dropped when the card closes (nothing is kept).
    private var askMochi: AskMochi?
    let dayClock = DayClock()
    /// The "unreadable list" notice is shown until the card has been opened and closed once.
    private var recoveryPending: Bool
    private var loopTask: Task<Void, Never>?

    private static let memoryKey = "todoAgentMemory"
    static let loopEvery: Duration = .seconds(30)

    init(store: TodoStore, engine: TimerEngine, settings: MochiSettings, companion: Companion,
         nudger: Nudger, context: AgentContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.store = store
        self.engine = engine
        self.settings = settings
        self.companion = companion
        self.nudger = nudger
        self.defaults = defaults
        let memory = defaults.data(forKey: Self.memoryKey)
            .flatMap { try? JSONDecoder().decode(TodoAgentMemory.self, from: $0) } ?? TodoAgentMemory()
        self.agent = TodoAgent(memory: memory, calendar: .autoupdatingCurrent)
        self.recoveryPending = store.recoveredBackupURL != nil
    }

    /// The card is anchored to Mochi's floating panel, so it exists once the panel does.
    func attach(panel: FloatingPanelController) {
        card = TodoCardController(anchor: panel)
    }

    func start() {
        guard loopTask == nil else { return }
        trackStore()
        trackEnabled()
        loopTask = Task { @MainActor [weak self] in
            // Let the panel appear first.
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                self?.housekeeping()
                self?.evaluate(event: nil)
                try? await Task.sleep(for: Self.loopEvery, tolerance: .seconds(10))
            }
        }
    }

    func handle(_ event: EngineEvent) {
        evaluate(event: event)
    }

    /// Re-evaluates when the list changes (e.g. the last item ticked off), without polling.
    private func trackStore() {
        withObservationTracking {
            _ = store.items
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.evaluate(event: nil)
                self.trackStore()
            }
        }
    }

    /// Closes the card and clears any to-do bubble when the feature is switched off.
    private func trackEnabled() {
        let on = withObservationTracking {
            settings.todosEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackEnabled() }
        }
        if !on {
            card?.hide()
            companion.clearTodoLine()
        }
    }

    /// Every 30 s: roll the day over (badge count, daily prune) and retry a failed save.
    private func housekeeping() {
        let now = Date()
        let before = dayClock.day
        dayClock.update(now)
        if dayClock.day != before { store.pruneOldDone(now: now) }
        store.retrySaveIfNeeded()
    }

    // MARK: Agent

    private func evaluate(event: EngineEvent?) {
        guard settings.todosEnabled, !companion.conversationActive else { return }
        let now = Date()
        // Bubbles need Mochi on screen and someone in front of it; reminders still notify when away.
        let active = settings.showMascot && !Self.userAway
        let nudge = agent.decide(now: now, items: store.items, phase: engine.phase, event: event,
                                 userActive: active, settings: settings.todoAgent)
        saveMemory()
        guard let nudge else { return }
        if nudge.showBubble {
            companion.sayTodo(Chatter.fill(nudge.text, name: settings.friendName), longer: nudge.openCard) { [weak self] in
                self?.openCard()
            }
        }
        if let title = nudge.notificationTitle {
            if settings.todoNotificationText {
                nudger.postTodoReminder(id: nudge.itemID, title: title, body: nudge.notificationBody ?? "")
            } else {
                nudger.postTodoReminder(id: nudge.itemID, title: "⏰ You have a to-do now", body: "")
            }
        }
    }

    private var savedMemory: TodoAgentMemory?
    private func saveMemory() {
        guard savedMemory != agent.memory else { return }
        savedMemory = agent.memory
        if let data = try? JSONEncoder().encode(agent.memory) { defaults.set(data, forKey: Self.memoryKey) }
    }

    private static var userAway: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            >= Companion.awayAfter
    }

    // MARK: Card

    /// Opens the card, or leaves it open if it already is (the menu row uses this).
    func openCard() {
        guard settings.todosEnabled, let card else { return }
        companion.clearTodoLine()
        if !card.isVisible { askMochi = settings.smartMochi ? AskMochi(context: context) : nil }
        card.show(items: { [store] in store.todayList(now: Date()) },
                  later: { [store] in store.laterList(now: Date()) },
                  now: { Date() },
                  showMoveToTomorrow: { [weak self] in self?.shouldOfferMoveToTomorrow ?? false },
                  notice: { [weak self] in self?.notice },
                  ask: { [weak self] in self?.askState },
                  week: { [store] in store.week(now: Date()) },
                  actions: actions)
    }

    /// The mascot badge toggles the card.
    func toggleCard() {
        guard let card else { return }
        if card.isVisible { cardClosed(); card.hide() } else { openCard() }
    }

    private func cardClosed() {
        recoveryPending = false
        askMochi?.cancel()
        askMochi = nil
    }

    /// The card's "start over" in Ask Mochi.
    func resetAsk() { askMochi?.reset() }

    /// What the card's Ask tab shows: nil hides it (Smart Mochi off), a reason when unavailable.
    private var askState: AskMochiState? {
        guard settings.smartMochi else { return nil }
        if let reason = SmartMochi.unavailableReason() { return AskMochiState(unavailableReason: reason) }
        return askMochi?.state
    }

    /// A short warning inside the card when the list can't be saved or had to be recovered.
    var notice: String? {
        if store.saveFailed { return "Couldn't save your list. Changes may not stick ⚠️" }
        if recoveryPending { return "Your old list was unreadable, so I saved a backup and started fresh 🌱" }
        return nil
    }

    /// The "Move to tomorrow" pill appears once something is left over from before, or at wrap-up time.
    private var shouldOfferMoveToTomorrow: Bool {
        let now = Date()
        let open = store.todayList(now: now).filter { !$0.done }
        guard !open.isEmpty else { return false }
        if open.contains(where: { $0.isCarriedOver(today: now) }) { return true }
        let s = settings.todoAgent
        guard let at = Calendar.autoupdatingCurrent.date(bySettingHour: s.wrapUpHour, minute: s.wrapUpMinute, second: 0, of: now) else { return false }
        return now >= at
    }

    /// Adds from the card. `day` is the day picked in the card (a day typed in the text still
    /// wins); a to-do that lands on a later day only because of the text gets a confirmation bubble.
    private func add(_ text: String, day: Date? = nil) {
        let now = Date()
        guard let item = store.add(text, now: now, defaultDay: day) else { return }
        let cal = Calendar.autoupdatingCurrent
        guard day == nil, item.day > cal.startOfDay(for: now), settings.showMascot else { return }
        companion.sayTodo("Added for \(TodoList.dayLabel(item.day, now: now, calendar: cal)) 🌱", longer: false) { [weak self] in
            self?.openCard()
        }
    }

    private var actions: TodoCardActions {
        TodoCardActions(
            add: { [weak self] in self?.add($0) },
            toggle: { [store] in store.toggle(id: $0, now: Date()) },
            delete: { [store] in store.delete(id: $0) },
            moveUnfinishedToTomorrow: { [store] in store.moveUnfinishedToTomorrow(now: Date()) },
            close: { [weak self] in self?.cardClosed() },
            ask: { [weak self] in self?.askMochi?.ask($0) },
            addOnDay: { [weak self] text, day in self?.add(text, day: day) },
            resetAsk: { [weak self] in self?.resetAsk() }
        )
    }
}
