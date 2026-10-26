import SwiftUI
import AppKit
import DynaNotchCore

/// Reference-counted SystemMonitorService sampling, so the System tab, the Home Network card and the header's
/// System Stats button can each ask for live numbers without switching each other off.
enum SystemSampling {
    private static var holders = Set<String>()

    static func acquire(_ token: String) {
        holders.insert(token)
        SystemMonitorService.shared.setActive(true)
    }

    static func release(_ token: String) {
        holders.remove(token)
        if holders.isEmpty { SystemMonitorService.shared.setActive(false) }
    }
}

/// Settings → AI Usage → Hide Personal Info: masks project names and home paths.
enum PersonalInfo {
    static func project(_ name: String, hidden: Bool) -> String {
        guard hidden, let first = name.first else { return name }
        return String(first) + String(repeating: "•", count: max(3, min(8, name.count - 1)))
    }

    static func path(_ text: String, hidden: Bool) -> String {
        guard hidden else { return text }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return text.replacingOccurrences(of: home, with: "~").replacingOccurrences(of: NSUserName(), with: "••••")
    }
}
