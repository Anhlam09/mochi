import Foundation
import MochiCore

/// The one-time first-launch intro: a short hello, then a polite ask before the notification
/// permission prompt. People who already used Mochi are never welcomed again or re-prompted.
@MainActor
final class WelcomeCoordinator {
    private let settings: MochiSettings
    private let store: TodoStore
    private let companion: Companion
    private let nudger: Nudger
    private var task: Task<Void, Never>?

    init(settings: MochiSettings, store: TodoStore, companion: Companion, nudger: Nudger) {
        self.settings = settings
        self.store = store
        self.companion = companion
        self.nudger = nudger
    }

    func startIfNeeded() {
        guard task == nil else { return }
        if Welcome.alreadyWelcomed(hasWelcomed: settings.hasWelcomed, hasTodos: !store.items.isEmpty,
                                   looksLikeExistingInstall: settings.looksLikeExistingInstall) {
            settings.hasWelcomed = true
            return
        }
        settings.hasWelcomed = true   // once per install, even if Mochi quits halfway
        let showBubbles = settings.showMascot
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            if showBubbles {
                try? await Task.sleep(for: .seconds(2))
                self.companion.sayNotice(Welcome.intro, seconds: 12)
                try? await Task.sleep(for: .seconds(14))
                self.companion.sayNotice(Welcome.permissionAsk, seconds: 8)
                try? await Task.sleep(for: .milliseconds(600))   // let the question land first
            } else {
                try? await Task.sleep(for: .seconds(5))
            }
            self.nudger.requestPermissionIfNeeded()
        }
    }
}
