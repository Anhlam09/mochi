import SwiftUI

/// What Mochi is currently doing. The app maps engine phases to these.
public enum MascotPose: String, CaseIterable, Sendable {
    case idle, working, almostDone, breakDue, onBreak, paused, chatting

    public var accessibilityDescription: String {
        switch self {
        case .idle: "Mochi is relaxing"
        case .working: "Mochi is focusing with you"
        case .almostDone: "Mochi is getting sleepy, a break is coming up"
        case .breakDue: "Mochi is happily waving, it is time for a break"
        case .onBreak: "Mochi is napping while you take a break"
        case .paused: "Mochi is paused"
        case .chatting: "Mochi is happily talking to you"
        }
    }

    /// Ring colour associated with this pose.
    public var ringTint: Color {
        switch self {
        case .idle, .working, .almostDone, .chatting: Palette.focusRing
        case .breakDue, .onBreak: Palette.breakRing
        case .paused: Palette.ink.opacity(0.35)
        }
    }
}
