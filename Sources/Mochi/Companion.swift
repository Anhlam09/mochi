import CoreGraphics
import Foundation
import Observation
import MochiCore
import MochiUI

/// Mochi's friendly voice: greets once a day, checks in now and then, and reacts to breaks,
/// returns and taps. Lines show in the mascot's speech bubble for a few seconds.
@MainActor @Observable
final class Companion {
    /// The line Mochi is saying right now, if any.
    private(set) var message: String?

    /// A to-do line (reminder, check-in...). It outranks chatter and keeps the bubble until it expires or is tapped.
    private(set) var todoLine: String?

    @ObservationIgnored private var todoTap: (() -> Void)?
    @ObservationIgnored private var todoClearTask: Task<Void, Never>?
    @ObservationIgnored private let engine: TimerEngine
    @ObservationIgnored private let settings: MochiSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var chatter = Chatter()
    @ObservationIgnored private var nextChat: Date?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    /// `MOCHI_CHAT_SECONDS` shortens the gap between unprompted lines (demo mode).
    @ObservationIgnored private let intervalOverride: TimeInterval?

    static let showFor: TimeInterval = 12
    /// How often Mochi spins into a new colour flavour.
    static let flavorEvery: TimeInterval = 2 * 3600
    private static let flavorKey = "lastFlavorChange"
    /// `MOCHI_FLAVOR_SECONDS` shortens the flavour interval (demo mode).
    @ObservationIgnored private let flavorOverride = ProcessInfo.processInfo.environment["MOCHI_FLAVOR_SECONDS"].flatMap(Double.init)
    /// The first unprompted line comes soon after launch, not a whole interval later.
    static let firstChatAfter: TimeInterval = 45
    /// At most one hover hello this often, so the time-left pill still shows most of the time.
    static let helloGap: TimeInterval = 2 * 60
    @ObservationIgnored private var lastHello: Date?
    private static let greetingKey = "lastGreeting"

