import SwiftUI

@main
struct DynaNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All windows are AppKit-managed (island panel + settings window); this scene is a placeholder.
        Settings {
            EmptyView()
        }
    }
}
