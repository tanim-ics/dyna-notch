import AppKit
import SwiftUI
import Combine
import DynaNotchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: IslandViewModel?
    private var islandController: IslandWindowController?
    private var screensCoordinator: IslandScreensCoordinator?
    private var statusItemController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var openSettingsObserver: NSObjectProtocol?
    private var welcomeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppLaunch.uptime   // pin the launch time for SettingsSceneRedirect
        NSApp.setActivationPolicy(.accessory)

        let vm = IslandViewModel()
        viewModel = vm

        let island = IslandWindowController(viewModel: vm)
        islandController = island
        island.show()

        vm.start()

        // Show On → Every display: extra islands on the other displays.
        let coordinator = IslandScreensCoordinator(primary: vm, primaryController: island)
        screensCoordinator = coordinator
        coordinator.start()

        // Lock screen: sounds, the "Unlocked" island and the weather / batteries strip (CONTRACTS §6.11).
        LockScreenController.shared.start { [weak self] in
            guard let self = self, let primary = self.viewModel else { return [] }
            return [primary] + (self.screensCoordinator?.extraViewModels ?? [])
        }

        settingsController = SettingsWindowController(viewModel: vm)
        statusItemController = StatusItemController(viewModel: vm)

        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .dynaNotchOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }

        welcomeObserver = NotificationCenter.default.addObserver(
            forName: .dynaNotchShowWelcome,
            object: nil,
            queue: .main
        ) { _ in
            WelcomeController.shared.show()
        }

        // First launch: the iPhone-style "hello", then tips under the notch.
        // Settings → General → Hello Intro replays just the greeting on every launch.
        let settings = AppSettings.shared
        if !settings.hasSeenWelcome || settings.helloIntro {
            let greetingOnly = settings.hasSeenWelcome
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                WelcomeController.shared.show(greetingOnly: greetingOnly)
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
            case "pin":
                // dynanotch://pin/<tab?> → open (optionally on a tab) and keep the panel open
                // An explicit tab wins over Default Tab / Open on Current Activity, like the palette's "Open …".
                if let tab = PanelTab(rawValue: argument) { viewModel?.open(tab: tab) }
                if viewModel?.isPinned == false { viewModel?.togglePin() }
            case "batteries":
                viewModel?.expand()
                viewModel?.showsBatteries.toggle()
            case "unpin":
                if viewModel?.isPinned == true { viewModel?.togglePin() }
                viewModel?.collapse()
            case "welcome":
                WelcomeController.shared.show()
            case "tab":
                if let tab = PanelTab(rawValue: argument) { viewModel?.open(tab: tab) }
            case "notify":
                if let notification = NotifyURL.parse(url) {
                    // Every island shows it (Show On → Every display); only the primary one plays the sound.
                    viewModel?.notify(notification)
                    screensCoordinator?.extraViewModels.forEach { $0.notify(notification) }
                }
            case "snapshot-palette":
                // dynanotch://snapshot-palette/<name> → Snapshots/<name>.png (palette must be shown)
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                _ = CommandPaletteController.shared.snapshot(
                    to: base.appendingPathComponent("DynaNotch/Snapshots/\(argument.isEmpty ? "palette" : argument).png"))
            case "snapshot-welcome":
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                WelcomeController.shared.snapshot(
                    to: base.appendingPathComponent("DynaNotch/Snapshots/\(argument.isEmpty ? "welcome" : argument).png"))
            case "set":
                // dynanotch://set?dn.notchDisplayStyle=pill → changes settings like the Settings UI does (testing)
                var dict: [String: Any] = [:]
                for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                    guard let value = item.value else { continue }
                    if value == "true" || value == "false" {
                        dict[item.name] = value == "true"
                    } else if let number = Double(value), !value.contains("#") {
                        dict[item.name] = number
                    } else {
                        dict[item.name] = value
                    }
                }
                if let data = try? JSONSerialization.data(withJSONObject: dict) {
                    _ = AppSettings.shared.importJSON(data)
                }
            case "ui":
                // dynanotch://ui/pointer?x=&y= (island canvas points; no query = real pointer again)
                // dynanotch://ui/click?window=island|settings&x=&y=[&alt=1]
                // dynanotch://ui/menu?item=<title>   (the next menu that opens picks that item)
                let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                    .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
                let x = Double(query["x"] ?? "").map { CGFloat($0) }
                let y = Double(query["y"] ?? "").map { CGFloat($0) }
                switch argument {
                case "pointer":
                    if let x = x, let y = y {
                        islandController?.setTestPointer(canvasPoint: NSPoint(x: x, y: y))
                    } else {
                        islandController?.setTestPointer(canvasPoint: nil)
                    }
                case "click":
                    // by coordinates, or by a `.uiTestID` name: dynanotch://ui/click?id=tabMenu
                    let window: NSWindow?
                    switch query["window"] {
                    case "settings": window = settingsController?.testWindow
                    case "palette": window = CommandPaletteController.shared.testWindow
                    case "dmg": window = DMGInstaller.shared.testWindow
                    case "welcome": window = WelcomeController.shared.testWindow
                    default: window = islandController?.testWindow
                    }
                    var point: NSPoint?
                    if let x = x, let y = y { point = NSPoint(x: x, y: y) }
                    if let id = query["id"], let frame = UITestRegistry.shared.frames[id] {
                        point = NSPoint(x: frame.midX, y: frame.midY)
                    }
                    if let window = window, let point = point {
                        UITestDriver.shared.click(in: window, at: point, modifiers: query["alt"] == "1" ? .option : [])
                    }
                case "menu":
                    if let item = query["item"] {
                        UITestDriver.shared.movePointerAway = { [weak self] in
                            self?.islandController?.setTestPointer(canvasPoint: NSPoint(x: 200, y: 310))
                        }
                        UITestDriver.shared.chooseInNextMenu(item, delay: Double(query["delay"] ?? "") ?? 0,
                                                             pointerAway: query["away"] == "1")
                    }
                case "override":
                    // dynanotch://ui/override?fullscreen=1&front=<bundle id>&mirror=1&focus=1 (no query = real values)
                    func flag(_ name: String) -> Bool? { query[name].map { $0 == "1" || $0 == "true" } }
                    islandController?.testFullscreen = flag("fullscreen")
                    islandController?.testFrontBundle = query["front"]
                    islandController?.testMirrored = flag("mirror")
                    viewModel?.testFocusActive = flag("focus")
                case "mediakey":
                    // dynanotch://ui/mediakey?code=16[&up=1] → the media-key handler, as the event tap calls it
                    if let code = Int(query["code"] ?? "") {
                        let flags = query["up"] == "1" ? 0x0B00 : 0x0A00
                        _ = viewModel?.handleMediaKey(MediaKeyEvent(data1: (code << 16) | flags), [])
                    }
                case "palette":
                    // dynanotch://ui/palette?query=<text>&key=down|up|return|escape
                    CommandPaletteController.shared.testInput(query: query["query"], key: query["key"])
                case "systemSettingsAction":
                    // dynanotch://ui/systemSettingsAction → the action ⌘, / "Settings…" sends to the SwiftUI scene
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                case "appMenuSettings":
                    // dynanotch://ui/appMenuSettings → performs the app menu's "Settings…" (⌘,) item
                    if let menu = NSApp.mainMenu?.items.first?.submenu,
                       let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
                        menu.performActionForItem(at: index)
                    }
                case "knock":
                    // dynanotch://ui/knock?count=N → as if the knock key were tapped N times
                    if let count = Int(query["count"] ?? "") { KnockMonitor.shared.simulate(count: count) }
                case "action":
                    // dynanotch://ui/action?name=<HotKeyAction raw> → as if its global shortcut were pressed
                    // dynanotch://ui/action?knock=<KnockAction raw> | ?tab=<PanelTab raw> (per-tab shortcut)
                    if let name = query["name"], let action = HotKeyAction(rawValue: name) {
                        AppActions.shared.perform(action)
                    } else if let name = query["knock"], let knock = KnockAction(rawValue: name) {
                        AppActions.shared.perform(knock: knock)
                    } else if let name = query["tab"], let tab = PanelTab(rawValue: name) {
                        AppActions.shared.toggleTab(tab)
                    }
                default:
                    break
                }
            case "state":
                // dynanotch://state → Snapshots/state.json (island state for scripted tests)
                guard let vm = viewModel else { break }
                let state: [String: Any] = [
                    "presentation": String(describing: vm.presentation),
                    "selectedTab": vm.selectedTab.rawValue,
                    "visibleTab": vm.visibleTab.rawValue,
                    "isPill": vm.isPill,
                    "topInset": Double(vm.topInset),
                    "notchWidth": Double(vm.notch.width),
                    "notchHeight": Double(vm.notch.height),
                    "hasPhysicalNotch": vm.notch.hasPhysicalNotch,
                    "isOnNotchDisplay": vm.isOnNotchDisplay,
                    "isHovering": vm.isHovering,
                    "isPinned": vm.isPinned,
                    "isUserHidden": vm.isUserHidden,
                    "headerCard": vm.headerCard?.rawValue ?? "none",
                    "palette": CommandPaletteController.shared.isShown,
                    "paletteQuery": CommandPaletteController.shared.testQuery,
                    "paletteSelection": CommandPaletteController.shared.testSelectionTitle,
                    "desktopLyrics": DesktopLyricsController.shared.isShowing,
                    "edgeGlow": EdgeGlowController.shared.lastFlash,
                    "knock": KnockMonitor.shared.lastKnock,
                    "knockAction": KnockMonitor.shared.lastAction,
                    "knockRunning": KnockMonitor.shared.isRunning,
                    "hotkeys": HotKeyService.shared.registered,
                    "hotkeysFailed": HotKeyService.shared.failed.joined(separator: ","),
                    "islandWidth": Double(vm.islandSize.width),
                    "islandHeight": Double(vm.islandSize.height),
                    "visibleWidth": Double(vm.visibleIslandSize.width),
                    "visibleHeight": Double(vm.visibleIslandSize.height),
                    "pillScale": Double(vm.pillScale),
                    "pillWidth": AppSettings.shared.pillWidth,
                    "pillHeight": AppSettings.shared.pillHeight,
                    "pillMinWidth": Double(vm.pillMinWidth),
                    "accessibility": Permissions.accessibilityGranted,
                    "displayMode": AppSettings.shared.displayMode.rawValue,
                    "islands": screensCoordinator?.extraStates ?? [],
                    "lockScreen": LockScreenController.shared.state,
                    "showsTimerControls": vm.showsTimerControls,
                    "sharingType": islandController?.sharingTypeName ?? "none",
                    "suppression": islandController?.suppressionReason ?? "none",
                    "panelVisible": islandController?.testWindow.isVisible ?? false,
                    "nowPlayingBundle": NowPlayingService.shared.snapshot.bundleIdentifier ?? "",
                    "nowPlayingTitle": NowPlayingService.shared.snapshot.title,
                    "lastMediaKey": vm.lastMediaKey,
                    "unplugMinutes": vm.unplugMinutesLeft.map { String($0) } ?? "nil",
                    "keepAwake": KeepAwakeService.shared.isOn,
                    "menu": UITestDriver.shared.lastMenuResult,
                    "screen": islandController?.screenName ?? "none",
                    "testIDs": UITestRegistry.shared.frames.keys.sorted().joined(separator: ","),
                    "frames": UITestRegistry.shared.frames.mapValues { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" },
                    "timer": TimerService.shared.state.map { "\($0.mode.rawValue) \($0.displayTime(at: Date()))" } ?? "none",
                    "timerRunning": TimerService.shared.state?.isRunning ?? false,
                ]
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let file = base.appendingPathComponent("DynaNotch/Snapshots/state.json")
                if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: file)
                }
            case "snapshot-settings":
                // dynanotch://snapshot-settings/<page> → opens Settings on that page and renders it
                let page = SettingsPage(rawValue: argument) ?? .general
                openSettings()
                SettingsNavigator.shared.go(page)
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let file = base.appendingPathComponent("DynaNotch/Snapshots/settings-\(page.rawValue).png")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.settingsController?.snapshot(to: file)
                }
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
            case "snapshot-extra":
                // dynanotch://snapshot-extra/<name> → the first extra island (Show On → Every display)
                let name = argument.isEmpty ? "extra" : argument
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let file = base.appendingPathComponent("DynaNotch/Snapshots/\(name).png")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    _ = self?.screensCoordinator?.firstExtraController?.snapshot(to: file)
                }
            case "lockscreen":
                // dynanotch://lockscreen/lock|unlock → as if the screen locked / unlocked (never locks the Mac)
                if argument == "lock" || argument == "unlock" { UserPresence.shared.simulateLock(argument == "lock") }
            case "snapshot-lockscreen":
                // dynanotch://snapshot-lockscreen/<name> → the lock-screen strip as it would look now
                let name = argument.isEmpty ? "lockscreen" : argument
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let file = base.appendingPathComponent("DynaNotch/Snapshots/\(name).png")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    _ = LockScreenController.shared.snapshot(to: file)
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
