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
        engine.start()
        engine.startTicking()

        panel = FloatingPanelController(rootView: MascotHost(engine: engine))
        trackMascotVisibility()
    }

    private var panel: FloatingPanelController?

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
