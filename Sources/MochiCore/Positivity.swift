import Foundation

/// How often Mochi offers a kind word on its own.
public enum Positivity: String, CaseIterable, Sendable {
    case rarely, fewTimesADay, often

    public var displayName: String {
        switch self {
        case .rarely: "Rarely"
        case .fewTimesADay: "A few times a day"
        case .often: "Often"
        }
    }
}

public enum PositivityWin: Sendable, Equatable { case focusFinished, todoTicked, allDone }
public enum PositivityMoment: Sendable, Equatable { case morning, midday, win(PositivityWin), wrapUp, hourly }

public struct PositivityMemory: Sendable, Equatable {
    public var lastAt: Date?
    public var morningDay: Date?
    public var middayDay: Date?
    public var wrapUpDay: Date?
    public init() {}
}

/// Decides WHEN Mochi says something kind (pure; nothing is saved).
/// - Rarely: morning + wrap-up. A few times a day: also midday and after wins. Often: also about hourly.
/// - At least 90 min between lines (wins: 30 min; Often: 60 min between scheduled lines).
/// - Quiet when the user is away, during breakDue, and from 22:00 to 6:00.
/// - A moment is only used up when it is spoken, so a busy moment just waits for the next one.
public struct PositivityPolicy: Sendable {
    public var memory: PositivityMemory
    public var calendar: Calendar

    public static let minGap: TimeInterval = 90 * 60
    public static let winGap: TimeInterval = 30 * 60
    public static let oftenGap: TimeInterval = 60 * 60
    public static let morningHour = 6
    public static let quietFromHour = 22
    public static let middayStart = (hour: 12, minute: 30)
    public static let middayEndHour = 15

    public init(memory: PositivityMemory = .init(), calendar: Calendar = .autoupdatingCurrent) {
        self.memory = memory
        self.calendar = calendar
    }

    /// A moment the policy would use, with the memory to adopt once it was actually shown.
    public struct Decision: Sendable, Equatable {
        public let moment: PositivityMoment
        fileprivate let memory: PositivityMemory
    }

    /// Looks without consuming anything. Call `commit` only if the line really was shown.
    public func peek(now: Date, level: Positivity, win: PositivityWin?, phase: Phase, userActive: Bool,
                     wrapUpHour: Int, wrapUpMinute: Int) -> Decision? {
        var copy = self
        guard let m = copy.evaluate(now: now, level: level, win: win, phase: phase, userActive: userActive,
                                    wrapUpHour: wrapUpHour, wrapUpMinute: wrapUpMinute) else { return nil }
        return Decision(moment: m, memory: copy.memory)
    }

    public mutating func commit(_ decision: Decision) { memory = decision.memory }

    /// Peek and commit in one step.
    public mutating func decide(now: Date, level: Positivity, win: PositivityWin?, phase: Phase, userActive: Bool,
                                wrapUpHour: Int, wrapUpMinute: Int) -> PositivityMoment? {
        evaluate(now: now, level: level, win: win, phase: phase, userActive: userActive,
                 wrapUpHour: wrapUpHour, wrapUpMinute: wrapUpMinute)
    }

    private mutating func evaluate(now: Date, level: Positivity, win: PositivityWin?, phase: Phase, userActive: Bool,
                                   wrapUpHour: Int, wrapUpMinute: Int) -> PositivityMoment? {
        guard userActive else { return nil }
        if case .breakDue = phase { return nil }
        let hour = calendar.component(.hour, from: now)
        guard hour >= Self.morningHour, hour < Self.quietFromHour else { return nil }
        let today = calendar.startOfDay(for: now)
        let since = memory.lastAt.map { now.timeIntervalSince($0) } ?? .infinity

        func say(_ m: PositivityMoment) -> PositivityMoment { memory.lastAt = now; return m }

        if let win, level != .rarely, since >= Self.winGap { return say(.win(win)) }
        let gap = level == .often ? Self.oftenGap : Self.minGap
        guard since >= gap else { return nil }

        if memory.wrapUpDay != today,
           let at = calendar.date(bySettingHour: wrapUpHour, minute: wrapUpMinute, second: 0, of: today), now >= at {
            memory.wrapUpDay = today
            return say(.wrapUp)
        }
        if memory.morningDay != today {
            if hour < 12 { memory.morningDay = today; return say(.morning) }
            memory.morningDay = today   // first seen after noon: no longer morning
        }
        if level != .rarely, memory.middayDay != today,
           let from = calendar.date(bySettingHour: Self.middayStart.hour, minute: Self.middayStart.minute, second: 0, of: today),
           now >= from, hour < Self.middayEndHour {
            memory.middayDay = today
            return say(.midday)
        }
        if level == .often { return say(.hourly) }
        return nil
    }
}

