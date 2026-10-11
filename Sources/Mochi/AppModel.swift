import Foundation
import Observation
import MochiCore
import MochiUI

/// Owns the single engine + settings for the app. Starts ticking once on first access.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let engine: TimerEngine
    let settings: MochiSettings
    /// Attach panel / sound / notification reactions here.
    var eventHandlers: [@MainActor (EngineEvent) -> Void] = []

    private init() {
        let settings = MochiSettings()
        let env = ProcessInfo.processInfo.environment
        let engine = TimerEngine(
            preset: settings.preset,
            focusOverride: env["MOCHI_FOCUS_SECONDS"].flatMap(Double.init),
            breakOverride: env["MOCHI_BREAK_SECONDS"].flatMap(Double.init)
        )
        self.settings = settings
        self.engine = engine
        engine.onEvent = { [weak self] event in
            self?.eventHandlers.forEach { $0(event) }
        }
        trackPreset()
        if settings.autoStart { engine.start() }
        engine.startTicking()

        let nudger = Nudger(engine: engine, settings: settings)
        self.nudger = nudger
        eventHandlers.append { nudger.handle($0) }

        let idle = env["MOCHI_IDLE_SECONDS"].flatMap(Double.init) ?? 300
        let monitor = SystemMonitor(engine: engine, threshold: idle)
        monitor.start()
        self.monitor = monitor

        panel = FloatingPanelController(
            rootView: MascotHost(engine: engine, settings: settings),
            size: MascotSize(rawValue: settings.mascotSize) ?? .medium
        )
        trackMascotVisibility()
        trackMascotSize()
    }

    private var nudger: Nudger?
    private var monitor: SystemMonitor?
    private var panel: FloatingPanelController?

    /// Sets the size and resizes the panel in the same run-loop turn.
    func setMascotSize(_ size: MascotSize) {
        settings.mascotSize = size.rawValue
        panel?.setSize(size)
    }

    /// Resizes the floating panel to match `settings.mascotSize`.
    private func trackMascotSize() {
        let raw = withObservationTracking {
            settings.mascotSize
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackMascotSize() }
        }
        panel?.setSize(MascotSize(rawValue: raw) ?? .medium)
    }

    /// Shows or hides the floating mascot to match `settings.showMascot`.
    private func trackMascotVisibility() {
        let visible = withObservationTracking {
            settings.showMascot
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackMascotVisibility() }
        }
        if visible { panel?.show() } else { panel?.hide() }
    }

    /// Single place where settings → engine.preset is synced.
    private func trackPreset() {
        withObservationTracking {
            _ = settings.preset
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.engine.preset = self.settings.preset
                self.trackPreset()
            }
        }
    }
}
