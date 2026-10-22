import Foundation

// "Mochi's little extras": wake greeting, good night, meal ideas and self-care nudges. All pure
// "when to say what" logic; the app only shows the lines. Nothing here touches the network.

/// Picks line indices without repeating the last few.
public struct LineRotor: Sendable, Equatable {
    public private(set) var recent: [Int] = []
    public let memory: Int
    public init(memory: Int = 3) { self.memory = memory }

    public mutating func next(count: Int, random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> Int {
        guard count > 0 else { return 0 }
        let fresh = (0..<count).filter { !recent.contains($0) }
        let choices = fresh.isEmpty ? Array(0..<count) : fresh
        let pick = choices[min(max(0, random(choices.count)), choices.count - 1)]
        recent.append(pick)
        if recent.count > memory { recent.removeFirst() }
        return pick
    }
}

// MARK: 1. Wake greeting

public enum WakeGreeting {
    /// Coming back after at least this long gets a greeting.
    public static let minAway: TimeInterval = 10 * 60

    public static func shouldGreet(awayFor: TimeInterval) -> Bool { awayFor >= minAway }

    /// 5:00-11:59 morning, 12:00-16:59 afternoon, 17:00-21:59 evening; 22:00-4:59 is a soft "it's late".
    public static func line(now: Date, name: String, calendar: Calendar = .autoupdatingCurrent,
                            locale: Locale = .autoupdatingCurrent) -> String {
        let hour = calendar.component(.hour, from: now)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = n.isEmpty ? "" : ", \(n)"
        let date = dateText(now, calendar: calendar, locale: locale)
        switch hour {
        case 5..<12: return "Good morning\(named)! ☀️ It's \(date)."
        case 12..<17: return "Good afternoon\(named)! 🌤️ It's \(date)."
        case 17..<22: return "Good evening\(named)! 🌙 It's \(date)."
        default: return "Hi again\(named) 🌙 It's late, be gentle with yourself"
        }
    }

    /// Localized weekday, month and day, e.g. "Thursday, October 22".
    public static func dateText(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: date)
    }
}

// MARK: 2. Good night

public enum GoodNight {
    public static let hours = 19...23
    public static let latestHour = 2   // never after 2:00
    public static let lines = [
        "Have an amazing night! 🌙",
        "You did enough today. Have a cozy night ✨",
        "Rest well tonight, see you tomorrow 💤",
        "Sleep tight, you earned it 🌙",
        "The day is done. Be proud of it ⭐",
        "Time to wind down, sweet dreams ☁️",
        "Goodnight! Tomorrow is a fresh start 🌱",
        "Cozy blankets and good dreams for you 🛏️",
        "Thanks for today. Sleep well 💤",
    ]

    /// The evening a moment belongs to (the night runs from `hour` until 2:00 the next morning).
    static func nightKey(_ now: Date, _ calendar: Calendar) -> Date {
        calendar.startOfDay(for: now.addingTimeInterval(-Double(latestHour) * 3600))
    }

    /// Once per night, at `hour` or the first active moment after it, but not after 2:00.
    public static func isDue(now: Date, hour: Int, lastNight: Date?, userActive: Bool, phase: Phase,
                             calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard userActive else { return false }
        if case .breakDue = phase { return false }
        let h = calendar.component(.hour, from: now)
        let start = min(max(hour, hours.lowerBound), hours.upperBound)
        guard h >= start || h < latestHour else { return false }
        return lastNight != nightKey(now, calendar)
    }

    public static func key(_ now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date { nightKey(now, calendar) }
}

// MARK: 3. Meal ideas

public enum MealMode: String, CaseIterable, Sendable {
    case off, any, vegetarian
    public var displayName: String {
        switch self { case .off: "Off"; case .any: "Any"; case .vegetarian: "Vegetarian" }
    }
}

public enum Meal: String, Sendable, Codable { case lunch, dinner }

public struct MealIdea: Sendable, Equatable {
    public let id: String
    public let text: String
    public let emoji: String
    public let vegetarian: Bool
    public let meal: Meal
    /// A short dish name for web searches, e.g. "ramen". Never contains anything about the user.
    public let searchTerm: String

