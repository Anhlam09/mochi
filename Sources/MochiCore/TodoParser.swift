import Foundation

/// Turns what the user typed ("call mom 3pm", "tomorrow call dentist at noon") into a title, a day and
/// an optional time. Pure and offline: it uses Foundation's on-device `NSDataDetector` only.
///
/// Heuristics:
/// - Input is capped at 500 characters before parsing.
/// - **Day**: `NSDataDetector(.date)` finds date phrases. A phrase counts as a day when something is left
///   of it after removing time tokens and filler words (at/on/by...): "tomorrow", "friday", "oct 24".
///   The day comes from the first such phrase. With no day, the to-do belongs to today, even when
///   its time has already passed (we never guess "tomorrow").
/// - **Time**: found by our own scan, not the detector, so it never depends on the clock. Recognised:
///   `3pm`, `3:15`, `15:30`, `at 10`, `by 5`, `@6`, `noon`, `midnight`, `10 o'clock`. The first time in
///   the text wins ("take pills at 8 am and 8 pm" gives 8:00). Date-only phrases leave `time == nil`.
/// - **Daytime heuristic** for hours without am/pm: 1-7 mean PM (13-19), 8-11 stay AM, 12 is noon, and
///   24-hour values (13-23, or "0:30") are taken as written. "gym at 6" is 18:00, "meeting at 10" is 10:00.
/// - Every accepted phrase and time token is removed from the title, plus dangling connectors
///   (at/on/by/and...) next to them. If nothing is left, the whole text is kept as the title.
/// - Single-word detector matches that are not unmistakable ("sat", "sun", "may", "mon") are ignored,
///   so "buy sun cream" stays a plain to-do.
public struct TodoParser: Sendable {
    public static let maxTitleLength = 120
    public static let maxInputLength = 500

