import SwiftUI
import MochiCore

struct MochiApp: App {
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: model.engine, settings: model.settings, todos: model.todos,
                        calendar: model.calendar, onOpenTodos: { model.openTodoCard() })
        } label: {
            Text(Self.label(for: model.engine))
                .monospacedDigit()
                .accessibilityLabel(Self.spoken(for: model.engine))
        }
        .menuBarExtraStyle(.window)
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func spoken(for e: TimerEngine) -> String {
        let s = Int(e.remaining.rounded(.up))
        let time = s >= 60 ? "\(s / 60) minutes \(s % 60) seconds" : "\(s) seconds"
        switch e.phase {
        case .idle: return "Mochi, ready to start"
        case .focusing: return "Mochi, \(time) of focus left"
        case .breakDue: return "Mochi, break time"
        case .snoozed: return "Mochi, break snoozed, \(time) left"
        case .onBreak: return "Mochi, on a break, \(time) left"
        case .paused: return "Mochi, paused, \(time) left"
        }
    }

    static func label(for e: TimerEngine) -> String {
        switch e.phase {
        case .idle: return "🌱 Start"
        case .focusing: return "\(e.preset.emoji) \(format(e.remaining))"
        case .breakDue: return "☕️ Break!"
        case .snoozed: return "😴 \(format(e.remaining))"
        case .onBreak: return "💤 \(format(e.remaining))"
        case .paused: return "⏸ \(format(e.remaining))"
        }
    }
}
