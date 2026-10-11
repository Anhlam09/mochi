import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`.
enum LaunchAtLogin {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// True when registered (including awaiting user approval).
    static var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
