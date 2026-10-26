import SwiftUI
import AppKit

@main
struct DynaNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All windows are AppKit-managed (island panel + SettingsWindowController). SwiftUI still needs a scene, and
        // macOS opens this one by itself (⌘, / app menu "Settings…", or window restoration after a quit) — it would
        // show as an empty "DynaNotch Settings" window, so it closes itself and opens the real settings instead.
        Settings {
            SettingsSceneRedirect()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .dynaNotchOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Content of the placeholder Settings scene: closes its window and opens the real settings window.
private struct SettingsSceneRedirect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        DispatchQueue.main.async {
            if let window = view.window {
                window.isRestorable = false
                window.close()
            }
            // Restored by macOS while launching → just close it; asked for by the user → open the real settings.
            if ProcessInfo.processInfo.systemUptime - AppLaunch.uptime > 3 {
                NotificationCenter.default.post(name: .dynaNotchOpenSettings, object: nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// When the process started (system uptime), captured before any scene is built.
enum AppLaunch {
    static let uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
}
