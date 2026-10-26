import Foundation

// "Talk to Mochi": the pure parts of the voice conversation. Audio and speech recognition live in the
// app target and run on-device only; nothing here touches the microphone, the disk or the network.

public enum Goodbye {
    private static let phrases = ["bye", "goodbye", "good bye", "bye bye", "that's all", "thats all", "that is all",
                                  "that's it", "thats it", "that is it", "stop listening", "never mind", "nevermind",
                                  "see you", "talk later", "talk to you later", "i'm done", "im done", "we're done"]

    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    /// "bye", "that's all", "thank you, that's it"... in a short utterance (long sentences that merely
    /// contain a phrase, like "add bye bye to my list", don't count).
    public static func isGoodbye(_ text: String) -> Bool {
        let w = words(text)
        guard !w.isEmpty, w.count <= 8 else { return false }
        let joined = w.joined(separator: " ")
        guard phrases.contains(where: { joined.contains($0) }) else { return false }
        // "add bye ..." / "remind me to say bye" are requests, not farewells.
        let blockers = ["add", "remind", "remember", "note", "write", "put"]
        return !w.contains(where: blockers.contains)
    }
}

public enum VoiceCommand: Equatable, Sendable {
    case greeting
    case mealIdea
    case startFocus
    case startBreak
    case addTodo(String)

    /// The no-AI fallback: a few simple spoken commands.
    public static func parse(_ text: String) -> VoiceCommand? {
        var l = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?")))
        for lead in ["hey mochi,", "hey mochi", "hi mochi,", "hi mochi", "okay mochi", "ok mochi", "mochi,", "mochi", "please"] where l.hasPrefix(lead + " ") || l == lead {
            l = String(l.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
        }
        guard !l.isEmpty else { return .greeting }
        if MealRequest.isRequest(l) { return .mealIdea }
        if l.contains("take a break") || l.contains("start a break") || l.contains("start my break") || l.contains("i need a break")
            || l.contains("break time") { return .startBreak }
        if (l.contains("start") || l.contains("begin")) && l.contains("focus") || l.contains("focus session") || l == "focus" {
            return .startFocus
        }
        for prefix in ["remind me to ", "remind me ", "add a to-do to ", "add a todo to ", "add to my list ", "add ", "new to-do ", "new todo ", "put "] where l.hasPrefix(prefix) {
            var item = String(l.dropFirst(prefix.count))
            for tail in [" to my list", " to my to-do list", " to my todo list", " to my to-dos", " to the list", " to my todos", " to do list"] where item.hasSuffix(tail) {
                item = String(item.dropLast(tail.count))
            }
            item = item.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : .addTodo(item)
        }
        let w = Goodbye.words(l)
        let greetings: Set<String> = ["hi", "hello", "hey", "hiya", "howdy", "morning", "afternoon", "evening"]
        if w.count <= 6, let first = w.first, greetings.contains(first) || l.hasPrefix("good morning") || l.hasPrefix("how are you") {
            return .greeting
        }
        return nil
    }
}

/// The back-and-forth conversation as a pure state machine (time is injected through the events).
/// listening -> (final transcript) -> thinking -> (reply) -> listening for a follow-up -> ... -> end.
public struct ConversationMachine: Sendable {
    public enum Phase: Sendable, Equatable { case idle, listening, thinking }
    public enum EndReason: Sendable, Equatable {
        case goodbye
        /// Nothing was said; `afterReply` is true for a follow-up that never came.
        case noSpeech(afterReply: Bool)
        case toggled, interrupted, timedOut
    }
    public enum Event: Sendable, Equatable {
        case toggle(Date)          // shortcut: start, or end if already active
        case holdStart(Date)
        case holdEnd(Date)
        case speechStarted(Date)
        case finalTranscript(String, Date)
        case replyReady(Date)
        case tick(Date)
        case interrupt(Date)       // Esc, a click on Mochi, screen lock, the user went away
    }
    public enum Action: Sendable, Equatable {
        case beginListening(followUp: Bool)
        case finishListening
        case askBrain(String)
        case end(EndReason)
    }

    public static let silenceEnd: TimeInterval = 1.3
    public static let maxTurn: TimeInterval = 20
    public static let followUpWindow: TimeInterval = 8
    public static let firstWindow: TimeInterval = 8
    public static let maxThinking: TimeInterval = 60

    public private(set) var phase: Phase = .idle
    public private(set) var followUp = false
    public private(set) var heard = false
    public private(set) var held = false
    public private(set) var hasReplied = false
    private var since = Date.distantPast

    public init() {}

    public var isActive: Bool { phase != .idle }

    public mutating func handle(_ event: Event) -> [Action] {
        switch event {
        case .toggle(let now):
            if isActive { return finish(.toggled) }
            return begin(now, held: false)
        case .holdStart(let now):
            switch phase {
            case .idle: return begin(now, held: true)
            case .listening:   // holding during a follow-up: the user is about to speak
                held = true; heard = false; since = now
                return [.beginListening(followUp: false)]
            case .thinking: return []
            }
        case .holdEnd:
            guard held else { return [] }
            held = false
            return phase == .listening ? [.finishListening] : []
        case .speechStarted:
            if phase == .listening { heard = true }
            return []
        case .finalTranscript(let text, let now):
            guard phase == .listening else { return [] }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return finish(.noSpeech(afterReply: hasReplied)) }
            if Goodbye.isGoodbye(t) { return finish(.goodbye) }
            phase = .thinking
            since = now
            return [.askBrain(t)]
        case .replyReady(let now):
            guard phase == .thinking else { return [] }
            phase = .listening
            followUp = true; heard = false; held = false; hasReplied = true
            since = now
            return [.beginListening(followUp: true)]
        case .tick(let now):
            let age = now.timeIntervalSince(since)
            switch phase {
            case .idle: return []
            case .thinking: return age >= Self.maxThinking ? finish(.timedOut) : []
            case .listening:
                if held { return [] }
                if !heard { return age >= (followUp ? Self.followUpWindow : Self.firstWindow) ? finish(.noSpeech(afterReply: hasReplied)) : [] }
                return age >= Self.maxTurn ? [.finishListening] : []
            }
        case .interrupt:
            return isActive ? finish(.interrupted) : []
        }
    }

    private mutating func begin(_ now: Date, held: Bool) -> [Action] {
        phase = .listening
        followUp = false; heard = false; hasReplied = false
        self.held = held
        since = now
        return [.beginListening(followUp: false)]
    }

    private mutating func finish(_ reason: EndReason) -> [Action] {
        phase = .idle
        followUp = false; heard = false; held = false; hasReplied = false
        return [.end(reason)]
    }
}