/// Cleans on-device model output into text that is safe to show: complete sentences only, no list
/// markers, no markdown, no stiff phrases. A cut-off answer is trimmed back to its last full sentence
/// (never mid-word, never "..."), or dropped.
public enum LineSanitizer {
    /// Phrases that break Mochi's voice. A reply containing one is dropped.
    static let banned = ["as an ai", "as a language model", "language model", "i'm an ai", "i am an ai",
                         "i'm glad you were able", "i am glad you were able", "programmed", "my programming"]

    public static func hasBannedPhrase(_ s: String) -> Bool {
        let l = s.lowercased()
        return banned.contains { l.contains($0) }
    }

    static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value >= 0x203C)
    }

    public static func containsEmoji(_ s: String) -> Bool { s.unicodeScalars.contains(where: isEmoji) }

    /// Ends in . ! ? or an emoji.
    static func endsComplete(_ s: String) -> Bool {
        guard let last = s.unicodeScalars.reversed().first(where: { !$0.properties.isWhitespace && $0.value != 0xFE0F })
        else { return false }
        return ".!?".unicodeScalars.contains(last) || isEmoji(last)
    }

    /// Indices just after each sentence end (a . ! ? followed by space/end, or an emoji).
    static func sentenceEnds(_ s: String) -> [String.Index] {
        var ends: [String.Index] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let next = s.index(after: i)
            let isEnd = ".!?".contains(c) ? (next == s.endIndex || s[next].isWhitespace || s[next].unicodeScalars.contains(where: isEmoji))
                : (c.unicodeScalars.contains(where: isEmoji) && !c.isNumber && (next == s.endIndex || s[next].isWhitespace))
            if isEnd { ends.append(next) }
            i = next
        }
        return ends
    }

    /// At most `maxLength` characters and ending on a full sentence; nil if impossible.
    static func completeSentences(_ s: String, maxLength: Int, maxSentences: Int = .max) -> String? {
        var text = s
        let ends = sentenceEnds(text)
        if ends.count > maxSentences { text = String(text[..<ends[maxSentences - 1]]) }
        if text.count > maxLength {
            let cut = String(text.prefix(maxLength))
            guard let end = sentenceEnds(cut).last else { return nil }
            text = String(cut[..<end])
        } else if !endsComplete(text) {
            if let end = sentenceEnds(text).last {
                text = String(text[..<end])
            } else if text.count <= 60 {
                text += "."
            } else {
                return nil
            }
        }
        let out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    /// One bubble line (first non-empty line, quotes stripped, one space between words).
    public static func oneLine(_ raw: String, maxLength: Int = 90) -> String? {
        let quotes = CharacterSet(charactersIn: "\"“”‘’`«»")
        var s = raw.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        s = s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(quotes))
        s = s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !s.isEmpty, !hasBannedPhrase(s) else { return nil }
        return completeSentences(s, maxLength: maxLength)
    }

    /// A kind line for the bubble: one line, on voice, always with an emoji for the time of day.
    private static let reminderPhrases = ["don't forget", "do not forget", "remember to", "make sure", "you should",
                                          "you need to", "you must", "you have to", "reminder"]
    private static let selfCare = ["water", "drink", "hydrat", "stretch", "breathe", "breath", "rest", "eyes", "posture",
                                   "snack", "walk", "blink", "shoulder", "sip", "eat", "smile"]

    /// "Don't forget to call mom" style nudges are not wanted in kind words; self-care ones are fine.
    public static func isTaskReminder(_ line: String) -> Bool {
        let l = line.lowercased()
        guard reminderPhrases.contains(where: { l.contains($0) }) else { return false }
        return !selfCare.contains { l.contains($0) }
    }

    public static func kindLine(_ raw: String, part: DayPart, maxLength: Int = 90) -> String? {
        guard let line = oneLine(raw, maxLength: maxLength), !isTaskReminder(line) else { return nil }
        return containsEmoji(line) ? line : line + " " + emoji(for: part)
    }

    public static func emoji(for part: DayPart) -> String {
        switch part {
        case .morning: "☀️"
        case .afternoon: "🌤️"
        case .evening: "🌙"
        case .night: "🌱"
        }
    }

    /// Strips markdown and list markers and joins the lines into prose.
    static func prose(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        let marker = try! NSRegularExpression(pattern: #"^\s*(?:#{1,6}\s+|[*•\-–]\s+|\d{1,2}[.)]\s+)"#)
        var parts: [String] = []
        let lines = cleaned.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, line) in lines.enumerated() {
            var t = marker.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length), withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            // A list item ends its own sentence. A plain last line that stops mid-sentence stays as is
            // (it may be cut off) so it can be trimmed away.
            let isItem = t != line
            if !(endsComplete(t) || t.hasSuffix(":") || t.hasSuffix(",")), isItem || i < lines.count - 1 { t += "." }
            parts.append(t)
        }
        return parts.joined(separator: " ").split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// A multi-sentence reply for the Ask card: prose, at most 3 sentences, at most `maxLength` characters,
    /// ending on a full sentence.
    public static func reply(_ raw: String, maxLength: Int = 400, maxSentences: Int = 3) -> String? {
        let text = prose(raw)
        guard !text.isEmpty else { return nil }
        return completeSentences(text, maxLength: maxLength, maxSentences: maxSentences)
    }
}

