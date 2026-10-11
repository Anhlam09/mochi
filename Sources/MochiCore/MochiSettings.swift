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
    public var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }

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
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
    }

    public var preset: Preset {
        if presetID == "custom" { return .custom(focusMinutes: customFocusMinutes, breakMinutes: customBreakMinutes) }
        return Preset.preset(id: presetID) ?? .gentle
    }
}
