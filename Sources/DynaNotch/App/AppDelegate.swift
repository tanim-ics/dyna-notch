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
        URLHookGate.prepare()   // private data folder (docs/SECURITY.md)
        Vault.migrateExistingFiles()   // encrypt data written by older builds
        // Scripts and tests drive every hook through the private control socket (this user only).
        LocalControlServer.shared.handler = { [weak self] url in self?.handle(url) }
        LocalControlServer.shared.start()
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

        // Updates (CONTRACTS §6.21): once a day ask GitHub; after an update, play its What's New story once.
        UpdateService.shared.start()
        WhatsNewController.shared.showIfUpdated(delay: 1.5)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        LocalControlServer.shared.stop()
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
        // Links from outside (web pages, mail, documents, other apps) only reach the public hooks; scripts on this
        // Mac use LocalControlServer for the rest (docs/SECURITY.md).
        for url in urls where url.scheme?.lowercased() == "dynanotch" && URLHookGate.allowsPublic(url) {
            handle(url)
        }
    }

    /// Runs one hook. Callers have already decided it is allowed (public link, or the control socket).
    private func handle(_ url: URL) {
        do {
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
            case "whatsnew":
                WhatsNewController.shared.showCurrent()
            case "story":
                // dynanotch://story/<next|previous|confirm|close|pause|resume>
                switch argument {
                case "next": WhatsNewController.shared.handle(.next)
                case "previous": WhatsNewController.shared.handle(.previous)
                case "confirm": WhatsNewController.shared.handle(.confirm)
                case "close": WhatsNewController.shared.handle(.close)
                case "pause": WhatsNewController.shared.model?.setPaused(true)
                case "resume": WhatsNewController.shared.model?.setPaused(false)
                default: break
                }
            case "update":
                // dynanotch://update/<check|show|install>, update/feed?url= (test feed, memory only; no url = GitHub)
                switch argument {
                case "check": UpdateService.shared.checkNow()
                case "show": WhatsNewController.shared.showUpdate()
                case "install": UpdateService.shared.install()
                case "feed":
                    let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first { $0.name == "url" }?.value
                    UpdateService.shared.feedOverride = value.flatMap(URL.init(string:))
                default: break
                }
            case "snapshot-whatsnew":
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                WhatsNewController.shared.snapshot(
                    to: base.appendingPathComponent("DynaNotch/Snapshots/\(SafeFileName.sanitize(argument, fallback: "whatsnew")).png"))
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
                    to: base.appendingPathComponent("DynaNotch/Snapshots/\(SafeFileName.sanitize(argument, fallback: "palette")).png"))
            case "snapshot-welcome":
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                WelcomeController.shared.snapshot(
                    to: base.appendingPathComponent("DynaNotch/Snapshots/\(SafeFileName.sanitize(argument, fallback: "welcome")).png"))
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
                    case "whatsnew": window = WhatsNewController.shared.testWindow
                    default: window = islandController?.testWindow
                    }
                    var point: NSPoint?
                    if let x = x, let y = y { point = NSPoint(x: x, y: y) }
                    if let id = query["id"], let frame = UITestRegistry.shared.frames[id] {
                        point = NSPoint(x: frame.midX, y: frame.midY)
                    }
                    if let window = window, let point = point {
                        UITestDriver.shared.click(in: window, at: point, modifiers: query["alt"] == "1" ? .option : [],
                                                  direct: window === islandController?.testWindow)
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
                    "displayKeys": ConnectedDisplay.current().map(\.key),
                    "holdsPopup": vm.holdsPopup,
                    "vault": Vault.status,
                    "clipboardSecrets": ClipboardService.shared.lastSecret,
                    "clipboardCount": ClipboardService.shared.history.items.count,
                    "canvasWidth": Double(vm.canvasSize.width),
                    "lockScreen": LockScreenController.shared.state,
                    "copy": FileCopyMonitor.shared.state,
                    "smartCopy": SmartCopyService.shared.state,
                    "agent": AgentIslandService.shared.state,
                    "alchemy": AlchemyService.shared.state,
                    "vitals": MacVitalsService.shared.state,
                    "wrap": DailyWrapService.shared.state,
                    "update": UpdateService.shared.state.merging([
                        "lastSeen": UserDefaults.standard.string(forKey: WhatsNewController.lastSeenKey) ?? "",
                        "story": WhatsNewController.shared.state,
                    ]) { a, _ in a },
                    "voice": VoiceNoteService.shared.state,
                    "focus": FocusGuardService.shared.state.merging([
                        "soundscape": AppSettings.shared.soundscape,
                        "playing": SoundscapeService.shared.playing.rawValue,
                        "shakes": vm.shakeCount,
                    ]) { a, _ in a },
                    "privacy": [
                        "inUse": PrivacyMonitor.shared.inUse.map(\.rawValue).sorted(),
                        "micApps": PrivacyMonitor.microphoneApps(),
                        "log": PrivacyMonitor.shared.log.sessions.prefix(3).map { "\($0.sensor) \($0.app) \($0.end == nil ? "open" : "closed")" },
                        "call": MeetingMeter.shared.state,
                    ] as [String: Any],
                    "lastTap": vm.lastTap,
                    "lastClick": UITestDriver.shared.lastClick,
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
                let name = SafeFileName.sanitize(argument, fallback: "panel")
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let file = base.appendingPathComponent("DynaNotch/Snapshots/\(name).png")
                // Let pending animations settle first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.islandController?.snapshot(to: file)
                }
            case "snapshot-extra":
                // dynanotch://snapshot-extra/<name> → the first extra island (Show On → Every display)
                let name = SafeFileName.sanitize(argument, fallback: "extra")
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory())
                let file = base.appendingPathComponent("DynaNotch/Snapshots/\(name).png")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    _ = self?.screensCoordinator?.firstExtraController?.snapshot(to: file)
                }
            case "copy":
                // dynanotch://copy?name=Photos&fraction=0.42&left=90 · copy?done=1 → the copy progress pill
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
                let name = value("name") ?? "Test.mov"
                if value("done") != nil {
                    FileCopyMonitor.shared.simulate(name: name, fraction: 1, secondsLeft: nil)
                } else {
                    FileCopyMonitor.shared.simulate(name: name, fraction: Double(value("fraction") ?? "") ?? 0.5,
                                                    secondsLeft: value("left").flatMap { Int($0) })
                }
            case "agent":
                // dynanotch://agent/answer?id=…&decision=allow|deny|terminal
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if argument == "install-test", let path = items.first(where: { $0.name == "settings" })?.value,
                   SafeFileName.isInside(path, directory: NSTemporaryDirectory())
                    || SafeFileName.isInside(path, directory: "/private/tmp") {
                    // Installer test against a copy (never the real ~/.claude/settings.json): install, check, remove.
                    ShellHookInstaller.claudeSettingsOverride = URL(fileURLWithPath: path)
                    let ok = ShellHookInstaller.installAgentHooks(timeout: Int(AppSettings.shared.agentTimeout))
                    let installed = ShellHookInstaller.agentHooksInstalled
                    try? FileManager.default.copyItem(atPath: path, toPath: path + ".installed")
                    ShellHookInstaller.removeAgentHooks()
                    let removed = !ShellHookInstaller.agentHooksInstalled
                    ShellHookInstaller.claudeSettingsOverride = nil
                    AgentIslandService.shared.installTest = "ok=\(ok) installed=\(installed) removed=\(removed)"
                }
                if argument == "answer", let id = items.first(where: { $0.name == "id" })?.value,
                   let decision = items.first(where: { $0.name == "decision" })?.value.flatMap(AgentDecision.init(rawValue:)) {
                    let project = AgentIslandService.shared.requests.first { $0.id == id }?.project ?? "Claude"
                    viewModel?.answerAgent(id: id, project: project, decision)
                }
            case "voice":
                // dynanotch://voice?text=remind%20me%20to%20… → what that sentence would do (no listening)
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let text = items.first(where: { $0.name == "text" })?.value { VoiceNoteService.shared.handle(text) }
            case "wrap":
                // dynanotch://wrap → today's Daily Wrap now
                DailyWrapService.shared.showNow()
            case "vitals":
                // dynanotch://vitals/thermal|memory|disk|runaway → that alert now
                MacVitalsService.shared.simulate(argument)
            case "focusguard":
                // dynanotch://focusguard?app=com.tinyspeck.slackmacgap → as if that app came to the front
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let app = items.first(where: { $0.name == "app" })?.value {
                    FocusGuardService.shared.activated(bundleID: app, name: items.first(where: { $0.name == "name" })?.value ?? "")
                }
            case "soundscape":
                // dynanotch://soundscape/rain · soundscape/stop
                if let sound = Soundscape(rawValue: argument), sound != .none {
                    SoundscapeService.shared.play(sound)
                } else {
                    SoundscapeService.shared.stop()
                }
            case "sensor":
                // dynanotch://sensor?kind=microphone&active=1&app=Zoom → as if that sensor turned on / off
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
                if argument == "forget", let app = value("app") {
                    PrivacyMonitor.shared.forget(app: app)   // test cleanup: drop one app's log entries
                } else if let kind = value("kind").flatMap(SensorKind.init(rawValue:)) {
                    PrivacyMonitor.shared.simulate(kind, active: value("active") == "1", app: value("app") ?? "")
                }
            case "shelf":
                // dynanotch://shelf/remove?path=… — takes a file off the shelf (test cleanup; the file stays)
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if argument == "remove", let path = items.first(where: { $0.name == "path" })?.value {
                    ShelfService.shared.items.filter { $0.path == path }.forEach { ShelfService.shared.remove($0) }
                }
            case "alchemy":
                // dynanotch://alchemy?action=cutout&path=/path/to/file — same as dropping it on that zone
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let raw = items.first(where: { $0.name == "action" })?.value, let action = AlchemyAction(rawValue: raw),
                   let path = items.first(where: { $0.name == "path" })?.value {
                    AlchemyService.shared.run(action, on: URL(fileURLWithPath: path))
                }
            case "convert":
                // dynanotch://convert?text=%E2%82%AC42 → Smart Copy as if that text was copied (clipboard untouched)
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if let text = items.first(where: { $0.name == "text" })?.value { SmartCopyService.shared.handle(text) }
            case "lockscreen":
                // dynanotch://lockscreen/lock|unlock → as if the screen locked / unlocked (never locks the Mac)
                if argument == "lock" || argument == "unlock" { UserPresence.shared.simulateLock(argument == "lock") }
            case "snapshot-lockscreen":
                // dynanotch://snapshot-lockscreen/<name> → the lock-screen strip as it would look now
                let name = SafeFileName.sanitize(argument, fallback: "lockscreen")
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
                } else if let minutes = URLHookPolicy.timerMinutes(argument) {
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
