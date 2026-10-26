import Foundation
import os
import ServiceManagement

/// Launch at login via SMAppService (macOS 13+).
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "launchatlogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            logger.error("launch at login change failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