    init(engine: TimerEngine, settings: MochiSettings, defaults: UserDefaults = .standard,
         intervalOverride: TimeInterval? = nil) {
        self.engine = engine
        self.settings = settings
        self.defaults = defaults
        self.intervalOverride = intervalOverride
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            // Let the panel appear before the first hello.
            try? await Task.sleep(for: .seconds(2))
            self?.launchHello(Date())
            while !Task.isCancelled {
                self?.tick(Date())
                // Loose tolerance lets macOS batch this wake-up with others (saves battery).
                try? await Task.sleep(for: .seconds(15), tolerance: .seconds(10))
            }
        }
    }

    /// Says hi every time Mochi opens (good morning on a new day), and chats again soon after.
    private func launchHello(_ now: Date) {
        guard settings.chat != .off, settings.showMascot else { return }
        if !greetIfNewDay(now) { say(.hello) }
        lastHello = now
        nextChat = now.addingTimeInterval(min(Self.firstChatAfter, intervalOverride ?? .infinity))
    }

    func handle(_ event: EngineEvent) {
        if event == .breakCompleted { say(.breakDone) }
    }

    /// Back from idle, lock or sleep: a new day's hello, or a welcome back.
    /// After 10+ minutes away (and with the wake greeting on) it's the day-part-and-date greeting instead.
    func userReturned(awayFor: TimeInterval) {
        let now = Date()
        if settings.wakeGreeting, settings.showMascot, settings.chat != .off, isQuiet,
           WakeGreeting.shouldGreet(awayFor: awayFor), !breakIsDue {
            defaults.set(now, forKey: Self.greetingKey)   // this counts as today's hello: no second greeting
            show(WakeGreeting.line(now: now, name: settings.friendName))
            return
        }
        if !greetIfNewDay(now) { say(.welcomeBack) }
    }

    private var breakIsDue: Bool {
        switch engine.phase {
        case .breakDue: true
        default: false
        }
    }

    /// A line from the little extras (good night, meals, self-care). Respects "Mochi talks to you: Off".
    /// False if something else is on screen or the mascot is hidden, so the caller keeps its slot.
    @discardableResult
    func sayExtra(_ line: String) -> Bool {
        guard settings.showMascot, settings.chat != .off, isQuiet, !breakIsDue else { return false }
        show(line)
        return true
    }

    /// The mouse moved over Mochi: say hi if it's quiet and it's been a while.
    func hovered() {
        let now = Date()
        guard message == nil, canChatNow,
              lastHello.map({ now.timeIntervalSince($0) >= Self.helloGap }) ?? true else { return }
        lastHello = now
        say(.hello)
    }

    /// Says a line for `moment` now (unless chatting is off) and pushes back the next check-in.
    func say(_ moment: ChatMoment) {
        guard settings.chat != .off else { return }
        chatter.name = settings.friendName
        show(chatter.line(for: moment, at: Date()))
    }

    /// Shows a to-do line. Random chatter can't overwrite it while it's up; tapping Mochi runs `onTap`.
    /// `longer`: the line waits for a tap (check-in, wrap-up), so it stays up longer.
    func sayTodo(_ text: String, longer: Bool, onTap: @escaping () -> Void) {
        lastLineAt = Date()
        todoLine = text
        todoTap = onTap
        todoClearTask?.cancel()
        todoClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(longer ? 20 : Self.showFor))
            guard !Task.isCancelled else { return }
            self?.clearTodoLine()
        }
    }

    /// Nothing is being said right now (no chatter, no to-do line).
    var isQuiet: Bool { message == nil && todoLine == nil }

    /// A kind line from the positivity policy. To-do lines and chatter win: it is dropped (false) if
    /// something is already showing, so the caller doesn't use up its slot.
    @discardableResult
    func sayPositive(_ line: String) -> Bool {
        guard isQuiet, settings.chat != .off else { return false }
        show(line)
        return true
    }

    /// The fixed cheer lines (used when the on-device model is off or unavailable). False if not shown.
    @discardableResult
    func sayCheer() -> Bool {
        guard isQuiet, settings.chat != .off else { return false }
        say(.cheer)
        return true
    }

    /// A plain notice (the first-launch welcome): outranks chatter like a to-do line, but a tap on
    /// Mochi still does its normal thing. Shown even when chat is Off.
    func sayNotice(_ text: String, seconds: TimeInterval) {
        lastLineAt = Date()
        todoLine = text
        todoTap = nil
        todoClearTask?.cancel()
        todoClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.clearTodoLine()
        }
    }

    func clearTodoLine() {
        todoClearTask?.cancel()
        todoLine = nil
        todoTap = nil
    }

    /// If a to-do line is showing, runs its tap action (and dismisses it). Returns whether it did.
    func consumeTodoTap() -> Bool {
        guard todoLine != nil, let tap = todoTap else { return false }
        clearTodoLine()
        tap()
        return true
    }

    /// When any line (chatter, to-do, welcome, extras) was last put in the bubble.
    @ObservationIgnored private(set) var lastLineAt: Date?

    private func show(_ line: String) {
        guard todoLine == nil else { return }
        let now = Date()
        lastLineAt = now
        message = line
        scheduleNext(from: now)
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.showFor))
            guard !Task.isCancelled, let self, self.message == line else { return }
            self.message = nil
        }
    }

    private func tick(_ now: Date) {
        guard settings.showMascot, !userAway else { return }
        rotateFlavorIfDue(now)
        guard settings.chat != .off, canChatNow else { return }
        if greetIfNewDay(now) { return }
        guard let nextChat else { scheduleNext(from: now); return }
        if now >= nextChat { say([.checkIn, .checkIn, .cheer, .cheer, .funFact].randomElement()!) }
    }

    /// Every couple of hours (while you're here to see it), spin into the next flavour and say so.
    private func rotateFlavorIfDue(_ now: Date) {
        guard settings.flavorRotation, canChatNow else { return }
        guard let last = defaults.object(forKey: Self.flavorKey) as? Date else {
            defaults.set(now, forKey: Self.flavorKey)   // start counting from first launch
            return
        }
        guard now.timeIntervalSince(last) >= (flavorOverride ?? Self.flavorEvery) else { return }
        defaults.set(now, forKey: Self.flavorKey)
        let next = (MochiFlavor(rawValue: settings.flavor) ?? .strawberry).next
        settings.flavor = next.rawValue
        if settings.chat != .off { show(chatter.flavorLine(name: next.displayName, emoji: next.emoji)) }
    }

    /// No keyboard or mouse for a while (or the screen is locked): nobody is there to read it.
    private var userAway: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            >= Self.awayAfter
    }
    static let awayAfter: TimeInterval = 120

    /// Only chat when Mochi isn't already busy with a break or about to call one.
    private var canChatNow: Bool {
        switch engine.phase {
        case .idle: true
        case .focusing: engine.remaining > TimerEngine.almostDoneWindow
        case .breakDue, .snoozed, .onBreak, .paused: false
        }
    }

    @discardableResult
    private func greetIfNewDay(_ now: Date) -> Bool {
        guard settings.chat != .off,
              ChatSchedule.needsGreeting(lastGreeting: defaults.object(forKey: Self.greetingKey) as? Date, now: now)
        else { return false }
        defaults.set(now, forKey: Self.greetingKey)
        if settings.wakeGreeting {
            // Same format as coming back to the Mac, so there is only ever one kind of greeting.
            chatter.name = settings.friendName
            show(WakeGreeting.line(now: now, name: settings.friendName))
        } else {
            say(.greeting)
        }
        return true
    }

    private func scheduleNext(from now: Date) {
        guard let interval = intervalOverride ?? settings.chat.interval else { nextChat = nil; return }
        nextChat = ChatSchedule.next(after: now, interval: interval, jitter: .random(in: 0...1))
    }
}
