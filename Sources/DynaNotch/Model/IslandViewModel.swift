import AppKit
import SwiftUI
import Combine
import DynaNotchCore

enum DemoActivity: String, CaseIterable {
    case volume, brightness, charging, lowBattery, airpods, focus, calendar, peek
    case timer, lyrics, notification, download, camera, capsLock
}

extension Notification.Name {
    static let dynaNotchOpenSettings = Notification.Name("DynaNotch.openSettings")
    /// Posted by panel text fields when they gain focus: the window controller makes the panel key.
    static let dynaNotchWantsKey = Notification.Name("DynaNotch.wantsKey")
}

/// Wraps `IslandEngine`, owns all timers and republishes the island presentation (CLAUDE.md §6.2).
/// Everything here runs on the main thread.
final class IslandViewModel: ObservableObject {
    @Published private(set) var presentation: IslandPresentation = .idle
    @Published private(set) var notch: NotchMetrics = .fallback
    @Published private(set) var isHovering: Bool = false
    /// Tab shown in the expanded panel.
    @Published private(set) var selectedTab: PanelTab = .home
    /// A pinned panel stays open when the mouse leaves or the user clicks elsewhere.
    @Published private(set) var isPinned: Bool = false
    /// The device-battery card is open over the panel.
    @Published var showsBatteries: Bool = false

    let settings: AppSettings

    private var engine = IslandEngine()
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private var deadlineWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var lingerWorkItem: DispatchWorkItem?
    private var demoWorkItem: DispatchWorkItem?

    /// Now-playing bookkeeping.
    private var lastSnapshot: NowPlayingSnapshot = .empty
    private var pausedSince: Date?
    private var demoNowPlayingUntil: Date?
    private var demoLyricsUntil: Date?
    private var v3Wired = false

    /// Media keys whose key-down we handled, so the matching key-up is consumed as well.
    private var handledKeyCodes = Set<Int>()

    private static let peekDuration: TimeInterval = 2.8

    init(settings: AppSettings = .shared) {
        self.settings = settings
        if settings.rememberLastTab, let tab = PanelTab(rawValue: settings.lastTab) {
            selectedTab = tab
        }
    }

    // MARK: Derived geometry

    var islandSize: CGSize {
        IslandLayout.size(for: presentation, notch: notch, hudStyle: settings.hudStyle)
    }

    var radii: IslandRadii {
        IslandLayout.radii(for: presentation, hudStyle: settings.hudStyle)
    }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Non-notch displays in pill style: the island floats below the top edge.
    var isPill: Bool {
        !notch.hasPhysicalNotch && settings.nonNotchStyle == .pill
    }

    var topInset: CGFloat {
        isPill ? IslandLayout.pillTopInset : 0
    }