    public init(id: String, text: String, emoji: String, vegetarian: Bool, meal: Meal, searchTerm: String) {
        self.id = id; self.text = text; self.emoji = emoji; self.vegetarian = vegetarian; self.meal = meal
        self.searchTerm = searchTerm
    }

    /// "🍳 Recipes" and "📍 Nearby": Google links that only open when tapped (Mochi makes no requests).
    public var links: [AskLink] {
        let q = MealIdea.queryWords(searchTerm)
        return [AskLink(title: "🍳 Recipes", url: URL(string: "https://www.google.com/search?q=\(q)+recipe")!),
                AskLink(title: "📍 Nearby", url: URL(string: "https://www.google.com/maps/search/\(q)+near+me")!)]
    }

    /// Words joined with "+", each percent-encoded.
    static func queryWords(_ term: String) -> String {
        term.split(whereSeparator: \.isWhitespace)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
            .joined(separator: "+")
    }

    /// "Lunch idea: a warm bowl of ramen? 🍜" (alternating "?" for variety).
    public var line: String {
        let n = Int(id.dropFirst()) ?? 0
        return "\(meal == .lunch ? "Lunch" : "Dinner") idea: \(text)\(n % 2 == 0 ? "?" : "") \(emoji)"
    }
}

/// Ids and dates only: which ideas were shown lately, and the day each meal was last suggested.
public struct MealMemory: Codable, Sendable, Equatable {
    public var recent: [String: Date] = [:]
    public var lunchDay: Date?
    public var dinnerDay: Date?
    public init() {}
}

public enum MealIdeas {
    private static func make(_ meal: Meal, _ prefix: String, _ rows: [(String, String, Bool)], _ terms: [String]) -> [MealIdea] {
        precondition(rows.count == terms.count)
        return rows.enumerated().map { MealIdea(id: String(format: "%@%02d", prefix, $0.offset + 1), text: $0.element.0,
                                                emoji: $0.element.1, vegetarian: $0.element.2, meal: meal,
                                                searchTerm: terms[$0.offset]) }
    }

    public static let lunch: [MealIdea] = make(.lunch, "l", [
        ("a warm bowl of ramen", "🍜", false), ("a banh mi with crunchy pickles", "🥖", false),
        ("pho with lots of fresh herbs", "🍲", false), ("a rice bowl with a soft egg and soy sauce", "🍚", true),
        ("avocado toast with chili flakes", "🥑", true), ("a big Greek salad with feta", "🥗", true),
        ("a chicken Caesar wrap", "🌯", false), ("veggie bibimbap with a fried egg", "🍚", true),
        ("cold sesame noodles", "🥢", true), ("grilled cheese with tomato soup", "🧀", true),
        ("a burrito bowl with black beans", "🌯", true), ("a tuna salad sandwich", "🥪", false),
        ("chana masala with rice", "🍛", true), ("a falafel pita with tahini", "🧆", true),
        ("gimbap rolls", "🍙", false), ("pesto pasta with cherry tomatoes", "🍝", true),
        ("egg fried rice", "🍳", true), ("miso soup with tofu and rice", "🍲", true),
        ("a melty cheese quesadilla", "🧀", true), ("udon in warm broth", "🍜", false),
        ("a caprese sandwich", "🍅", true), ("a teriyaki chicken bowl", "🍗", false),
        ("lentil soup with crusty bread", "🥣", true), ("dumplings with chili oil", "🥟", false),
        ("a hummus plate with veggies and pita", "🫓", true), ("a turkey club sandwich", "🥪", false),
        ("pad thai", "🍤", false), ("veggie fried noodles", "🍜", true),
        ("mac and cheese", "🧀", true), ("a poke bowl", "🐟", false),
        ("tomato basil soup", "🍅", true), ("a fluffy omelette with toast", "🍳", true),
        ("a chicken shawarma wrap", "🌯", false), ("spring rolls with peanut sauce", "🥬", true),
        ("a baked potato with all the toppings", "🥔", true), ("chicken katsu curry", "🍛", false),
        ("a pasta salad with olives and feta", "🥗", true), ("a tofu stir-fry with rice", "🥦", true),
        ("bean and cheese nachos", "🧀", true), ("a few sushi rolls", "🍣", false),
        ("a leftovers remix bowl", "♻️", true), ("a bowl of congee with scallions", "🥣", true),
    ], ["ramen", "banh mi", "pho", "egg rice bowl", "avocado toast", "greek salad", "chicken caesar wrap", "vegetarian bibimbap", "cold sesame noodles", "grilled cheese tomato soup", "burrito bowl", "tuna salad sandwich", "chana masala", "falafel pita", "gimbap", "pesto pasta", "egg fried rice", "miso soup", "cheese quesadilla", "udon", "caprese sandwich", "teriyaki chicken bowl", "lentil soup", "dumplings", "hummus plate", "turkey club sandwich", "pad thai", "vegetable fried noodles", "mac and cheese", "poke bowl", "tomato basil soup", "omelette", "chicken shawarma wrap", "spring rolls", "loaded baked potato", "chicken katsu curry", "pasta salad", "tofu stir fry", "nachos", "sushi rolls", "easy lunch bowl", "congee"])