/// Final checks on an "Ask Mochi" answer before it is shown.
public enum AskReply {
    public static let couldNotDo = "I couldn't do that one, could you try rephrasing? 💜"
    public static let hiccup = "My brain hiccuped. Try again? 🌀"

    private static let claim = try! NSRegularExpression(
        pattern: #"\b(?:i(?:'ve| have)?|mochi(?:'s)?|all set[,!.]?\s*i)\s+(?:just\s+|already\s+|now\s+)?(?:added|moved|started|begun|ticked|marked|checked off|ticked off|scheduled|created|set|put|deleted|removed|cleared|erased|finished|completed)\b|\b(?:reminder|to-?do|task)\b[^.!?]{0,40}\b(?:is|has been|was)\s+(?:now\s+)?(?:added|set|moved|scheduled|done|deleted|removed)\b"#,
        options: [.caseInsensitive])

    /// True if the text says Mochi already did something to the list or timer.
    public static func claimsAction(_ reply: String) -> Bool {
        claim.firstMatch(in: reply, range: NSRange(location: 0, length: (reply as NSString).length)) != nil
    }

    private static let greeting = try! NSRegularExpression(
        pattern: #"^\s*(?:hello|hi|hey|hiya|howdy|greetings|good (?:morning|afternoon|evening))\b[ ,]*(?:there\b[ ,]*)?"#,
        options: [.caseInsensitive])