    /// The selected tab if it is enabled, else the first enabled tab.
    var visibleTab: PanelTab {
        let tabs = settings.enabledTabs
        return tabs.contains(selectedTab) ? selectedTab : (tabs.first ?? .home)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        let nowPlaying = NowPlayingService.shared
        nowPlaying.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.handleSnapshot(snapshot) }
            .store(in: &cancellables)
        nowPlaying.trackChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleTrackChanged() }
            .store(in: &cancellables)

        VolumeService.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                guard let self = self else { return }
                if self.settings.hudEnabled && self.settings.volumeHUD {
                    self.post(.hud(.volume, level: reading.level, muted: reading.muted))
                }
            }
            .store(in: &cancellables)

        BrightnessService.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                if self.settings.hudEnabled && self.settings.brightnessHUD {
                    self.post(.hud(.brightness, level: level, muted: false))
                }
            }
            .store(in: &cancellables)

        BatteryService.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handlePowerEvent(event) }
            .store(in: &cancellables)

        BluetoothService.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.post(.bluetooth(name: event.name, device: event.kind, battery: event.battery, connected: event.connected))
            }
            .store(in: &cancellables)

        FocusService.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.post(.focus(name: state.name, symbol: state.symbol, enabled: state.isActive))
            }
            .store(in: &cancellables)

        CalendarService.shared.dueSoon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                let seconds = item.start.timeIntervalSince(Date())
                let minutes = max(0, Int(ceil(seconds / 60)))
                self?.post(.calendar(title: item.title, minutesUntil: minutes))
            }
            .store(in: &cancellables)

        wireV3Services()

        // Settings may change presentation (now playing toggles, HUD style …). objectWillChange fires
        // before the new value is stored, so re-evaluate on the next run-loop turn.
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.settingsDidChange() }
            }
            .store(in: &cancellables)

        MediaKeyTap.shared.handler = { [weak self] event, flags in
            self?.handleMediaKey(event, flags) ?? false
        }

        nowPlaying.start()
        VolumeService.shared.start()
        BrightnessService.shared.start()
        MediaKeyTap.shared.start()
        BatteryService.shared.start()
        BluetoothService.shared.start()
        FocusService.shared.start()
        if settings.calendarEnabled {
            CalendarService.shared.start()
        }
        startV3Services()

        refresh()
    }

    private func settingsDidChange() {
        if settings.calendarEnabled {
            CalendarService.shared.start()   // idempotent
        }
        startV3Services()                    // idempotent; picks up features switched on
        TimerService.shared.applyConfig(settings.pomodoroConfig)
        evaluateTimer()
        evaluateNowPlaying()                 // refreshes
        objectWillChange.send()              // islandSize / radii may depend on hudStyle
    }

    // MARK: Intents

    func setNotch(_ metrics: NotchMetrics) {
        guard metrics != notch else { return }
        notch = metrics
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            if settings.expandOnHover && presentation != .hidden && !engine.isExpanded {
                expandWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isHovering else { return }
                    self.expand()
                }
                expandWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + settings.hoverDelay, execute: item)
            }
        } else {
            expandWorkItem?.cancel()
            expandWorkItem = nil
            if engine.isExpanded && !isPinned {
                collapseWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self, !self.isHovering, !self.isPinned else { return }
                    self.collapse()
                }
                collapseWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + settings.collapseDelay, execute: item)
            }
        }
    }

    func tap() {
        guard settings.clickToExpand else { return }
        if engine.isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func expand() {
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard !engine.isExpanded else { return }
        engine.isExpanded = true
        engine.cancelPeek()
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        refresh()
    }

    func collapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        guard engine.isExpanded else { return }
        engine.isExpanded = false
        isPinned = false
        showsBatteries = false
        refresh()
    }

    /// Outside clicks collapse the panel unless it is pinned.
    func collapseFromOutside() {
        guard !isPinned else { return }
        collapse()
    }

    func select(_ tab: PanelTab) {
        guard tab != selectedTab else { return }
        selectedTab = tab
        if settings.rememberLastTab {
            settings.lastTab = tab.rawValue
        }
    }

    /// Expands the panel on `tab`.
    func open(tab: PanelTab) {
        select(tab)
        expand()
    }

    func togglePin() {
        isPinned.toggle()
        if isPinned && !engine.isExpanded { expand() }
    }

    /// Files are being dragged near the island: open the shelf so they can be dropped.
    func beginFileDrag() {
        guard settings.shelfEnabled else { return }
        if !engine.isExpanded || selectedTab != .shelf {
            open(tab: .shelf)
        }
    }

    /// `dynanotch://notify` and other app-originated notifications.
    func notify(_ notification: NotchNotification) {
        guard settings.notifyActivity else { return }
        engine.post(.notification(title: notification.title, body: notification.body, symbol: notification.symbol),
                    now: Date(), duration: notification.duration)
        refresh()
    }

    /// Clipboard row tapped: collapse first so ⌘V lands in the frontmost app, then paste.
    func paste(_ item: ClipItem, plainText: Bool = false) {
        let pasteNow = settings.pasteOnClick && Permissions.accessibilityGranted
        if pasteNow {
            isPinned = false
            collapse()
        }
        ClipboardService.shared.paste(item, plainText: plainText)
    }

    func swipe(_ direction: SwipeDirection) {
        switch direction {
        case .left:
            NowPlayingService.shared.next()
        case .right:
            NowPlayingService.shared.previous()
        case .up:
            if engine.isExpanded {
                collapse()
            } else {
                engine.dismissCurrent(now: Date())
                refresh()
            }
        case .down:
            expand()
        }
    }

    func setSuppressed(_ suppressed: Bool) {
        guard engine.isSuppressed != suppressed else { return }
        engine.isSuppressed = suppressed
        refresh()
    }

    /// Posts a live activity if the corresponding setting allows it.
    func post(_ kind: ActivityKind) {
        guard isAllowed(kind) else { return }
        engine.post(kind, now: Date())
        refresh()
    }

    func openSettings() {
        NotificationCenter.default.post(name: .dynaNotchOpenSettings, object: nil)
    }

    /// Debug menu: shows sample activities regardless of the per-activity toggles.
    func simulate(_ demo: DemoActivity) {
        let now = Date()
        switch demo {
        case .volume:
            engine.post(.hud(.volume, level: 0.62, muted: false), now: now)
        case .brightness:
            engine.post(.hud(.brightness, level: 0.8, muted: false), now: now)
        case .charging:
            engine.post(.charging(level: 0.76, isCharging: true, pluggedIn: true), now: now)
        case .lowBattery:
            engine.post(.lowBattery(level: 0.1), now: now)
        case .airpods:
            engine.post(.bluetooth(name: "AirPods Pro", device: .airpodsPro, battery: 84, connected: true), now: now)
        case .focus:
            engine.post(.focus(name: "Do Not Disturb", symbol: "moon.fill", enabled: true), now: now)
        case .calendar:
            engine.post(.calendar(title: "Design review", minutesUntil: 5), now: now)
        case .peek:
            if engine.isExpanded {
                engine.isExpanded = false
            }
            if !engine.isNowPlayingActive {
                // No real track: pretend one is active for the peek duration.
                let until = now.addingTimeInterval(IslandViewModel.peekDuration)
                demoNowPlayingUntil = until
                engine.isNowPlayingActive = true
                demoWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.demoNowPlayingUntil = nil
                    self.evaluateNowPlaying()
                }
                demoWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + IslandViewModel.peekDuration + 0.05, execute: item)
            }
            engine.startPeek(now: now, duration: IslandViewModel.peekDuration)
        case .timer:
            if TimerService.shared.state == nil {
                TimerService.shared.startCountdown(minutes: 5, label: "Demo")
            }
            engine.isExpanded = false
            evaluateTimer()
        case .lyrics:
            engine.isExpanded = false
            demoLyricsUntil = now.addingTimeInterval(6)
            demoWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.demoLyricsUntil = nil
                self?.evaluateNowPlaying()
            }
            demoWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.05, execute: item)
            evaluateNowPlaying()
        case .notification:
            engine.post(.notification(title: "Build finished", body: "All 120 tests passed in 42 s", symbol: "hammer.fill"),
                        now: now)
        case .download:
            engine.post(.download(name: "DynaNotch.dmg", finished: true), now: now)
        case .camera:
            engine.post(.sensor(.camera, active: true), now: now)
        case .capsLock:
            engine.post(.toggle(symbol: "capslock.fill", label: "Caps Lock", on: true), now: now)
        }
        refresh()
    }

    // MARK: Gating

    private func isAllowed(_ kind: ActivityKind) -> Bool {
        switch kind {
        case .hud(let hud, _, _):
            guard settings.hudEnabled else { return false }
            switch hud {
            case .volume: return settings.volumeHUD
            case .brightness: return settings.brightnessHUD
            }
        case .charging:
            return settings.chargingActivity
        case .lowBattery:
            return settings.lowBatteryActivity
        case .bluetooth:
            return settings.bluetoothActivity
        case .focus:
            return settings.focusActivity
        case .calendar:
            return settings.calendarActivity && settings.calendarEnabled
        case .timerFinished:
            return true
        case .notification:
            return settings.notifyActivity
        case .download:
            return settings.downloadActivity
        case .sensor:
            return settings.privacyActivity
        case .toggle:
            return true   // callers check the specific toggle setting
        }
    }

    // MARK: Engine → presentation

    private func refresh() {
        let now = Date()
        engine.prune(now: now)
        engine.prefersTimerOverMusic = settings.timerOverNowPlaying
        let showCompact = settings.nowPlayingEnabled && settings.showCompactNowPlaying
        let next = engine.presentation(now: now, showNowPlayingCompact: showCompact)
        if next != presentation {
            let animation: Animation = reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.42, dampingFraction: 0.82)
            withAnimation(animation) {
                presentation = next
            }
        }
        scheduleDeadline(now: now)
    }

    private func scheduleDeadline(now: Date) {
        deadlineWorkItem?.cancel()
        deadlineWorkItem = nil
        guard let deadline = engine.nextDeadline(now: now) else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.deadlineWorkItem = nil
            self.engine.prune(now: Date())
            self.refresh()
        }
        deadlineWorkItem = item
        let delay = max(0, deadline.timeIntervalSince(now)) + 0.02
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: Now playing

    private func handleSnapshot(_ snapshot: NowPlayingSnapshot) {
        if snapshot.isEmpty {
            pausedSince = nil
        } else if snapshot.isPlaying {
            pausedSince = nil
        } else if pausedSince == nil && lastSnapshot.isPlaying && !lastSnapshot.isEmpty {
            pausedSince = Date()
        }
        lastSnapshot = snapshot
        evaluateNowPlaying()
    }

    private func handleTrackChanged() {
        // Make sure the active flag reflects the newest snapshot before peeking.
        evaluateNowPlaying()
        guard settings.showTrackPeek, !engine.isExpanded else { return }
        engine.startPeek(now: Date(), duration: IslandViewModel.peekDuration)
        refresh()
    }

    private func evaluateNowPlaying() {
        let now = Date()
        let snapshot = NowPlayingService.shared.snapshot
        lingerWorkItem?.cancel()
        lingerWorkItem = nil

        var active = false
        if settings.nowPlayingEnabled && !snapshot.isEmpty {
            if snapshot.isPlaying {
                active = true
            } else if let since = pausedSince {
                let lingerEnd = since.addingTimeInterval(max(0, settings.pausedLingerSeconds))
                if lingerEnd > now {
                    active = true
                    let item = DispatchWorkItem { [weak self] in
                        self?.lingerWorkItem = nil
                        self?.evaluateNowPlaying()
                    }
                    lingerWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + lingerEnd.timeIntervalSince(now) + 0.05, execute: item)
                }
            }
        }
        if let lyricsUntil = demoLyricsUntil, lyricsUntil > now {
            active = true
        }
        if let demoUntil = demoNowPlayingUntil {
            if demoUntil > now {
                active = true
            } else {
                demoNowPlayingUntil = nil
            }
        }

        engine.isNowPlayingActive = active

        let lyricsAvailable = !LyricsService.shared.lines.isEmpty && snapshot.isPlaying
        engine.hasLyricLine = settings.lyricsEnabled && settings.lyricsInCompact
            && (lyricsAvailable || (demoLyricsUntil.map { $0 > now } ?? false))
        refresh()
    }

    // MARK: v3 services

    private func wireV3Services() {
        guard !v3Wired else { return }
        v3Wired = true

        let timer = TimerService.shared
        timer.applyConfig(settings.pomodoroConfig)
        timer.$engine
            .map(\.isActive)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluateTimer() }
            .store(in: &cancellables)
        timer.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .countdownFinished(let label):
                    self?.post(.timerFinished(label: label.isEmpty ? "Timer" : label))
                case .phaseFinished(_, let to):
                    self?.post(.timerFinished(label: to == .work ? "Back to focus" : "\(to.title) time"))
                }
            }
            .store(in: &cancellables)

        LyricsService.shared.$lines
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.evaluateNowPlaying() } }
            .store(in: &cancellables)

        CapsLockMonitor.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                guard let self = self, self.settings.capsLockActivity else { return }
                self.post(.toggle(symbol: on ? "capslock.fill" : "capslock", label: "Caps Lock", on: on))
            }
            .store(in: &cancellables)

        PrivacyMonitor.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sensor, active in self?.post(.sensor(sensor, active: active)) }
            .store(in: &cancellables)

        DownloadsMonitor.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.post(.download(name: event.name, finished: event.finished)) }
            .store(in: &cancellables)

        KeepAwakeService.shared.$isOn
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in
                self?.post(.toggle(symbol: on ? "cup.and.saucer.fill" : "cup.and.saucer", label: "Keep Awake", on: on))
            }
            .store(in: &cancellables)

        AudioDeviceService.shared.$isMicMuted
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.post(.toggle(symbol: muted ? "mic.slash.fill" : "mic.fill", label: "Microphone", on: !muted))
            }
            .store(in: &cancellables)

        let hotkeys = HotKeyService.shared
        hotkeys.onTogglePanel = { [weak self] in
            guard let self = self else { return }
            if self.engine.isExpanded {
                self.collapse()
            } else {
                self.expand()
                NotificationCenter.default.post(name: .dynaNotchWantsKey, object: nil)
            }
        }
        hotkeys.onClipboard = { [weak self] in
            guard let self = self, self.settings.clipboardEnabled else { return }
            self.open(tab: .clipboard)
            NotificationCenter.default.post(name: .dynaNotchWantsKey, object: nil)
        }
    }

    /// Starts every v3 service whose feature is on (all `start()`s are idempotent).
    private func startV3Services() {
        LyricsService.shared.start()
        AudioDeviceService.shared.start()
        CapsLockMonitor.shared.start()
        PrivacyMonitor.shared.start()
        DownloadsMonitor.shared.start()
        HotKeyService.shared.start()
        DeviceBatteryService.shared.start()
        if settings.clipboardEnabled {
            ClipboardService.shared.start()
        } else {
            ClipboardService.shared.stop()
        }
        if settings.weatherEnabled {
            WeatherService.shared.start()
        }
        if settings.aiUsageEnabled {
            AIUsageService.shared.start()
        }
    }

    private func evaluateTimer() {
        let active = TimerService.shared.state != nil && settings.showCompactTimer
        guard engine.isTimerActive != active else { return }
        engine.isTimerActive = active
        refresh()
    }

    // MARK: Power

    private func handlePowerEvent(_ event: PowerEvent) {
        switch event {
        case .pluggedIn(let info):
            post(.charging(level: info.level, isCharging: info.isCharging, pluggedIn: true))
        case .unplugged(let info):
            post(.charging(level: info.level, isCharging: false, pluggedIn: false))
        case .lowBattery(let info, _):
            post(.lowBattery(level: info.level))
        }
    }

    // MARK: Media keys (called from the event tap; return true = consume)

    private func handleMediaKey(_ event: MediaKeyEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard settings.hudEnabled && settings.replaceSystemHUD else {
            handledKeyCodes.removeAll()
            return false
        }
        guard let key = event.key else { return false }

        switch key {
        case .soundUp, .soundDown, .mute, .brightnessUp, .brightnessDown:
            break
        default:
            return false   // play / next / previous etc. go to the system
        }

        if !event.isDown {
            // Consume the key-up only if we consumed the key-down.
            if handledKeyCodes.contains(event.rawKeyCode) {
                handledKeyCodes.remove(event.rawKeyCode)
                return true
            }
            return false
        }

        let fine = flags.contains(.option) && flags.contains(.shift)
        let handled: Bool
        switch key {
        case .soundUp, .soundDown, .mute:
            handled = handleVolumeKey(key, fine: fine)
        case .brightnessUp, .brightnessDown:
            handled = handleBrightnessKey(key, fine: fine)
        default:
            handled = false
        }

        if handled {
            handledKeyCodes.insert(event.rawKeyCode)
        } else {
            handledKeyCodes.remove(event.rawKeyCode)
        }
        return handled
    }

    private func handleVolumeKey(_ key: MediaKey, fine: Bool) -> Bool {
        let volume = VolumeService.shared
        guard let reading = volume.read() else { return false }

        var result = reading
        if key == .mute {
            let muted = !reading.muted
            guard volume.setMuted(muted) else { return false }
            result = LevelReading(level: reading.level, muted: muted)
        } else {
            let newLevel = LevelStepper.step(reading.level, up: key == .soundUp, fine: fine)
            guard volume.setLevel(newLevel) else { return false }
            result = volume.read() ?? LevelReading(level: newLevel, muted: newLevel <= 0 ? reading.muted : false)
        }

        if settings.volumeHUD {
            post(.hud(.volume, level: result.level, muted: result.muted))
        }
        return true
    }

    private func handleBrightnessKey(_ key: MediaKey, fine: Bool) -> Bool {
        let brightness = BrightnessService.shared
        guard brightness.isAvailable, let level = brightness.read() else { return false }
        let newLevel = LevelStepper.step(level, up: key == .brightnessUp, fine: fine)
        guard brightness.setLevel(newLevel) else { return false }
        if settings.brightnessHUD {
            post(.hud(.brightness, level: newLevel, muted: false))
        }
        return true
    }
}
