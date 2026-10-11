import SwiftUI
import MochiCore
import MochiUI
import ServiceManagement

private let lavender = Palette.focusRing
private let sky = Palette.breakRing
private let blush = Palette.blush

struct MenuBarView: View {
    let engine: TimerEngine
    let settings: MochiSettings
    @State private var loginStatus = LaunchAtLogin.status
    @State private var loginError: String?

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription)"
        }
        loginStatus = LaunchAtLogin.status
    }

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
                adjustRow
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

            DisclosureGroup("Settings ⚙︎") {
              VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Mochi on screen", isOn: $settings.showMascot)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(.callout, design: .rounded))

                if settings.showMascot {
                    Picker("Size", selection: Binding(
                    get: { settings.mascotSize },
                    set: { raw in AppModel.shared.setMascotSize(MascotSize(rawValue: raw) ?? .medium) })) {
                        ForEach(MascotSize.allCases, id: \.rawValue) { size in
                            Text(size.displayName).tag(size.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .font(.system(.callout, design: .rounded))
                }

                Toggle("Start automatically when Mochi opens", isOn: $settings.autoStart)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(.callout, design: .rounded))

                Toggle("Calm mode (saves battery)", isOn: $settings.calmMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(.callout, design: .rounded))

                Toggle("Sound", isOn: $settings.soundEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(.callout, design: .rounded))

                Toggle("Open Mochi at login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled(loginStatus) },
                    set: { setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(.callout, design: .rounded))
                if let loginError {
                    Text(loginError)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loginStatus == .requiresApproval {
                    Text("Waiting for approval: approve in System Settings → Login Items")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Button("Open Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                        .font(.system(.caption, design: .rounded))
                }
              }
              .padding(.top, 6)
            }
            .font(.system(.callout, design: .rounded))

            Button("Quit Mochi") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { loginStatus = LaunchAtLogin.status; loginError = nil }
        .font(.system(.body, design: .rounded))
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 8) {
            switch engine.phase {
            case .idle:
                pill("Start focus 🌱", lavender) { engine.start() }
            case .focusing:
                pill("Take break now", sky) { engine.startBreak() }
                HStack(spacing: 8) {
                    pill("Pause", lavender) { engine.pause() }
                    pill("Reset", lavender) { engine.reset() }
                    pill("Stop", lavender) { engine.stop() }
                }
            case .breakDue(_, let n):
                pill("Start break", sky) { engine.startBreak() }
                HStack(spacing: 8) {
                    pill("Skip", lavender) { engine.skipBreak() }
                }
                snoozeRow(used: n)
            case .snoozed:
                pill("Start break", sky) { engine.startBreak() }
                pill("Skip break", lavender) { engine.skipBreak() }
            case .onBreak:
                HStack(spacing: 8) {
                    pill("Pause", lavender) { engine.pause() }
                    pill("Skip break", lavender) { engine.skipBreak() }
                    pill("Stop", lavender) { engine.stop() }
                }
            case .paused:
                HStack(spacing: 8) {
                    pill("Resume", sky) { engine.resume() }
                    pill("Reset", lavender) { engine.reset() }
                    pill("Stop", lavender) { engine.stop() }
                }
            }
        }
    }

    @ViewBuilder private var adjustRow: some View {
        switch engine.phase {
        case .focusing, .onBreak, .snoozed, .paused:
            HStack(spacing: 6) {
                ForEach([(-1, "−1"), (1, "+1"), (5, "+5")], id: \.0) { m, label in
                    Button { engine.adjust(by: Double(m) * 60) } label: {
                        Text(label)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(accent.opacity(0.4), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m == -1 ? "Subtract 1 minute" : "Add \(m) minute\(m == 1 ? "" : "s")")
                }
                Text("min").font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private func snoozeRow(used: Int) -> some View {
        let maxed = used >= TimerEngine.maxSnoozes
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("Snooze").font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                ForEach([1, 5, 10], id: \.self) { m in
                    Button { engine.snooze(minutes: m) } label: {
                        Text("\(m) min")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(blush.opacity(maxed ? 0.12 : 0.4), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(maxed)
                    .accessibilityLabel("Snooze \(m) minute\(m == 1 ? "" : "s")")
                }
            }
            if used == TimerEngine.maxSnoozes - 1 {
                Text("Last snooze 💤").font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
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
