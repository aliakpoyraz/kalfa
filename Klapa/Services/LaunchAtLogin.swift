import Foundation
import ServiceManagement

/// Login-item registration through `SMAppService`, which needs no helper bundle
/// and no privileged install step.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns false when the user has the item disabled in System Settings —
    /// in that case macOS refuses registration and only they can undo it.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            Log.display.error("login item change failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
