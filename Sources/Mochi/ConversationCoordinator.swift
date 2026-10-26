import AppKit
import Foundation
import Observation
import MochiCore

/// "Talk to Mochi": hold Mochi (or press the shortcut), talk, and Mochi answers in its speech bubble
/// (text only), then listens again for a follow-up. The loop is `ConversationMachine` (pure, checked);
/// speech is recognized on-device only (`VoiceListener`); the answer reuses Ask Mochi's guarded brain.
/// Nothing said is logged or saved, and the conversation is forgotten when it ends.
@MainActor @Observable
final class ConversationCoordinator {
    /// What the mascot should show.
    private(set) var isActive = false
    private(set) var isListening = false
    private(set) var isThinking = false
    /// The live transcript while listening.
    private(set) var liveText: String?
    /// True while the bubble should say "I'm listening…" (nothing from the last answer is on screen).
    private(set) var showsListeningPrompt = false

    @ObservationIgnored private let settings: MochiSettings
    @ObservationIgnored private let companion: Companion
    @ObservationIgnored private let context: AgentContext
    @ObservationIgnored private let listener = VoiceListener()
    @ObservationIgnored private var machine = ConversationMachine()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var ask: AskMochi?
    @ObservationIgnored private var tools: AgentTools?
    @ObservationIgnored private var lastReply: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private static let talkKeyID: UInt32 = 1
    private static let escKeyID: UInt32 = 2

    init(settings: MochiSettings, companion: Companion, context: AgentContext) {
        self.settings = settings
        self.companion = companion
        self.context = context
        listener.onLiveText = { [weak self] t in self?.heard(live: t) }
        listener.onSpeechStarted = { [weak self] in self?.send(.speechStarted(Date())) }
        listener.onFinal = { [weak self] t in self?.send(.finalTranscript(t, Date())) }
        listener.onFailure = { [weak self] f in self?.failed(f) }
    }

    // MARK: Entry points

