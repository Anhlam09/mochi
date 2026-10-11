import SwiftUI
import MochiCore

private let lavender = Color(red: 0xB5/255, green: 0xA8/255, blue: 0xFF/255)
private let sky = Color(red: 0x8F/255, green: 0xD9/255, blue: 0xF0/255)
private let blush = Color(red: 0xFF/255, green: 0xB3/255, blue: 0xC1/255)

struct MenuBarView: View {
    let engine: TimerEngine
    let settings: MochiSettings

    private var caption: String {
        switch engine.phase {
        case .idle: return "Ready when you are"
        case .focusing: return "Focusing — you've got this"
        case .breakDue: return "Time for a break!"
        case .snoozed: return "Snoozed — back soon"
        case .onBreak: return engine.currentTip ?? "Take a breather"
        case .paused: return "Paused"
        }
    }

    private var accent: Color {
        switch engine.phase {
        case .breakDue, .snoozed: return blush
        case .onBreak: return sky
        default: return lavender
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text(MochiApp.format(engine.remaining))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: engine.progress).tint(accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))

            controls

            @Bindable var settings = settings
            Picker("Preset", selection: $settings.presetID) {
                ForEach(Preset.all + [Preset.custom(focusMinutes: settings.customFocusMinutes, breakMinutes: settings.customBreakMinutes)]) {
                    Text("\($0.emoji) \($0.name)").tag($0.id)
                }
            }
            .labelsHidden()

            if settings.presetID == "custom" {
                VStack(spacing: 6) {
                    Stepper("Focus: \(settings.customFocusMinutes) min", value: $settings.customFocusMinutes, in: 5...120, step: 5)
                    Stepper("Break: \(settings.customBreakMinutes) min", value: $settings.customBreakMinutes, in: 1...30)
                }
                .font(.system(.callout, design: .rounded))
            }

            Toggle("Show Mochi on screen", isOn: $settings.showMascot)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(.callout, design: .rounded))

            Button("Quit Mochi") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
        .font(.system(.body, design: .rounded))
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 8) {
            switch engine.phase {
            case .idle:
                pill("Start", lavender) { engine.start() }
            case .focusing:
                pill("Take break now", sky) { engine.startBreak() }
                HStack(spacing: 8) {
                    pill("Pause", lavender) { engine.pause() }
                    pill("Reset", lavender) { engine.reset() }
                }
            case .breakDue(_, let n):
                pill("Start break", sky) { engine.startBreak() }
                HStack(spacing: 8) {
                    pill("Snooze 5 min", blush, disabled: n >= TimerEngine.maxSnoozes) { engine.snooze(minutes: 5) }
                    pill("Skip", lavender) { engine.skipBreak() }
                }
            case .snoozed:
                pill("Start break", sky) { engine.startBreak() }
                pill("Skip break", lavender) { engine.skipBreak() }
            case .onBreak:
                HStack(spacing: 8) {
                    pill("Pause", lavender) { engine.pause() }
                    pill("Skip break", lavender) { engine.skipBreak() }
                }
            case .paused:
                HStack(spacing: 8) {
                    pill("Resume", sky) { engine.resume() }
                    pill("Reset", lavender) { engine.reset() }
                }
            }
        }
    }

    private func pill(_ title: String, _ color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Text(title)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(color.opacity(disabled ? 0.12 : 0.35), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
