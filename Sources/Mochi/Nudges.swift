import AppKit
import Foundation
import Observation
import UserNotifications
import MochiCore

/// Break-due / welcome-back notifications and optional sounds.
@MainActor
final class Nudger: NSObject, UNUserNotificationCenterDelegate {
    private static let dueID = "mochi.breakDue"
    private static let backID = "mochi.back"

    private let engine: TimerEngine
    private let settings: MochiSettings
    private let center: UNUserNotificationCenter?
    private var playing: [NSSound] = []

    init(engine: TimerEngine, settings: MochiSettings) {
        self.engine = engine
        self.settings = settings
        // Bare binaries (no bundle) crash when touching UNUserNotificationCenter.
        self.center = Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
        super.init()
        guard let center else { return }
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: "START", title: "Start break", options: []),
            UNNotificationAction(identifier: "SNOOZE", title: "Snooze 5 min", options: []),
            UNNotificationAction(identifier: "SKIP", title: "Skip", options: []),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "BREAK_DUE", actions: actions, intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        trackPhase()
    }

    func handle(_ event: EngineEvent) {
        switch event {
        case .breakDue:
            post(id: Self.dueID, title: "Time for a little break 🌱",
                 body: engine.currentTip ?? "Step away for a moment.", category: "BREAK_DUE")
            play("Glass")
        case .breakCompleted:
            post(id: Self.backID, title: "Welcome back ✨", body: "Nice rest. Let's focus again!", category: nil)
            play("Purr")
        case .breakStarted, .breakEnded, .almostDone:
            break
        }
    }

    /// Clears the break-due notification whenever the phase is no longer breakDue
    /// (covers start, skip and snooze from the menu, the mascot or the notification).
    private func trackPhase() {
        let phase = withObservationTracking {
            engine.phase
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackPhase() }
        }
        if case .breakDue = phase { return }
        center?.removeDeliveredNotifications(withIdentifiers: [Self.dueID])
        center?.removePendingNotificationRequests(withIdentifiers: [Self.dueID])
    }

    private func post(id: String, title: String, body: String, category: String?) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { [weak self] _ in
            // Race: the phase may have moved on while the request was being delivered.
            Task { @MainActor in
                guard let self, id == Self.dueID else { return }
                switch self.engine.phase {
                case .breakDue, .snoozed: break
                default: self.center?.removeDeliveredNotifications(withIdentifiers: [Self.dueID])
                }
            }
        }
    }

    private func play(_ name: String) {
        guard settings.soundEnabled, let sound = NSSound(named: name) else { return }
        playing.removeAll { !$0.isPlaying }
        if playing.count >= 3 { playing.removeFirst() }
        playing.append(sound)
        sound.play()
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            switch engine.phase {
            case .breakDue, .snoozed:
                switch action {
                case "START": engine.startBreak()
                case "SNOOZE": engine.snooze(minutes: 5)
                case "SKIP": engine.skipBreak()
                default: break
                }
            default: break
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