    func start() {
        trackShortcut()
        let dist = DistributedNotificationCenter.default()
        let ws = NSWorkspace.shared.notificationCenter
        for (center, name) in [(dist as NotificationCenter, "com.apple.screenIsLocked"),
                               (ws, NSWorkspace.willSleepNotification.rawValue),
                               (ws, NSWorkspace.screensDidSleepNotification.rawValue)] {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt() }
            }
            observers.append((center, token))
        }
    }

    /// The shortcut: start, or end if a conversation is active.
    func toggle() {
        guard settings.talkEnabled, settings.showMascot || isActive else { return }
        send(.toggle(Date()))
    }

    func holdStart() {
        guard settings.talkEnabled, settings.talkHoldEnabled, settings.showMascot else { return }
        send(.holdStart(Date()))
    }

    func holdEnd() { send(.holdEnd(Date())) }

    /// Esc, a click on Mochi, the screen locking or the Mac sleeping.
    func interrupt() { send(.interrupt(Date())) }

    // MARK: Shortcut

    private func trackShortcut() {
        let on = withObservationTracking {
            settings.talkEnabled && settings.talkShortcutEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackShortcut() }
        }
        if on {
            GlobalHotKeys.shared.register(id: Self.talkKeyID, keyCode: GlobalHotKeys.talkKeyCode,
                                          modifiers: GlobalHotKeys.talkModifiers) { [weak self] in self?.toggle() }
        } else {
            GlobalHotKeys.shared.unregister(id: Self.talkKeyID)
        }
    }

    // MARK: Machine

    private func send(_ event: ConversationMachine.Event) {
        let actions = machine.handle(event)
        for action in actions {
            switch action {
            case .beginListening(let followUp): beginListening(followUp: followUp)
            case .finishListening: listener.stop()
            case .askBrain(let text): think(text)
            case .end(let reason): end(reason)
            }
        }
    }

    private func beginListening(followUp: Bool) {
        if !isActive {
            isActive = true
            generation += 1
            companion.beginConversation()
            GlobalHotKeys.shared.register(id: Self.escKeyID, keyCode: 53, modifiers: 0) { [weak self] in self?.interrupt() }
            tickTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.send(.tick(Date()))
                }
            }
        }
        isListening = true
        isThinking = false
        liveText = nil
        showsListeningPrompt = !followUp || lastReply == nil
        if !followUp { lastReply = nil; companion.setConversationText(nil) }
        listener.start()
    }

    private func heard(live: String) {
        guard isListening else { return }
        liveText = live
        showsListeningPrompt = false
    }

    private func think(_ text: String) {
        isListening = false
        isThinking = true
        liveText = nil
        companion.setConversationText("Hmm… 💭")
        let gen = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (reply, actions) = await self.answer(text)
            guard gen == self.generation, self.isActive else { return }
            var shown = reply
            if !actions.isEmpty { shown += "\n" + actions.joined(separator: " ") }
            self.lastReply = shown
            self.isThinking = false
            self.companion.setConversationText(shown)
            self.send(.replyReady(Date()))
        }
    }

    private func end(_ reason: ConversationMachine.EndReason) {
        listener.cancel()
        GlobalHotKeys.shared.unregister(id: Self.escKeyID)
        tickTask?.cancel()
        tickTask = nil
        ask?.cancel()
        ask = nil
        tools = nil
        generation += 1
        let reply = lastReply
        lastReply = nil
        isActive = false; isListening = false; isThinking = false; liveText = nil; showsListeningPrompt = false
        switch reason {
        case .goodbye, .noSpeech(afterReply: false): companion.endConversation(linger: "Talk soon! 🌱", seconds: 3)
        case .noSpeech(afterReply: true): companion.endConversation(linger: reply, seconds: 7)   // let the answer be read
        case .toggled, .interrupted, .timedOut: companion.endConversation(linger: nil, seconds: 0)
        }
    }

    private func failed(_ failure: VoiceListener.Failure) {
        let text: String
        switch failure {
        case .micDenied: text = "I need microphone access to listen. You can allow it in System Settings, Privacy & Security 💜"
        case .speechDenied: text = "I need Speech Recognition access to listen. You can allow it in System Settings, Privacy & Security 💜"
        case .unsupportedLanguage: text = "I can only listen on-device, and your language isn't supported yet 💜"
        case .failed: text = "I couldn't start listening just now 💜"
        }
        _ = machine.handle(.interrupt(Date()))
        end(.interrupted)
        companion.sayNotice(text, seconds: 9)
    }

    // MARK: Brain

    /// One turn: Ask Mochi's guarded model (tools, injection guards, meal ideas), or simple commands
    /// when Apple Intelligence isn't available.
    private func answer(_ text: String) async -> (String, [String]) {
        let modelReady = settings.smartMochi && SmartMochi.isAvailable
        if ask == nil { ask = AskMochi(context: context) }
        if tools == nil { tools = AgentTools(context: context) }
        guard let ask, let tools else { return (AskReply.hiccup, []) }

        if modelReady || MealRequest.isRequest(text) {
            ask.clearOutput()
            let state = await ask.askAndWait(text)
            return (state.reply ?? AskReply.hiccup, state.actionsTaken)
        }
        tools.beginTurn(userText: text)
        switch VoiceCommand.parse(text) {
        case .greeting: return ("Hi! I'm right here 🌱", [])
        case .addTodo(let item):
            let r = tools.addTodo(item)
            return (tools.actionsTaken.isEmpty ? r : "Done! 🌱", tools.actionsTaken)
        case .startFocus:
            let r = tools.startFocus()
            return (tools.actionsTaken.isEmpty ? r : "Let's focus! 🌱", tools.actionsTaken)
        case .startBreak:
            let r = tools.startBreak()
            return (tools.actionsTaken.isEmpty ? r : "Enjoy your break ☁️", tools.actionsTaken)
        case .mealIdea, nil:
            return ("I can chat more when Apple Intelligence is on ✨", [])
        }
    }
}
