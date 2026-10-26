import AppKit
import ApplicationServices
import Foundation

/// TCC helpers. Nothing here blocks or shows modal UI of our own.
enum Permissions {
    /// Accessibility is needed for the media-key event tap (HUD replacement).
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system "allow Accessibility" prompt (once per app identity).
    static func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt; using the literal avoids
        // depending on whether the SDK imports that constant as CFString or Unmanaged<CFString>.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openFullDiskAccessSettings() {
        openPrivacyPane("Privacy_AllFiles")
    }

    static func openCalendarSettings() {
        openPrivacyPane("Privacy_Calendars")
    }

    static func openBluetoothSettings() {
        openPrivacyPane("Privacy_Bluetooth")
    }

    private static func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