    public static let dinner: [MealIdea] = make(.dinner, "d", [
        ("tacos with lots of lime", "🌮", false), ("a vegetable curry with rice", "🍛", true),
        ("spaghetti aglio e olio", "🍝", true), ("pho again, it never gets old", "🍲", false),
        ("a sheet-pan chicken and veggies", "🍗", false), ("a creamy mushroom risotto", "🍄", true),
        ("a bulgogi bowl", "🥩", false), ("palak paneer with naan", "🍛", true),
        ("a margherita pizza", "🍕", true), ("grilled salmon with rice", "🐟", false),
        ("stir-fried noodles with whatever veggies you have", "🥢", true), ("cheese enchiladas", "🌯", true),
        ("chicken tikka masala", "🍛", false), ("Thai green curry with tofu", "🥥", true),
        ("a veggie lasagna", "🧀", true), ("ramen with a soft egg", "🍜", false),
        ("shakshuka with crusty bread", "🍳", true), ("burgers and baked fries", "🍔", false),
        ("kimchi jjigae", "🌶️", false), ("grilled cheese night with a salad", "🥗", true),
        ("teriyaki salmon", "🐟", false), ("chili with cornbread", "🌶️", false),
        ("stuffed bell peppers", "🫑", true), ("butter chicken", "🍗", false),
        ("a veggie mapo tofu", "🥘", true), ("gnocchi with brown butter and sage", "🍝", true),
        ("fish tacos", "🌮", false), ("chicken souvlaki with tzatziki", "🥙", false),
        ("dal and rice, simple comfort", "🍲", true), ("chicken and rice soup", "🍲", false),
        ("ratatouille with bread", "🍆", true), ("okonomiyaki", "🥞", false),
        ("bean burritos", "🌯", true), ("pasta primavera", "🍝", true),
        ("steak and roasted potatoes", "🥩", false), ("veggie dumplings with dipping sauce", "🥟", true),
        ("a coconut lentil curry", "🥥", true), ("a tomato and egg stir-fry with rice", "🍅", true),
        ("falafel bowls", "🧆", true), ("loaded baked sweet potatoes", "🍠", true),
        ("bun cha with fresh herbs", "🥢", false), ("chicken fried rice", "🍚", false),
    ], ["tacos", "vegetable curry", "spaghetti aglio e olio", "pho", "sheet pan chicken and vegetables", "mushroom risotto", "bulgogi bowl", "palak paneer", "margherita pizza", "grilled salmon", "vegetable stir fry noodles", "cheese enchiladas", "chicken tikka masala", "thai green curry tofu", "vegetable lasagna", "ramen", "shakshuka", "burgers", "kimchi jjigae", "grilled cheese sandwich", "teriyaki salmon", "chili cornbread", "stuffed bell peppers", "butter chicken", "vegetarian mapo tofu", "gnocchi brown butter sage", "fish tacos", "chicken souvlaki", "dal", "chicken rice soup", "ratatouille", "okonomiyaki", "bean burritos", "pasta primavera", "steak and potatoes", "vegetable dumplings", "coconut lentil curry", "tomato egg stir fry", "falafel bowl", "stuffed sweet potatoes", "bun cha", "chicken fried rice"])

