import AppKit
import SwiftUI
import Combine
import DynaNotchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: IslandViewModel?
    private var islandController: IslandWindowController?
    private var statusItemController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var openSettingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let vm = IslandViewModel()
        viewModel = vm

        let island = IslandWindowController(viewModel: vm)
        islandController = island
        island.show()

        vm.start()

        settingsController = SettingsWindowController(viewModel: vm)
        statusItemController = StatusItemController(viewModel: vm)

        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .dynaNotchOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }

        let settings = AppSettings.shared
        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.openSettings()
                AppSettings.shared.hasCompletedOnboarding = true
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = openSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
            openSettingsObserver = nil
        }
        NowPlayingService.shared.stop()
    }

    /// dynanotch://simulate/<demo>, dynanotch://expand, dynanotch://collapse, dynanotch://settings,
    /// dynanotch://tab/<tab>, dynanotch://notify?title=…&body=…&symbol=…&duration=…
    /// Used by scripts/build_agent.sh and shell hooks (e.g. Claude Code) to drive the island.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "dynanotch" {
            let action = url.host ?? ""
            let argument = url.pathComponents.dropFirst().first ?? ""
            switch action {
            case "simulate":
                if let demo = DemoActivity(rawValue: argument) { viewModel?.simulate(demo) }
            case "expand":
                viewModel?.expand()
            case "collapse":
                viewModel?.collapse()
            case "settings":
                openSettings()
            case "tab":
                if let tab = PanelTab(rawValue: argument) { viewModel?.open(tab: tab) }
            case "notify":
                if let notification = NotifyURL.parse(url) { viewModel?.notify(notification) }
            case "snapshot":
                // dynanotch://snapshot/<name> → ~/Library/Application Support/DynaNotch/Snapshots/<name>.png
                let name = argument.isEmpty ? "panel" : argument
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let file = base.appendingPathComponent("DynaNotch/Snapshots/\(name).png")
                // Let pending animations settle first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.islandController?.snapshot(to: file)
                }
            case "timer":
                // dynanotch://timer/25 → 25-minute countdown, dynanotch://timer/stop → reset
                if argument == "stop" {
                    TimerService.shared.reset()
                } else if let minutes = Double(argument), minutes > 0 {
                    TimerService.shared.startCountdown(minutes: minutes, label: "Timer")
                }
            default:
                break
            }
        }
    }

    private func openSettings() {
        settingsController?.show()
    }
}
