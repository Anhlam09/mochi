import Foundation
import Observation

@MainActor @Observable
public final class MochiSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var presetID: String { didSet { defaults.set(presetID, forKey: "presetID") } }
    public var customFocusMinutes: Int { didSet { defaults.set(customFocusMinutes, forKey: "customFocusMinutes") } }
    public var customBreakMinutes: Int { didSet { defaults.set(customBreakMinutes, forKey: "customBreakMinutes") } }
    public var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "soundEnabled") } }
    public var showMascot: Bool { didSet { defaults.set(showMascot, forKey: "showMascot") } }
    public var autoStart: Bool { didSet { defaults.set(autoStart, forKey: "autoStart") } }
    /// "small" | "medium" | "large" (raw values of MochiUI.MascotSize).
    public var mascotSize: String { didSet { defaults.set(mascotSize, forKey: "mascotSize") } }
    /// Gentler, low-CPU animation for the floating mascot.
    public var calmMode: Bool { didSet { defaults.set(calmMode, forKey: "calmMode") } }
    /// How often Mochi says kind things unprompted (raw value of `ChatLevel`).
    public var chatLevel: String { didSet { defaults.set(chatLevel, forKey: "chatLevel") } }
    /// What Mochi calls the user; empty means no name.
    public var friendName: String { didSet { defaults.set(friendName, forKey: "friendName") } }
    /// Mochi's colour flavour (raw value of MochiUI.MochiFlavor).
    public var flavor: String { didSet { defaults.set(flavor, forKey: "flavor") } }
    /// Switch to the next flavour (with a spin) every couple of hours.
    public var flavorRotation: Bool { didSet { defaults.set(flavorRotation, forKey: "flavorRotation") } }

    /// To-do agent (all local): master switch, wrap-up time, and the optional gentle nudges.
    public var todosEnabled: Bool { didSet { defaults.set(todosEnabled, forKey: "todosEnabled") } }
    public var todoNudges: Bool { didSet { defaults.set(todoNudges, forKey: "todoNudges") } }
    /// Show the to-do's text in reminder notifications (off: "You have a to-do now").
    public var todoNotificationText: Bool { didSet { defaults.set(todoNotificationText, forKey: "todoNotificationText") } }
    /// On-device AI (Apple Intelligence) for kind lines and "Ask Mochi". Does nothing unless the Mac supports it.
    public var smartMochi: Bool { didSet { defaults.set(smartMochi, forKey: "smartMochi") } }
    /// How often Mochi offers a kind word on its own (raw value of `Positivity`).
    public var positivity: String { didSet { defaults.set(positivity, forKey: "positivity") } }
    public var todoWrapUpHour: Int { didSet { defaults.set(todoWrapUpHour, forKey: "todoWrapUpHour") } }
    public var todoWrapUpMinute: Int { didSet { defaults.set(todoWrapUpMinute, forKey: "todoWrapUpMinute") } }

    // Mochi's little extras
    /// Greet with the day part and date when you come back after 10+ minutes away.
    public var wakeGreeting: Bool { didSet { defaults.set(wakeGreeting, forKey: "wakeGreeting") } }
    public var goodNight: Bool { didSet { defaults.set(goodNight, forKey: "goodNight") } }
    /// Hour (19-23) for the good-night line.
    public var goodNightHour: Int { didSet { defaults.set(goodNightHour, forKey: "goodNightHour") } }
    /// Raw value of `MealMode`.
    public var mealIdeas: String { didSet { defaults.set(mealIdeas, forKey: "mealIdeas") } }
    /// Minutes between self-care nudges; 0 is off.
    public var selfCareMinutes: Int { didSet { defaults.set(selfCareMinutes, forKey: "selfCareMinutes") } }
    // Talk to Mochi (on-device speech only)
    public var talkEnabled: Bool { didSet { defaults.set(talkEnabled, forKey: "talkEnabled") } }
    public var talkHoldEnabled: Bool { didSet { defaults.set(talkHoldEnabled, forKey: "talkHoldEnabled") } }
    public var talkShortcutEnabled: Bool { didSet { defaults.set(talkShortcutEnabled, forKey: "talkShortcutEnabled") } }
    /// The first-launch welcome has been shown (or was not needed). Once per install.
    public var hasWelcomed: Bool { didSet { defaults.set(hasWelcomed, forKey: "hasWelcomed") } }
    /// True if any setting was already stored when this object was created, i.e. Mochi has run here before.
    @ObservationIgnored public let looksLikeExistingInstall: Bool

    private static let installMarkers = ["presetID", "customFocusMinutes", "customBreakMinutes", "soundEnabled", "showMascot",
                                         "autoStart", "mascotSize", "calmMode", "chatLevel", "friendName", "flavor",
                                         "flavorRotation", "wakeGreeting", "goodNight", "goodNightHour", "mealIdeas", "selfCareMinutes", "talkEnabled", "talkHoldEnabled", "talkShortcutEnabled", "todosEnabled", "todoNudges", "smartMochi", "positivity"]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        looksLikeExistingInstall = Self.installMarkers.contains { defaults.object(forKey: $0) != nil }
        wakeGreeting = defaults.object(forKey: "wakeGreeting") as? Bool ?? true
        goodNight = defaults.object(forKey: "goodNight") as? Bool ?? true
        goodNightHour = min(23, max(19, defaults.object(forKey: "goodNightHour") as? Int ?? 20))
        mealIdeas = defaults.string(forKey: "mealIdeas").flatMap(MealMode.init(rawValue:))?.rawValue ?? MealMode.any.rawValue
        let care = defaults.object(forKey: "selfCareMinutes") as? Int ?? 60
        selfCareMinutes = SelfCare.options.contains(care) ? care : 60
        talkEnabled = defaults.object(forKey: "talkEnabled") as? Bool ?? true
        talkHoldEnabled = defaults.object(forKey: "talkHoldEnabled") as? Bool ?? true
        talkShortcutEnabled = defaults.object(forKey: "talkShortcutEnabled") as? Bool ?? true
        hasWelcomed = defaults.object(forKey: "hasWelcomed") as? Bool ?? false
        let stored = defaults.string(forKey: "presetID") ?? "gentle"
        presetID = (stored == "custom" || Preset.preset(id: stored) != nil) ? stored : "gentle"
        customFocusMinutes = defaults.object(forKey: "customFocusMinutes") as? Int ?? 30
        customBreakMinutes = defaults.object(forKey: "customBreakMinutes") as? Int ?? 5
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? false
        showMascot = defaults.object(forKey: "showMascot") as? Bool ?? true
        autoStart = defaults.object(forKey: "autoStart") as? Bool ?? false
        mascotSize = defaults.string(forKey: "mascotSize") ?? "medium"
        calmMode = defaults.object(forKey: "calmMode") as? Bool ?? true
        chatLevel = defaults.string(forKey: "chatLevel").flatMap(ChatLevel.init(rawValue:))?.rawValue
            ?? ChatLevel.sometimes.rawValue
        flavor = defaults.string(forKey: "flavor") ?? "strawberry"
        flavorRotation = defaults.object(forKey: "flavorRotation") as? Bool ?? true
        todosEnabled = defaults.object(forKey: "todosEnabled") as? Bool ?? true
        todoNudges = defaults.object(forKey: "todoNudges") as? Bool ?? true
        todoNotificationText = defaults.object(forKey: "todoNotificationText") as? Bool ?? true
        smartMochi = defaults.object(forKey: "smartMochi") as? Bool ?? true
        positivity = defaults.string(forKey: "positivity").flatMap(Positivity.init(rawValue:))?.rawValue
            ?? Positivity.fewTimesADay.rawValue
        todoWrapUpHour = min(23, max(0, defaults.object(forKey: "todoWrapUpHour") as? Int ?? 17))
        todoWrapUpMinute = min(59, max(0, defaults.object(forKey: "todoWrapUpMinute") as? Int ?? 30))
        friendName = defaults.string(forKey: "friendName")
            ?? NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    public var mealMode: MealMode { MealMode(rawValue: mealIdeas) ?? .any }

    public var positivityLevel: Positivity { Positivity(rawValue: positivity) ?? .fewTimesADay }

    public var todoAgent: TodoAgentSettings {
        TodoAgentSettings(todosEnabled: todosEnabled, wrapUpHour: todoWrapUpHour,
                          wrapUpMinute: todoWrapUpMinute, nudges: todoNudges)
    }

    public var chat: ChatLevel { ChatLevel(rawValue: chatLevel) ?? .sometimes }

    public var preset: Preset {
        if presetID == "custom" { return .custom(focusMinutes: customFocusMinutes, breakMinutes: customBreakMinutes) }
        return Preset.preset(id: presetID) ?? .gentle
    }
}

/// Decides whether the one-time first-launch welcome is still due.
public enum Welcome {
    /// Someone who already used Mochi (a stored setting, any to-dos, or a prior welcome) never gets it.
    public static func alreadyWelcomed(hasWelcomed: Bool, hasTodos: Bool, looksLikeExistingInstall: Bool) -> Bool {
        hasWelcomed || hasTodos || looksLikeExistingInstall
    }

    public static let intro = "Hi! I'm Mochi 🌱 Click me to start a focus, and tap 📝 for your to-dos."
    public static let permissionAsk = "Can I send you little reminders? 🔔"
}
