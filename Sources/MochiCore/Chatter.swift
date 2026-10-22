import Foundation

/// Rough part of the day, used to pick fitting lines.
public enum DayPart: Sendable, Equatable {
    case morning, afternoon, evening, night

    public init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }
}

/// Why Mochi is speaking.
public enum ChatMoment: Sendable, Equatable, CaseIterable {
    /// First hello of the day.
    case greeting
    /// Unprompted "how are you" style line, fitted to the time of day.
    case checkIn
    /// Unprompted affirmation.
    case cheer
    /// A full break just finished.
    case breakDone
    /// Back after being idle, locked or asleep.
    case welcomeBack
    /// Unprompted cute little fact or musing.
    case funFact
    /// The mouse wandered over Mochi.
    case hello
    /// The user tapped Mochi while there was nothing else to do.
    case tapped
    /// A focus session just started from a tap.
    case focusStart
}

/// How often Mochi chats unprompted.
public enum ChatLevel: String, CaseIterable, Sendable {
    case off, sometimes, often

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .sometimes: "Sometimes"
        case .often: "Often"
        }
    }

    /// Average gap between unprompted lines; nil when Mochi stays quiet.
    public var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .sometimes: 8 * 60
        case .often: 2 * 60
        }
    }
}

/// Pure timing rules for Mochi's chatter.
public enum ChatSchedule {
    /// A "day" starts at 5am, so staying up past midnight doesn't earn a second good morning.
    public static let dayStartHour = 5

    /// Next unprompted line: `interval` stretched by ±25% using `jitter` in 0...1.
    public static func next(after date: Date, interval: TimeInterval, jitter: Double) -> Date {
        date.addingTimeInterval(interval * (0.75 + 0.5 * min(1, max(0, jitter))))
    }

    /// True when `now` falls on a later Mochi day than `lastGreeting` (or there was none).
    public static func needsGreeting(lastGreeting: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastGreeting else { return true }
        let shift = TimeInterval(-dayStartHour * 3600)
        return !calendar.isDate(lastGreeting.addingTimeInterval(shift), inSameDayAs: now.addingTimeInterval(shift))
    }
}

/// Picks sweet, kind lines for Mochi to say, avoiding recent repeats.
public struct Chatter: Sendable {
    /// What Mochi calls the user; lines read naturally when empty.
    public var name: String
    private var recent: [String] = []
    static let memory = 24

    public init(name: String = "") { self.name = name }

    /// A line for `moment`. `pick(n)` returns an index in `0..<n` (injectable for checks).
    public mutating func line(for moment: ChatMoment, at date: Date, calendar: Calendar = .current,
                              pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let month = calendar.component(.month, from: date)
        let pool = Self.lines(for: moment, part: DayPart(hour: hour), weekday: weekday, month: month)
        let fresh = pool.filter { !recent.contains($0) }
        let choices = fresh.isEmpty ? pool : fresh
        let template = choices[min(max(0, pick(choices.count)), choices.count - 1)]
        recent.append(template)
        if recent.count > Self.memory { recent.removeFirst() }
        return Self.fill(template, name: name)
    }

    /// Mochi announcing its new colours, e.g. ("Matcha", "🍵").
    public mutating func flavorLine(name flavor: String, emoji: String,
                                    pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let lines = [
            "Ta-da! ✨ I'm \(flavor) Mochi now! \(emoji)",
            "Spin spin! Do you like my \(flavor) colors? \(emoji)",
            "New look! \(flavor) Mochi reporting for duty \(emoji)",
            "Whee! I turned into \(flavor) Mochi \(emoji)",
        ]
        return lines[min(max(0, pick(lines.count)), lines.count - 1)]
    }

    /// Swaps in the name: ", {name}" and " {name}" vanish cleanly when the name is empty.
    public static func fill(_ template: String, name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return template
            .replacingOccurrences(of: ", {name}", with: n.isEmpty ? "" : ", \(n)")
            .replacingOccurrences(of: " {name}", with: n.isEmpty ? "" : " \(n)")
    }

    /// Every template for a moment (weekday: 1 = Sunday … 7 = Saturday; month: 1…12).
    public static func lines(for moment: ChatMoment, part: DayPart, weekday: Int, month: Int = 0) -> [String] {
        let weekend = weekday == 1 || weekday == 7
        switch moment {
        case .greeting:
            var lines = Lines.greetings(part)
            if part == .morning, weekday == 2 { lines += Lines.mondayGreetings }
            if weekday == 6 { lines += Lines.fridayGreetings }
            if weekend, part != .night { lines += Lines.weekendGreetings }
            return lines
        case .checkIn:
            var lines = Lines.checkIns(part)
            if weekend, part != .night { lines += Lines.weekendCheckIns }
            if part != .night { lines += Lines.seasonal(month: month) }
            return lines
        case .cheer: return Lines.cheers
        case .funFact: return Lines.funFacts
        case .breakDone: return Lines.breakDone
        case .welcomeBack: return part == .night ? Lines.welcomeBack + Lines.lateWelcome : Lines.welcomeBack
        case .hello: return Lines.hello
        case .tapped: return Lines.tapped
        case .focusStart: return Lines.focusStart
        }
    }
}

