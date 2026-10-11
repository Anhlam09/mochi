import SwiftUI
import MochiCore

@main
struct MochiApp: App {
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: model.engine, settings: model.settings)
        } label: {
            Text(Self.label(for: model.engine))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
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
