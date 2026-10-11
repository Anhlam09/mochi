import Foundation

public enum BreakKind: String, Sendable { case eyes, short, stretch, long }

public struct BreakSpec: Sendable, Equatable {
    public let focus: TimeInterval
    public let rest: TimeInterval
    public let kind: BreakKind
    public init(focus: TimeInterval, rest: TimeInterval, kind: BreakKind) {
        self.focus = focus; self.rest = rest; self.kind = kind
    }
}

public struct Preset: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let emoji: String
    private let rule: @Sendable (Int) -> BreakSpec

    public init(id: String, name: String, emoji: String, rule: @escaping @Sendable (Int) -> BreakSpec) {
        self.id = id; self.name = name; self.emoji = emoji; self.rule = rule
    }

    /// `n` = number of completed breaks so far (0-based).
    public func spec(forCycle n: Int) -> BreakSpec { rule(max(0, n)) }

    public static func == (a: Preset, b: Preset) -> Bool {
        a.id == b.id && a.spec(forCycle: 0).focus == b.spec(forCycle: 0).focus
            && a.spec(forCycle: 0).rest == b.spec(forCycle: 0).rest
    }

    public static let gentle = Preset(id: "gentle", name: "Gentle", emoji: "🌱") { n in
        n % 3 == 2
            ? BreakSpec(focus: 20 * 60, rest: 5 * 60, kind: .stretch)
            : BreakSpec(focus: 20 * 60, rest: 20, kind: .eyes)
    }
    public static let pomodoro = Preset(id: "pomodoro", name: "Pomodoro", emoji: "🍅") { n in
        n % 4 == 3
            ? BreakSpec(focus: 25 * 60, rest: 15 * 60, kind: .long)
            : BreakSpec(focus: 25 * 60, rest: 5 * 60, kind: .short)
    }
    public static let deepFocus = Preset(id: "deepFocus", name: "Deep Focus", emoji: "🌊") { _ in
        BreakSpec(focus: 52 * 60, rest: 17 * 60, kind: .short)
    }
    public static func custom(focusMinutes: Int, breakMinutes: Int) -> Preset {
        let spec = BreakSpec(focus: Double(max(1, focusMinutes)) * 60, rest: Double(max(1, breakMinutes)) * 60, kind: .short)
        return Preset(id: "custom", name: "Custom", emoji: "✨") { _ in spec }
    }

    public static let all: [Preset] = [.gentle, .pomodoro, .deepFocus]
    public static func preset(id: String) -> Preset? { all.first { $0.id == id } }
}

public enum Tips {
    static let eyeTips = [
        "Look out the window for 20 seconds — let your eyes wander far away 🌤️",
        "Close your eyes for a few seconds. I'll keep watch.",
        "Blink slowly a few times — your eyes will thank you.",
    ]
    static let bodyTips = [
        "Roll your shoulders back, slowly. Ahh.",
        "Stand up and stretch tall like a little sprout 🌱",
        "Sip some water — future you says thanks 💧",
        "Unclench your jaw, drop your shoulders.",
        "3 slow breaths: in through the nose, out through the mouth.",
        "Gentle neck tilt — left, then right.",
        "Shake out your hands and wrists.",
        "Walk to the kitchen and back — tiny trips count!",
    ]
    public static func random(for kind: BreakKind) -> String {
        (kind == .eyes ? eyeTips : bodyTips).randomElement()!
    }
}