private enum Lines {
    static func greetings(_ part: DayPart) -> [String] {
        switch part {
        case .morning: [
            "Good morning, {name}! ☀️ How are you feeling today?",
            "Morning, {name}! I'm so happy to see you 🌱",
            "Rise and shine! Today is a fresh little start ☀️",
            "Good morning! Did you sleep okay? 💤",
            "Morning, sunshine! Ready for a gentle day? 🌼",
            "Good morning, {name}! I saved you a smile 😊",
            "Yawn… good morning! Let's wake up together 🌤️",
            "Hello, new day! Hello, {name}! 🌱",
        ]
        case .afternoon: [
            "Good afternoon, {name}! How's your day going? 🌤️",
            "Hello! Hope today is being kind to you 🌷",
            "Good afternoon! Have you eaten something yummy? 🍙",
            "Hi, {name}! Half the day done already ✨",
            "Afternoon hello! I'm so glad you're here 💕",
            "Hey there! How's your heart today? 🌷",
        ]
        case .evening: [
            "Good evening, {name}! How was your day? 🌙",
            "Evening! You made it through the day 💕",
            "Hi, {name}! Time to slow down a little soon 🌆",
            "Good evening! What was the best part of today? ✨",
            "Evening hugs for you, {name} 🤗",
            "The sky is getting cozy. Hi, {name}! 🌇",
        ]
        case .night: [
            "Hi, {name}! It's late, so be gentle with yourself 🌙",
            "Still up? I'll keep you company 🌙",
            "Late-night hello! Don't forget to rest soon 💤",
            "Hello, night owl! 🦉 Don't stay up too long",
            "The stars are out. Hi, {name}! ✨",
        ]
        }
    }

    static let mondayGreetings = [
        "Happy Monday, {name}! New week, fresh start 🌱",
        "Monday again! We'll take it one step at a time 💕",
    ]

    static let fridayGreetings = [
        "It's Friday, {name}! You made it through the week 🎉",
        "Happy Friday! The weekend is almost here 🥳",
    ]

    static let weekendGreetings = [
        "Happy weekend, {name}! Go easy on yourself today 🌷",
        "It's the weekend! Room for a little fun? 🎈",
    ]

    static func checkIns(_ part: DayPart) -> [String] {
        switch part {
        case .morning: [
            "How are you doing so far, {name}? 🌱",
            "Did you have breakfast? Tummy fuel matters 🍓",
            "Have you had some water yet? 💧",
            "You're off to a lovely start ☀️",
            "What's one nice thing you'd like today? 🌼",
            "Coffee, tea, or cocoa this morning? ☕",
            "Open a window for some fresh air? 🌬️",
            "Let's make today a soft and kind one 🌷",
        ]
        case .afternoon: [
            "How's your day going, {name}? 🌤️",
            "Hope your afternoon is treating you gently 🌷",
            "Did you have lunch? You deserve a yummy one 🍙",
            "Afternoon slump? That's okay. You're doing great 💕",
            "Water check! Have a little sip 💧",
            "How about a little snack? 🍪",
            "Sit up tall for me? Your back says thanks 🌱",
            "Has anything made you smile today? 😊",
            "You're more than halfway through. Nice! ✨",
        ]
        case .evening: [
            "How was your day, {name}? I hope it was kind to you 🌙",
            "You did a lot today. I'm proud of you 💕",
            "Don't forget dinner! 🍲",
            "Whatever happened today, you did your best 🌷",
            "What's one thing that went well today? ✨",
            "Time to start winding down, maybe? 🛋️",
            "Did you talk to someone you love today? 💌",
            "Evening tea and a cozy blanket sound nice 🍵",
        ]
        case .night: [
            "It's getting late. Rest is productive too 🌙",
            "Your cozy bed misses you 💤",
            "Tomorrow-you will thank you for sleeping soon 🌙",
            "You did enough today, {name}. Really 💕",
            "Maybe put the screen away soon? 📵",
            "Sleep is magic for tired brains ✨",
            "Let's leave the rest for tomorrow, okay? 🌙",
        ]
        }
    }

    static let weekendCheckIns = [
        "Working on the weekend? Don't forget to play too 🎈",
        "Weekend plan idea: a nap! 😴",
        "Do something just for fun today, {name} 🎨",
    ]

    static func seasonal(month: Int) -> [String] {
        switch month {
        case 12, 1, 2: [
            "Stay warm and cozy today 🧣",
            "Cold outside? A hot drink might be nice ☕",
        ]
        case 3, 4, 5: [
            "Spring is here! Flowers are waking up 🌸",
            "Maybe a little walk among the blossoms? 🌷",
        ]
        case 6, 7, 8: [
            "Summer days! Drink extra water 💧",
            "Sunshine check: wear sunscreen if you go out ☀️",
        ]
        case 9, 10, 11: [
            "Autumn leaves are so pretty right now 🍂",
            "Cozy autumn vibes. A warm drink, maybe? 🍵",
        ]
        default: []
        }
    }

