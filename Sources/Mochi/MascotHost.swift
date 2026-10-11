import SwiftUI
import MochiCore
import MochiUI

/// Bridges the timer engine to the floating mascot: maps phases to poses,
/// shows the current tip in a bubble, and handles taps on Mochi.
struct MascotHost: View {
    let engine: TimerEngine
    let settings: MochiSettings
    let companion: Companion

    var body: some View {
        MascotView(
            pose: Self.pose(for: engine),
            progress: engine.progress,
            bubbleText: Self.bubble(for: engine) ?? companion.message,
            size: MascotSize(rawValue: settings.mascotSize) ?? .medium,
            hoverText: Self.hoverText(for: engine),
            calm: settings.calmMode,
            onTap: { Self.handleTap(engine, companion: companion) }
        )
    }

    static func pose(for engine: TimerEngine) -> MascotPose {
        switch engine.phase {
        case .idle:
            return .idle
        case .focusing:
            return engine.remaining <= TimerEngine.almostDoneWindow ? .almostDone : .working
        case .breakDue:
            return .breakDue
        case .snoozed:
            return .idle
        case .onBreak:
            return .onBreak
        case .paused:
            return .paused
        }
    }

    /// Small "time left" pill shown while hovering over Mochi.
    static func hoverText(for engine: TimerEngine) -> String? {
        let time = MochiApp.format(engine.remaining)
        switch engine.phase {
        case .idle: return "Tap me to start 🌱"
        case .focusing: return "\(time) left"
        case .onBreak: return "Break: \(time)"
        case .snoozed: return "Snoozing: \(time)"
        case .paused: return "Paused · \(time)"
        case .breakDue: return nil
        }
    }

    static func bubble(for engine: TimerEngine) -> String? {
        switch engine.phase {
        case .breakDue:
            return engine.currentTip ?? "Break time! Tap me 🌱"
        case .onBreak:
            return engine.now.timeIntervalSince(engine.phaseStartedAt) < 4 ? "Ahh, rest time ☁️" : nil
        default:
            return nil
        }
    }

    /// Tapping Mochi does the obvious thing for the moment: start a due break,
    /// or wake up from a pause. Otherwise Mochi just says something sweet.
    static func handleTap(_ engine: TimerEngine, companion: Companion) {
        switch engine.phase {
        case .breakDue, .snoozed:
            engine.startBreak()
        case .paused:
            engine.resume()
        case .idle:
            engine.start()
            companion.say(.focusStart)
        case .focusing, .onBreak:
            companion.say(.tapped)
        }
    }
}
