import AppKit
import SwiftUI

/// Owns the AppKit settings window hosting `SettingsRootView` (CLAUDE.md §6.3).
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let viewModel: IslandViewModel
    private var window: NSWindow?

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    /// Closing drops the SwiftUI content so its status timers (permissions, suggestions…) stop; show() rebuilds it.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, !window.isVisible else { return }
            window.contentViewController = nil
            self?.window = nil
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var testWindow: NSWindow? { window }

    /// Debug (`dynanotch://snapshot-settings/<page>`): renders the settings window content to a PNG.
    func snapshot(to url: URL) {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DynaNotch Settings"
        window.isReleasedWhenClosed = false
        // Never reopened by macOS window restoration at launch (only when the user asks for Settings).
        window.isRestorable = false
        window.delegate = self

        let root = SettingsRootView()
            .environmentObject(viewModel)
            .environmentObject(AppSettings.shared)
            .environmentObject(NowPlayingService.shared)
            .environmentObject(BatteryService.shared)
            .environmentObject(CalendarService.shared)
            .environmentObject(FocusService.shared)
            .environmentObject(MediaKeyTap.shared)
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 860, height: 640))
        window.center()
        return window
    }
}