    static let cheers = [
        "You're doing amazing, {name}! 🌟",
        "Don't forget to drink some water 💧",
        "Little stretch break? Your shoulders will thank you 🌱",
        "Blink slowly and look far away for a sec 🌤️",
        "I'm really glad you're here 💕",
        "One small step at a time. You've got this 🌱",
        "Proud of you for showing up today ✨",
        "It's okay to go slow. Slow is still moving 🐢",
        "You matter so much 🍡💕",
        "Breathe in… breathe out… you're doing fine ☁️",
        "Hey {name}, you're pretty wonderful, you know? 💖",
        "Your hard work is adding up, even when it's quiet 🌱",
        "Mistakes are just practice. You're learning 💡",
        "I believe in you! 🍡",
        "Remember to smile a little today 😊",
        "You make this little desk a happy place 🌷",
        "You're braver than you think 🦁",
        "Little progress is still progress 🌱",
        "You don't have to be perfect to be amazing ✨",
        "The world is better with you in it 🌍💕",
        "Be as kind to yourself as you are to others 🌷",
        "You're growing, just like my sprout 🌱",
        "Rest when you need to. That's allowed 💤",
        "You've handled hard things before. You can again 💪",
        "I'm your number one fan! 📣",
        "Your ideas are worth sharing 💡",
        "Today you, plus a snack, equals unstoppable 🍪",
    ]

    static let funFacts = [
        "Did you know? Otters hold hands while they sleep 🦦",
        "Fun fact: cows have best friends 🐄💕",
        "Did you know? Honey never goes bad 🍯",
        "Fun fact: a group of flamingos is a flamboyance 🦩",
        "Did you know? Bananas are berries! 🍌",
        "Fun fact: octopuses have three hearts 🐙",
        "Did you know? Sea turtles can live 100 years 🐢",
        "Fun fact: wombat poop is cube-shaped 🟫",
        "Did you know? Koalas sleep up to 22 hours a day 🐨",
        "Fun fact: mochi is made of pounded rice! 🍡",
        "Did you know? Butterflies taste with their feet 🦋",
        "Fun fact: penguins give pebbles as gifts 🐧",
        "Did you know? Sloths can hold their breath 40 min 🦥",
        "Fun fact: some plants grow better with music 🎶🌱",
        "I wonder what clouds taste like… ☁️",
        "If I had hands, I'd give you a high five ✋",
        "I'm thinking about dumplings again 🥟",
        "My sprout grew a tiny bit today! 🌱",
    ]

    static let breakDone = [
        "Thank you for resting 💕 Back at it together!",
        "Ahh, refreshed! You take such good care of yourself ✨",
        "That was a nice break. I'm proud of you 🌱",
        "Welcome back! Feeling a bit lighter? ☁️",
        "Break complete! Gold star for you ⭐",
        "Rested and ready. Let's go, {name}! 🌱",
        "Your eyes and body say thank you 💕",
    ]

    static let welcomeBack = [
        "Welcome back, {name}! I missed you 💕",
        "Yay, you're back! 🍡",
        "Hi again! Hope that was a nice little pause 🌷",
        "There you are! Ready when you are 🌱",
        "I kept your seat warm! 🪑",
        "Welcome back! Did you get some water? 💧",
    ]

    static let lateWelcome = [
        "Oh hi! It's late, so don't stay up too long 🌙",
    ]

    static let hello = [
        "Oh, hi there! 👋",
        "Hello, {name}! 💕",
        "Hi hi! I'm right here 🌱",
        "Peekaboo! 🙈",
        "Hey you! Doing okay? 🌷",
        "Oh! You came to visit me 💕",
        "Hiya! Nice to see you 😊",
        "*waves sprout* Hello! 🌱",
    ]

    static let tapped = [
        "Hehe, that tickles! 🍡",
        "Hi hi! 👋 I'm right here with you",
        "Boop! You're doing great 💕",
        "You're my favourite human 💖",
        "I'm cheering for you! 📣",
        "*happy wiggle* 🌱",
        "Hello, {name}! Need a hug? 🤗",
        "Squish! Hehe 🍡",
        "You found me! 🙈",
        "*sprout wiggles happily* 🌱",
        "I like it when you say hi 💕",
        "Pat pat. You're doing so well 🫶",
    ]

    static let focusStart = [
        "Let's do this together! 🌱",
        "Focus time! I'll be right here 💕",
        "You've got this, {name}! ✨",
        "Ready, set, sprout! 🌱",
        "Let's make some magic happen ✨",
        "Deep breath, and go! I believe in you 💪",
    ]
}