    public static func startsWithGreeting(_ s: String) -> Bool {
        greeting.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Drops a leading "Hello Anh!" unless the user greeted first.
    static func stripGreeting(_ reply: String, name: String) -> String {
        guard let m = greeting.firstMatch(in: reply, range: NSRange(location: 0, length: (reply as NSString).length)) else { return reply }
        var rest = (reply as NSString).substring(from: m.range.length)
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty, rest.lowercased().hasPrefix(n.lowercased()) { rest = String(rest.dropFirst(n.count)) }
        rest = String(rest.drop(while: { " ,!.".contains($0) || $0.isWhitespace }))
        guard let first = rest.first else { return reply }
        return first.uppercased() + rest.dropFirst()
    }

    private static let offers = ["how else can i", "anything else", "let me know", "feel free", "need any more", "if you need",
                                 "happy to help", "here to help", "i'm here if", "more assistance", "would you like me to"]

    /// Drops trailing "can I help with anything else?" filler (never the only sentence).
    static func dropOffers(_ text: String) -> String {
        let ends = LineSanitizer.sentenceEnds(text)
        guard ends.count > 1 else { return text }
        var sentences: [String] = []
        var start = text.startIndex
        for e in ends { sentences.append(String(text[start..<e]).trimmingCharacters(in: .whitespaces)); start = e }
        let rest = String(text[start...]).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        let kept = sentences.filter { s in !offers.contains { s.lowercased().contains($0) } }
        return kept.isEmpty ? text : kept.joined(separator: " ")
    }

    /// `actionsTaken` is what the tools really did; a reply may never claim more than that.
    public static func finalize(_ raw: String, userText: String, name: String, actionsTaken: [String]) -> String {
        guard var text = LineSanitizer.reply(raw), !LineSanitizer.hasBannedPhrase(text),
              !text.contains("[") else { return hiccup }   // an unfilled placeholder from the examples
        text = dropOffers(text)
        if !startsWithGreeting(userText) { text = stripGreeting(text, name: name) }
        if actionsTaken.isEmpty, claimsAction(text) { return couldNotDo }
        return text
    }
}

/// Finds the unfinished to-do a spoken phrase most likely means.
public enum TodoMatcher {
    public enum Result: Equatable {
        case found(TodoItem)
        case ambiguous([String])
        case none
    }

    private static let stopwords: Set<String> = ["the", "my", "a", "an", "to", "task", "todo", "to-do", "item", "for", "of",
                                                 "tomorrow", "today", "done", "please", "that", "this", "it"]

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    public static func find(_ query: String, in items: [TodoItem]) -> Result {
        let open = items.filter { !$0.done }
        let q = tokens(query).filter { !stopwords.contains($0) }
        guard !q.isEmpty else { return .none }
        let normalizedQuery = tokens(query).joined(separator: " ")
        var best: [TodoItem] = []
        var bestScore = 0
        for item in open {
            let t = tokens(item.title)
            let score: Int
            if t.joined(separator: " ") == normalizedQuery {
                score = 3
            } else if q.allSatisfy({ qt in t.contains { $0 == qt || ($0.count >= 3 && qt.hasPrefix($0)) || (qt.count >= 3 && $0.hasPrefix(qt)) } }) {
                score = q.allSatisfy({ t.contains($0) }) ? 2 : 1
            } else {
                continue
            }
            if score > bestScore { best = [item]; bestScore = score } else if score == bestScore { best.append(item) }
        }
        switch best.count {
        case 0: return .none
        case 1: return .found(best[0])
        default: return .ambiguous(best.map(\.title))
        }
    }

    /// Words of 3+ letters (letters only) that carry meaning.
    static func significantWords(_ s: String) -> [String] {
        tokens(s).filter { $0.count >= 3 && $0.allSatisfy(\.isLetter) && !stopwords.contains($0) && !fillerWords.contains($0) }
    }

    private static let fillerWords: Set<String> = ["remind", "reminder", "add", "and", "then", "with", "about", "need", "please",
                                                   "can", "could", "you", "put", "list", "set", "make", "move", "mark", "tick"]

    private static func sameWord(_ a: String, _ b: String) -> Bool {
        a == b || (a.count >= 4 && b.hasPrefix(a)) || (b.count >= 4 && a.hasPrefix(b))
    }

    /// Does the user's own message mention a significant word of this to-do's title? (Guards against
    /// instructions hidden inside titles making the model tick or move things the user never named.)
    public static func userMentions(_ title: String, in userText: String) -> Bool {
        let user = tokens(userText)
        return significantWords(title).contains { w in user.contains { sameWord(w, $0) } }
    }

    /// Is text the model wants to add really taken from what the user typed? At least 75% of its
    /// significant words must appear in the user's message (or, with none, the text must be a substring).
    public static func textComesFrom(_ text: String, userText: String) -> Bool {
        let words = significantWords(text)
        let user = tokens(userText)
        if words.isEmpty {
            let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && userText.lowercased().contains(t)
        }
        let hits = words.filter { w in user.contains { sameWord(w, $0) } }.count
        return Double(hits) >= Double(words.count) * 0.75
    }
}