    /// `defaultDay`: the day to use when the text names none (a time in the text then applies on that
    /// day); an explicit day in the text wins.
    public static func parse(_ text: String, now: Date, calendar: Calendar = .autoupdatingCurrent, defaultDay: Date? = nil)
        -> (title: String, day: Date, time: Date?)? {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxInputLength))
        guard !trimmed.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        let plain = (title: cap(trimmed), day: defaultDay.map { calendar.startOfDay(for: $0) } ?? today, time: Date?.none)
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)

        var removed: [NSRange] = []
        var day: Date?
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            detector.enumerateMatches(in: trimmed, options: [], range: full) { match, _, _ in
                guard let match, let date = match.date else { return }
                let info = Phrase(ns.substring(with: match.range))
                guard info.acceptable, info.hasDay else { return }
                removed.append(match.range)
                if day == nil { day = calendar.startOfDay(for: date) }
            }
        }
        let tokens = timeTokens(in: trimmed)
        removed += tokens.map(\.range)

        let title = remainingTitle(trimmed, removing: removed)
        guard !removed.isEmpty, !title.isEmpty else { return plain }

        let theDay = day ?? defaultDay.map { calendar.startOfDay(for: $0) } ?? today
        var time: Date?
        if let t = tokens.first {
            time = calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: theDay)
        }
        return (cap(title), theDay, time)
    }

    // MARK: Time tokens

    struct TimeToken { let range: NSRange; let hour: Int; let minute: Int }

    /// 1-7 -> PM, 8-11 AM, 12 noon; 0 and 13-23 as written.
    static func hour(_ h: Int, pm: Bool?) -> Int {
        if let pm { return pm ? (h % 12) + 12 : h % 12 }
        return (1...7).contains(h) ? h + 12 : h
    }

    private static func makePatterns() -> [(NSRegularExpression, (NSTextCheckingResult, NSString) -> (Int, Int)?)] {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
        func int(_ m: NSTextCheckingResult, _ i: Int, _ s: NSString) -> Int? {
            m.range(at: i).location == NSNotFound ? nil : Int(s.substring(with: m.range(at: i)))
        }
        func ampm(_ m: NSTextCheckingResult, _ i: Int, _ s: NSString) -> Bool? {
            m.range(at: i).location == NSNotFound ? nil : s.substring(with: m.range(at: i)).lowercased() == "p"
        }
        let bare = #"(?!\s*(?:min|minutes?|hours?|hrs?|days?|weeks?|months?|%|st\b|nd\b|rd\b|th\b|[ap]\.?m\b))"#
        return [
            (rx(#"\b(\d{1,2}):(\d{2})(?:\s*([ap])\.?m\b\.?)?(?![\d:])"#), { m, s in
                guard let h = int(m, 1, s), let mi = int(m, 2, s), h <= 23, mi <= 59 else { return nil }
                if ampm(m, 3, s) != nil, !(1...12).contains(h) { return nil }
                return (hour(h, pm: ampm(m, 3, s)), mi)
            }),
            (rx(#"\b(\d{1,2})\s?([ap])\.?m\b\.?"#), { m, s in
                guard let h = int(m, 1, s), (1...12).contains(h) else { return nil }
                return (hour(h, pm: ampm(m, 2, s)), 0)
            }),
            (rx(#"\bnoon\b"#), { _, _ in (12, 0) }),
            (rx(#"\bmidnight\b"#), { _, _ in (0, 0) }),
            (rx(#"\b(\d{1,2})\s?o'?clock\b"#), { m, s in
                guard let h = int(m, 1, s), (1...12).contains(h) else { return nil }
                return (hour(h, pm: nil), 0)
            }),
            (rx(#"(?:\b(?:at|by)\s+|@\s*)(\d{1,2})\b(?![:\d])"# + bare), { m, s in
                guard let h = int(m, 1, s), (1...12).contains(h) else { return nil }
                return (hour(h, pm: nil), 0)
            }),
        ]
    }

    /// All time tokens, in text order (overlapping candidates: earlier pattern wins).
    static func timeTokens(in text: String) -> [TimeToken] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var found: [TimeToken] = []
        for (regex, resolve) in makePatterns() {
            for m in regex.matches(in: text, range: full) {
                guard !found.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }),
                      let (h, mi) = resolve(m, ns) else { continue }
                found.append(TimeToken(range: m.range, hour: h, minute: mi))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    // MARK: Phrase analysis

    struct Phrase {
        let hasDay: Bool
        let acceptable: Bool

        init(_ phrase: String) {
            let lower = phrase.lowercased()
            var rest = lower as NSString
            for t in TodoParser.timeTokens(in: lower).reversed() {
                rest = rest.replacingCharacters(in: t.range, with: " ") as NSString
            }
            let words = (rest as String).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "/" })
                .filter { !Self.fillers.contains(String($0)) }
            hasDay = !words.isEmpty
            let all = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            acceptable = hasDay && (all.count > 1 || lower.contains(where: \.isNumber) || Self.safeWords.contains(lower))
        }

        static let fillers: Set<String> = ["at", "on", "by", "around", "due", "from", "before", "until", "@"]
        static let safeWords: Set<String> = ["today", "tonight", "tomorrow", "monday", "tuesday", "wednesday",
                                             "thursday", "friday", "saturday", "sunday"]
    }

    // MARK: Title cleanup

    private static let danglers: Set<String> = ["at", "on", "by", "around", "due", "before", "until", "@"]
    private static let joiners: Set<String> = ["and", "or"]
    private static let junk = CharacterSet(charactersIn: ",;:-–—").union(.whitespacesAndNewlines)

    /// Drops every token touching a removed range, then connectors left dangling next to them.
    private static func remainingTitle(_ text: String, removing ranges: [NSRange]) -> String {
        let ns = text as NSString
        struct Tok { var text: String; var gone: Bool }
        var toks: [Tok] = []
        var i = 0
        while i < ns.length {
            while i < ns.length, isSpace(ns.character(at: i)) { i += 1 }
            guard i < ns.length else { break }
            let start = i
            while i < ns.length, !isSpace(ns.character(at: i)) { i += 1 }
            let r = NSRange(location: start, length: i - start)
            toks.append(Tok(text: ns.substring(with: r), gone: ranges.contains { NSIntersectionRange($0, r).length > 0 }))
        }
        func core(_ t: Tok) -> String { t.text.lowercased().trimmingCharacters(in: junk) }
        var changed = true
        while changed {
            changed = false
            for k in toks.indices where !toks[k].gone {
                let c = core(toks[k])
                let prevGone = k == 0 || toks[k - 1].gone
                let nextGone = k == toks.count - 1 || toks[k + 1].gone
                let isPunct = c.isEmpty
                if isPunct && (prevGone || nextGone)
                    || danglers.contains(c) && nextGone && (k + 1 < toks.count || k > 0)
                    || joiners.contains(c) && prevGone && nextGone && toks.contains(where: \.gone) {
                    toks[k].gone = true; changed = true
                }
            }
        }
        return toks.filter { !$0.gone }.map(\.text).joined(separator: " ").trimmingCharacters(in: junk)
    }

    private static func isSpace(_ c: unichar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(c) ?? " ")
    }

    static func cap(_ s: String) -> String {
        s.count <= maxTitleLength ? s : String(s.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
    }
}
