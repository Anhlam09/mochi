import SwiftUI
import MochiCore
import MochiUI

/// Bridges the timer engine to the floating mascot: maps phases to poses,
/// shows the current tip in a bubble, and handles taps on Mochi.
struct MascotHost: View {
    let engine: TimerEngine
    let settings: MochiSettings
    let companion: Companion
    let todos: TodoStore
    let todoCoordinator: TodoCoordinator
    let conversation: ConversationCoordinator

    var body: some View {
        let todoLine = companion.todoLine
        let talk = conversation
        let basePose = Self.pose(for: engine, talking: todoLine != nil || companion.conversationText != nil
                                 || (Self.bubble(for: engine) == nil && companion.message != nil))
        MascotView(
            pose: talk.isThinking ? .thinking : talk.isListening ? .listening : basePose,
            progress: engine.progress,
            bubbleText: companion.conversationText ?? todoLine ?? Self.bubble(for: engine) ?? companion.message,
            size: MascotSize(rawValue: settings.mascotSize) ?? .medium,
            hoverText: Self.hoverText(for: engine),
            // Low Power Mode always gets the low-CPU animation.
            calm: settings.calmMode || ProcessInfo.processInfo.isLowPowerModeEnabled,
            flavor: MochiFlavor(rawValue: settings.flavor) ?? .strawberry,
            onTap: { if talk.isActive { talk.interrupt() } else { Self.handleTap(engine, companion: companion) } },
            onHoverStart: { companion.hovered() },
            todoBadge: settings.todosEnabled ? Self.leftToday(todos, todoCoordinator) : nil,
            onTodoTap: { todoCoordinator.toggleCard() },
            listening: talk.isListening && talk.showsListeningPrompt,
            liveText: talk.isListening ? talk.liveText : nil,
            onHoldStart: { talk.holdStart() },
            onHoldEnd: { talk.holdEnd() }
        )
    }

    /// Reads the day clock so the count refreshes at midnight.
    static func leftToday(_ todos: TodoStore, _ coordinator: TodoCoordinator) -> Int {
        _ = coordinator.dayClock.day
        return todos.counts(now: Date()).left
    }

    /// `talking`: Mochi is saying a friendly line, so idle or working Mochi shows its happy talking face.
    static func pose(for engine: TimerEngine, talking: Bool = false) -> MascotPose {
        switch engine.phase {
        case .idle:
            return talking ? .chatting : .idle
        case .focusing:
            if engine.remaining <= TimerEngine.almostDoneWindow { return .almostDone }
            return talking ? .chatting : .working
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
        // A to-do line in the bubble: tapping Mochi opens the card instead.
        if companion.consumeTodoTap() { return }
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