    public static func pool(_ meal: Meal, mode: MealMode) -> [MealIdea] {
        let all = meal == .lunch ? lunch : dinner
        return mode == .vegetarian ? all.filter(\.vegetarian) : all
    }
}

public enum MealPolicy {
    public static let lunchWindow = (from: (h: 11, m: 30), to: (h: 13, m: 30))
    public static let dinnerWindow = (from: (h: 17, m: 30), to: (h: 19, m: 30))
    /// Aims at about 12:00 / 18:00: each day's start is the window start plus 0-60 minutes.
    public static let aimSpread = 60
    public static let noRepeat: TimeInterval = 7 * 86400

    static func at(_ h: Int, _ m: Int, _ day: Date, _ cal: Calendar) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }

    /// Deterministic per-day spread, so the same day always aims at the same minute.
    static func aimOffset(_ day: Date, _ meal: Meal, _ cal: Calendar) -> Int {
        let ordinal = cal.ordinality(of: .day, in: .era, for: day) ?? 0
        return (ordinal &* 37 &+ (meal == .lunch ? 11 : 23)) % (aimSpread + 1)
    }

    /// Which meal (if any) is due: inside its window, past that day's aim time, not yet suggested today,
    /// the user active, and the timer not in focus / break due (it waits for the focus to end).
    public static func due(now: Date, mode: MealMode, memory: MealMemory, userActive: Bool, phase: Phase,
                           calendar: Calendar = .autoupdatingCurrent) -> Meal? {
        guard mode != .off, userActive else { return nil }
        switch phase {
        case .focusing, .breakDue, .snoozed: return nil
        case .idle, .paused, .onBreak: break
        }
        let day = calendar.startOfDay(for: now)
        for (meal, window, last) in [(Meal.lunch, lunchWindow, memory.lunchDay), (.dinner, dinnerWindow, memory.dinnerDay)] {
            let start = at(window.from.h, window.from.m, day, calendar)
                .addingTimeInterval(Double(aimOffset(day, meal, calendar)) * 60)
            let end = at(window.to.h, window.to.m, day, calendar)
            if now >= start, now <= end, last != day { return meal }
        }
        return nil
    }

    /// An idea not shown in the last 7 days (or the longest-ago one if everything was).
    public static func pick(_ meal: Meal, mode: MealMode, memory: MealMemory, now: Date,
                            random: (Int) -> Int = { Int.random(in: 0..<$0) }) -> MealIdea? {
        let pool = MealIdeas.pool(meal, mode: mode)
        guard !pool.isEmpty else { return nil }
        let fresh = pool.filter { memory.recent[$0.id].map { now.timeIntervalSince($0) >= noRepeat } ?? true }
        let choices = fresh.isEmpty
            ? [pool.min { (memory.recent[$0.id] ?? .distantPast) < (memory.recent[$1.id] ?? .distantPast) }!]
            : fresh
        return choices[min(max(0, random(choices.count)), choices.count - 1)]
    }

    /// `markDay: false` is for ideas the user asked for: they rest for 7 days but don't use up today's scheduled one.
    public static func commit(_ idea: MealIdea, to memory: inout MealMemory, now: Date, calendar: Calendar = .autoupdatingCurrent,
                              markDay: Bool = true) {
        let day = calendar.startOfDay(for: now)
        if markDay { if idea.meal == .lunch { memory.lunchDay = day } else { memory.dinnerDay = day } }
        memory.recent[idea.id] = now
        memory.recent = memory.recent.filter { now.timeIntervalSince($0.value) < noRepeat * 2 }
    }
}

// MARK: 4. Self-care

