import SwiftUI
import MochiCore
import MochiUI

/// Bridges the timer engine to the floating mascot: maps phases to poses,
/// shows the current tip in a bubble, and handles taps on Mochi.
struct MascotHost: View {
    let engine: TimerEngine

    var body: some View {
        MascotView(
            pose: Self.pose(for: engine),
            progress: engine.progress,
            bubbleText: Self.bubble(for: engine),
            onTap: { Self.handleTap(engine) }
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

    static func bubble(for engine: TimerEngine) -> String? {
        switch engine.phase {
        case .breakDue:
            return engine.currentTip ?? "Break time! Tap me 🌱"
        default:
            return nil
        }
    }

    /// Tapping Mochi does the obvious thing for the moment: start a due break,
    /// or wake up from a pause.
    static func handleTap(_ engine: TimerEngine) {
        switch engine.phase {
        case .breakDue, .snoozed:
            engine.startBreak()
        case .paused:
            engine.resume()
        case .idle:
            engine.start()
        case .focusing, .onBreak:
            break
        }
    }
}
