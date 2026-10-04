import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindowController: NotchWindowController?
    var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupNotchWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: – Menu bar icon
    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            btn.image = NSImage(systemSymbolName: "capsule.fill",
                                accessibilityDescription: "DynaNotch")?.withSymbolConfiguration(cfg)
            btn.image?.isTemplate = true
            btn.toolTip = "DynaNotch"
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "DynaNotch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let nowPlayingItem = NSMenuItem(title: "Toggle Music Widget", action: #selector(forceExpand), keyEquivalent: "")
        nowPlayingItem.target = self
        menu.addItem(nowPlayingItem)

        let testMusicItem = NSMenuItem(title: "Test Music Preview", action: #selector(testMusicPreview), keyEquivalent: "")
        testMusicItem.target = self
        menu.addItem(testMusicItem)

        let volHUDItem = NSMenuItem(title: "Test Volume HUD", action: #selector(testVolumeHUD), keyEquivalent: "")
        volHUDItem.target = self
        menu.addItem(volHUDItem)

        let batHUDItem = NSMenuItem(title: "Test Battery HUD", action: #selector(testBatteryHUD), keyEquivalent: "")
        batHUDItem.target = self
        menu.addItem(batHUDItem)

        let notifItem = NSMenuItem(title: "Test Notification", action: #selector(testNotification), keyEquivalent: "")
        notifItem.target = self
        menu.addItem(notifItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit DynaNotch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: – Actions
    @objc func forceExpand() {
        NotificationCenter.default.post(name: .toggleNotchExpand, object: nil)
    }

    @objc func testMusicPreview() {
        NotificationCenter.default.post(name: .testMusicPreview, object: nil)
    }

    @objc func testVolumeHUD() {
        NotificationCenter.default.post(name: .testVolumeHUD, object: nil)
    }

    @objc func testBatteryHUD() {
        NotificationCenter.default.post(name: .testBatteryHUD, object: nil)
    }

    @objc func testNotification() {
        NotificationCenter.default.post(name: .testNotification, object: nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil || !(settingsWindow?.isVisible ?? false) {
            let hostingVC = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hostingVC)
            win.title = "DynaNotch Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.setContentSize(NSSize(width: 440, height: 600))
            win.center()
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: – Notch window
    private func setupNotchWindow() {
        notchWindowController = NotchWindowController()
        notchWindowController?.showWindow(nil)
    }
}
