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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            ?? ChatLevel.often.rawValue
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

    public var positivityLevel: Positivity { Positivity(rawValue: positivity) ?? .fewTimesADay }

    public var todoAgent: TodoAgentSettings {
        TodoAgentSettings(todosEnabled: todosEnabled, wrapUpHour: todoWrapUpHour,
                          wrapUpMinute: todoWrapUpMinute, nudges: todoNudges)
    }

    public var chat: ChatLevel { ChatLevel(rawValue: chatLevel) ?? .often }

    public var preset: Preset {
        if presetID == "custom" { return .custom(focusMinutes: customFocusMinutes, breakMinutes: customBreakMinutes) }
        return Preset.preset(id: presetID) ?? .gentle
    }
}
