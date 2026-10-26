import AppKit
import SwiftUI

/// Owns the AppKit settings window hosting `SettingsRootView` (CLAUDE.md §6.3).
final class SettingsWindowController: NSObject {
    private let viewModel: IslandViewModel
    private var window: NSWindow?

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DynaNotch Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false

        let root = SettingsRootView()
            .environmentObject(viewModel)
            .environmentObject(AppSettings.shared)
            .environmentObject(NowPlayingService.shared)
            .environmentObject(BatteryService.shared)
            .environmentObject(CalendarService.shared)
            .environmentObject(FocusService.shared)
            .environmentObject(MediaKeyTap.shared)
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 720, height: 520))
        window.center()
        return window
    }
}