public enum SelfCare {
    public static let options = [0, 30, 60]   // minutes; 0 is off
    public static let quietFromHour = 22
    public static let quietUntilHour = 7
    public static let otherLineGap: TimeInterval = 10 * 60

    public static let lines = [
        "Sip of water time 💧",
        "Don't forget to drink some water 💧",
        "Little stretch? Reach up high and breathe 🌱",
        "Rest your eyes: look far away for 20 seconds 🌤️",
        "Posture check: shoulders down, back tall 🪑",
        "Three slow breaths with me… in… and out ☁️",
        "Roll your shoulders back a few times 🌿",
        "Shake out your wrists and fingers for a moment ✨",
        "Unclench your jaw and soften your face 😌",
        "Stand up and wiggle your toes a bit 🦶",
        "Blink slowly a few times, your eyes will thank you 👀",
        "Neck stretch: tilt your head slowly side to side 🌸",
        "How about a glass of water? 💧",
        "Look out a window for a moment 🪟",
        "Plant both feet on the floor and sit tall 🌱",
        "A deep breath in, a long breath out 🍃",
        "Wrist circles, five each way ✨",
        "Let your shoulders drop away from your ears 🌥️",
    ]

    /// Every `minutes` while the user is active and the timer is idle or paused; quiet 22:00-7:00; and not
    /// when Mochi said something else in the last 10 minutes.
    public static func isDue(now: Date, minutes: Int, lastNudge: Date, lastOtherLine: Date?, userActive: Bool, phase: Phase,
                             calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard minutes > 0, userActive else { return false }
        switch phase {
        case .idle, .paused: break
        case .focusing, .breakDue, .snoozed, .onBreak: return false
        }
        let h = calendar.component(.hour, from: now)
        guard h >= quietUntilHour, h < quietFromHour else { return false }
        guard now.timeIntervalSince(lastNudge) >= Double(minutes) * 60 else { return false }
        if let other = lastOtherLine, now.timeIntervalSince(other) < otherLineGap { return false }
        return true
    }
}

// MARK: On-demand meal ideas (Ask Mochi)

public enum MealRequest {
    private static let triggers = ["lunch idea", "dinner idea", "meal idea", "food idea", "snack idea", "what should i eat",
                                   "what shall i eat", "what to eat", "what can i eat", "what's for dinner", "whats for dinner",
                                   "what's for lunch", "whats for lunch", "what is for dinner", "what is for lunch",
                                   "ideas for lunch", "ideas for dinner", "something to eat"]

    /// True if the text asks for something to eat (not a to-do like "dinner with Sam at 7").
    public static func isRequest(_ text: String) -> Bool {
        let l = text.lowercased().replacingOccurrences(of: "’", with: "'")
        return triggers.contains { l.contains($0) }
    }

    /// "lunch" or "dinner" in the text picks that meal; otherwise lunch before 15:00 and dinner after.
    public static func meal(for text: String, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Meal {
        let l = text.lowercased()
        let lunch = l.range(of: "lunch"), dinner = l.range(of: "dinner")
        switch (lunch, dinner) {
        case let (a?, b?): return a.lowerBound <= b.lowerBound ? .lunch : .dinner
        case (_?, nil): return .lunch
        case (nil, _?): return .dinner
        default: return calendar.component(.hour, from: now) < 15 ? .lunch : .dinner
        }
    }

    /// A short, warm reply, e.g. "How about a warm bowl of ramen? 🍜 Simple and cozy."
    public static func reply(for idea: MealIdea) -> String {
        let closers = ["Simple and cozy.", "Easy and tasty.", "Comfort without the fuss.", "Hope that sounds good!"]
        let n = Int(idea.id.dropFirst()) ?? 0
        return "How about \(idea.text)? \(idea.emoji) \(closers[n % closers.count])"
    }

    /// The Ask card state for an idea: the reply plus its two search links.
    public static func state(for idea: MealIdea) -> AskMochiState {
        AskMochiState(reply: reply(for: idea), links: idea.links)
    }

    /// The mode to answer with: Off still answers (the user asked), everything else as set.
    public static func mode(from setting: MealMode) -> MealMode { setting == .off ? .any : setting }
}
