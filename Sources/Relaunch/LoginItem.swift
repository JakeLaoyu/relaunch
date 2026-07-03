import ServiceManagement
import AppKit

/// Launch-at-login backed by SMAppService (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the change actually took, so the UI can roll back.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Relaunch: login item toggle failed: \(error)")
            return false
        }
    }
}
