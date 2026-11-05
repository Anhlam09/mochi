import Foundation

/// Clear "add this to my list" requests, handled in code before the on-device model is asked, so
/// they always work, instantly, with the user's own words (the small model sometimes only *talks*
/// about adding, or rewrites the text).
public enum AddRequest: Equatable, Sendable {
    /// Add this text (the user's own words, original casing).
    case add(String)
    /// "Can you add it" with nothing to add: ask what.
    case needsWhat

    private static let leads = ["hey mochi", "hi mochi", "hello mochi", "ok mochi", "okay mochi", "mochi",
                                "hey", "hi", "hello", "ok", "okay", "please", "pls",
                                "can you", "could you", "would you", "will you", "can u", "could u",
                                "i need you to", "i want you to", "i'd like you to", "help me"]
    private static let verbs = ["add a to-do to", "add a todo to", "add a to do to", "add a reminder to",
                                "add a to-do for", "add a todo for", "add a to-do", "add a todo", "add a reminder",
                                "remind me to", "remind me", "add to my list", "put down", "jot down", "add", "put",
                                "new to-do", "new todo", "make a to-do to", "make a todo to", "note down"]
    private static let tails = ["to my to-do list", "to my todo list", "to my to do list", "to my to-dos", "to my todos",
                                "to my list", "on my to-do list", "on my todo list", "on my list", "to the list",
                                "onto my list", "to-do list", "todo list", "to do list", "for me", "please", "pls", "thanks",
                                "thank you"]
    private static let vague: Set<String> = ["it", "that", "this", "something", "them", "one", "those", "these", "stuff",
                                             "a to-do", "a todo", "a reminder", "to my list", "a task"]

    public static func parse(_ text: String) -> AddRequest? {
        var s = text.replacingOccurrences(of: "’", with: "'")
        s = trim(s)
        // Greetings / politeness up front, possibly several ("hey mochi, can you please add …").
        var changed = true
        while changed {
            changed = false
            for lead in leads where hasWordPrefix(s, lead) {
                s = trim(String(s.dropFirst(lead.count)))
                changed = true
            }
        }
        guard let verb = verbs.first(where: { hasWordPrefix(s, $0) }) else { return nil }
        var item = trim(String(s.dropFirst(verb.count)))
        var trimmed = true
        while trimmed {
            trimmed = false
            for tail in tails where hasWordSuffix(item, tail) {
                item = trim(String(item.dropLast(tail.count)))
                trimmed = true
            }
        }
        if item.isEmpty || vague.contains(item.lowercased()) { return .needsWhat }
        return .add(item)
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?:;")))
    }

    /// Case-insensitive prefix that ends at a word boundary ("add" matches "add milk", not "address").
    private static func hasWordPrefix(_ s: String, _ p: String) -> Bool {
        guard s.count >= p.count, s.prefix(p.count).lowercased() == p else { return false }
        guard s.count > p.count else { return true }
        let next = s[s.index(s.startIndex, offsetBy: p.count)]
        return !(next.isLetter || next.isNumber)
    }

    private static func hasWordSuffix(_ s: String, _ p: String) -> Bool {
        guard s.count > p.count, s.suffix(p.count).lowercased() == p else { return false }
        let prev = s[s.index(s.endIndex, offsetBy: -p.count - 1)]
        return !(prev.isLetter || prev.isNumber)
    }
}
