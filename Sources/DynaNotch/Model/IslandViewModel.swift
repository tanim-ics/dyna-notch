import AppKit
import SwiftUI
import Combine
import DynaNotchCore

/// Dropdown cards under the panel header.
enum HeaderCard: String, Equatable {
    case battery, sound
}

enum DemoActivity: String, CaseIterable {
    case volume, brightness, charging, lowBattery, airpods, focus, calendar, peek
    case timer, lyrics, notification, download, camera, capsLock, unplug
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
    /// Card open under the header (battery devices or sound), from a click or from hovering its button.
    @Published var headerCard: HeaderCard?

    /// Kept for older callers: the battery card.
    var showsBatteries: Bool {
        get { headerCard == .battery }
        set { headerCard = newValue ? .battery : (headerCard == .battery ? nil : headerCard) }
    }

    private var headerCardByHover = false
    private var headerHoverRegion: String?
    private var headerHoverWork: DispatchWorkItem?
    /// Settings → Timer → Controls on hover: the compact timer grew a row of pause / +1 min / stop buttons.
    @Published private(set) var showsTimerControls: Bool = false

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
    private var explicitTabRequest = false
    /// When the user last chose a tab; "Open on current activity" doesn't override a recent choice.
    private var userPickedTabAt: Date?
    /// Metrics of the target screen as measured; `notch` is what the island lays out with.
    private var screenNotch = NotchMetrics.fallback
    private var idleWorkItem: DispatchWorkItem?
    private var v3Wired = false
    /// Settings → Now Playing → Peek on hover: the track peek is shown because the pointer is over the island.
    private var hoverPeekActive = false
    /// The pointer has been over the open panel since it expanded. A panel opened from the keyboard / an action
    /// only auto-collapses after the pointer has entered and then left it.
    private var hoveredSinceExpand = false
    private lazy var lastAutoCollapse: Bool = settings.autoCollapse
    /// `simulate(.unplug)`: sample "time left" for the unplug island.
    private var demoUnplugMinutes: Int?
    /// Scripted tests (`dynanotch://ui/override?focus=1`): pretend a Focus mode is on / off.
    var testFocusActive: Bool?
    /// Scripted tests: outcome of the last media key handled through `handleMediaKey` ("play consumed" …).
    private(set) var lastMediaKeyResult = ""

    /// Media keys whose key-down we handled, so the matching key-up is consumed as well.
    private var handledKeyCodes = Set<Int>()

    private static let peekDuration: TimeInterval = 2.8

    /// Show On → Every display: extra islands (`isPrimary == false`) mirror the activities but leave sounds, the edge
    /// glow, media keys and shortcuts to the primary island so nothing happens twice.
    let isPrimary: Bool

    init(settings: AppSettings = .shared, isPrimary: Bool = true) {
        self.settings = settings
        self.isPrimary = isPrimary
        if settings.rememberLastTab, let tab = PanelTab(rawValue: settings.lastTab) {
            selectedTab = tab
        }
    }

    // MARK: Derived geometry

    /// Layout size of the island (before the closed-pill scale).
    var islandSize: CGSize {
        if showsTimerControls && presentation == .timer {
            return IslandLayout.timerControlsSize(notch: notch)
        }
        if presentation == .expanded {
            return expandedSize
        }
        return IslandLayout.size(for: presentation, notch: notch, hudStyle: settings.hudStyle)
    }

    /// Settings → Appearance → Panel: width, Fixed / Fit Content (per tab) and maximum height.
    var expandedSize: CGSize {
        let content = IslandLayout.expandedContentHeight(tab: visibleTab, sizing: settings.panelSizing,
                                                         maxHeight: CGFloat(settings.panelMaxHeight))
        return IslandLayout.expandedSize(notch: notch, width: CGFloat(settings.panelWidth), contentHeight: content)
    }

    /// Fixed canvas of the island window; grows only when the panel settings need more room.
    var canvasSize: CGSize {
        let expandedInset: CGFloat
        if floatsBelowNotch {
            expandedInset = screenNotch.height + IslandLayout.pillTopInset
        } else if isPill {
            expandedInset = IslandLayout.pillTopInset
        } else {
            expandedInset = 0
        }
        return IslandLayout.canvasSize(panelWidth: CGFloat(settings.panelWidth),
                                       panelMaxHeight: CGFloat(settings.panelMaxHeight),
                                       notchHeight: notch.height + expandedInset)
    }

    var radii: IslandRadii {
        if showsTimerControls && presentation == .timer {
            return IslandLayout.timerControlsRadii
        }
        return IslandLayout.radii(for: presentation, hudStyle: settings.hudStyle)
    }

    /// Settings → Appearance → Closed Pill Size: scales the closed pill (never the open panel).
    var pillScale: CGFloat {
        guard isPill, presentation != .expanded else { return 1 }
        return min(max(CGFloat(settings.pillScale), IslandLayout.pillScaleRange.lowerBound),
                   IslandLayout.pillScaleRange.upperBound)
    }

    /// Size as drawn on screen (closed pill scale applied); the window controller hit-tests with it.
    var visibleIslandSize: CGSize {
        let scale = pillScale
        return scale == 1 ? islandSize : IslandLayout.scaled(islandSize, by: scale)
    }

    /// Battery time left for the unplug island (nil while macOS is still estimating).
    var unplugMinutesLeft: Int? {
        demoUnplugMinutes ?? BatteryService.shared.info?.minutesToEmpty
    }

    var lastMediaKey: String { lastMediaKeyResult }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Island spring from Settings → Appearance (Calm / Snappy / Bouncy × speed); a short fade with Reduce Motion.
    var motion: Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        let style = settings.animationStyle
        return .spring(response: style.response(speed: settings.animationSpeed), dampingFraction: style.spring.damping)
    }

    /// Pill style: on non-notch displays it floats below the top edge; on notch displays
    /// (Settings → Appearance → Notch displays: Floating pill) it floats just below the camera notch.
    var isPill: Bool {
        floatsBelowNotch || (!notch.hasPhysicalNotch && settings.nonNotchStyle == .pill)
    }

    var topInset: CGFloat {
        guard isPill else { return 0 }
        // Settings → Appearance → Pill Height Adjustment moves the closed pill only.
        let offset = presentation == .expanded ? 0 : CGFloat(settings.pillHeightOffset)
        let base = floatsBelowNotch ? screenNotch.height + IslandLayout.pillTopInset : IslandLayout.pillTopInset
        return max(0, base + offset)
    }

    /// True when the target screen has a hardware notch, whatever shape the island uses.
    var isOnNotchDisplay: Bool { screenNotch.hasPhysicalNotch }

    private var floatsBelowNotch: Bool {
        screenNotch.hasPhysicalNotch && settings.notchDisplayStyle == .pill
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

        if isPrimary {
            MediaKeyTap.shared.handler = { [weak self] event, flags in
                self?.handleMediaKey(event, flags) ?? false
            }
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

    /// Re-applies settings synchronously (the window controller calls it for shape changes).
    func applySettingsNow() {
        settingsDidChange()
    }

    private func settingsDidChange() {
        applyNotchShape()
        if !settings.peekOnHover { endHoverPeek() }
        if !settings.timerHoverControls { setTimerControls(false) }
        // Auto Collapse switched back on (only that change, not any setting such as lastTab) while the pointer is
        // away from a panel it has already visited.
        let autoCollapseTurnedOn = settings.autoCollapse && !lastAutoCollapse
        lastAutoCollapse = settings.autoCollapse
        if autoCollapseTurnedOn && engine.isExpanded && hoveredSinceExpand && !isHovering && !isPinned
            && collapseWorkItem == nil {
            scheduleHoverCollapse()
        }
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
        screenNotch = metrics
        applyNotchShape()
    }

    /// Settings → Appearance → Pill Width can't go below this: the MacBook's camera notch (185 pt without one).
    var pillMinWidth: CGFloat { ScreenLocator.physicalNotchWidth() }

    /// A pill lays out like a non-notch island (no gap for the camera housing), sized by Pill Width / Pill Height.
    private func applyNotchShape() {
        let usesPill = floatsBelowNotch || (!screenNotch.hasPhysicalNotch && settings.nonNotchStyle == .pill)
        let effective = usesPill
            ? IslandLayout.pillMetrics(width: CGFloat(settings.pillWidth), height: CGFloat(settings.pillHeight),
                                       notchWidth: pillMinWidth, scale: CGFloat(settings.pillScale))
            : screenNotch
        guard effective != notch else { return }
        notch = effective
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            hoveredSinceExpand = true
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            guard presentation != .hidden && !engine.isExpanded else { return }
            // Timer controls on hover replace auto-expanding; a click on the island opens the panel.
            if settings.timerHoverControls && presentation == .timer {
                setTimerControls(true)
                return
            }
            var delay = settings.hoverDelay
            if settings.peekOnHover && (presentation == .nowPlaying || presentation == .lyrics) {
                beginHoverPeek()
                // Long enough to read the title before the panel opens.
                delay = max(delay, 0.6)
            }
            if settings.expandOnHover {
                expandWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isHovering else { return }
                    self.expand()
                }
                expandWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            }
        } else {
            expandWorkItem?.cancel()
            expandWorkItem = nil
            endHoverPeek()
            setTimerControls(false)
            // Settings → Behavior → Auto Collapse off: only Esc, outside clicks and the idle timeout close it.
            if engine.isExpanded && !isPinned && settings.autoCollapse && hoveredSinceExpand {
                scheduleHoverCollapse()
            }
        }
    }

    private func scheduleHoverCollapse() {
        collapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.collapseWorkItem = nil
            guard !self.isHovering, !self.isPinned, self.settings.autoCollapse else { return }
            self.collapse()
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.collapseDelay, execute: item)
    }

    private func beginHoverPeek() {
        hoverPeekActive = true
        engine.startPeek(now: Date(), duration: 3600)
        refresh()
    }

    private func endHoverPeek() {
        guard hoverPeekActive else { return }
        hoverPeekActive = false
        engine.cancelPeek()
        refresh()
    }

    private func setTimerControls(_ show: Bool) {
        guard show != showsTimerControls else { return }
        withAnimation(motion) {
            showsTimerControls = show
        }
    }

    func tap() {
        if showsTimerControls && presentation == .timer {
            expand()
            return
        }
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
        // Opening the panel on purpose (shortcut, menu, URL) brings a hidden island back.
        if isUserHidden { showAgain() }
        guard !engine.isExpanded else { return }
        if !explicitTabRequest {
            selectOpeningTab()
        }
        explicitTabRequest = false
        engine.isExpanded = true
        hoveredSinceExpand = isHovering
        scheduleIdleCollapse()
        engine.cancelPeek()
        hoverPeekActive = false
        showsTimerControls = false
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
        headerCard = nil
        headerCardByHover = false
        headerHoverWork?.cancel()
        idleWorkItem?.cancel()
        idleWorkItem = nil
        refresh()
    }

    /// Outside clicks collapse the panel unless it is pinned.
    func collapseFromOutside() {
        guard !isPinned else { return }
        collapse()
    }

    func select(_ tab: PanelTab) {
        userPickedTabAt = Date()
        guard tab != selectedTab else { return }
        selectedTab = tab
        if settings.rememberLastTab {
            settings.lastTab = tab.rawValue
        }
    }

    /// Expands the panel on `tab`.
    func open(tab: PanelTab) {
        select(tab)
        explicitTabRequest = true
        expand()
        explicitTabRequest = false
    }

    /// Settings → Behavior: "Open on current activity" (music / timer running) wins over "Default tab".
    private func selectOpeningTab() {
        let enabled = settings.enabledTabs
        let pickedRecently = userPickedTabAt.map { Date().timeIntervalSince($0) < 600 } ?? false
        if settings.defaultTab == "previous" && pickedRecently { return }
        if settings.openOnCurrentActivity {
            switch presentation {
            case .timer where enabled.contains(.timer):
                selectAutomatically(.timer)
                return
            case .nowPlaying, .lyrics, .peek:
                if enabled.contains(.nowPlaying) {
                    selectAutomatically(.nowPlaying)
                    return
                }
            default:
                break
            }
        }
        if settings.defaultTab != "previous", let tab = PanelTab(rawValue: settings.defaultTab), enabled.contains(tab) {
            selectAutomatically(tab)
        }
    }

    private func selectAutomatically(_ tab: PanelTab) {
        let picked = userPickedTabAt
        select(tab)
        userPickedTabAt = picked
    }

    /// Pointer activity inside the open panel restarts the idle timeout.
    func noteInteraction() {
        guard engine.isExpanded, settings.idleTimeout > 0 else { return }
        scheduleIdleCollapse()
    }

    private func scheduleIdleCollapse() {
        idleWorkItem?.cancel()
        idleWorkItem = nil
        guard settings.idleTimeout > 0 else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isPinned else { return }
            self.collapse()
        }
        idleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.idleTimeout, execute: item)
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
        let kind = ActivityKind.notification(title: notification.title, body: notification.body, symbol: notification.symbol)
        guard settings.notifyActivity, !isQuieted(kind) else { return }
        engine.post(kind, now: Date(), duration: notification.duration ?? settings.notificationDuration)
        didPost(kind, category: .notifications)
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
        guard isAllowed(kind), !isQuieted(kind) else { return }
        engine.post(kind, now: Date())
        didPost(kind)
        refresh()
    }

    /// Side effects of a posted activity: its alert sound (Settings → Popups → Sounds) and, for battery / timer
    /// alerts, the screen-edge glow (Settings → Popups → Edge Glow).
    private func didPost(_ kind: ActivityKind, category: AlertCategory? = nil) {
        guard isPrimary else { return }
        if let category = category ?? IslandViewModel.alertCategory(for: kind) {
            // Settings → Timer → Sound off silences timer alerts whatever Sounds → Timers says.
            if !(category == .timers && !settings.timerSound) {
                AlertSoundPlayer.play(category)
            }
        }
        switch kind {
        case .lowBattery:
            EdgeGlowController.shared.flash(.systemRed)
        case .timerFinished:
            EdgeGlowController.shared.flash(.systemOrange)
        default:
            break
        }
    }

    /// Which alert-sound category an activity belongs to (nil = silent: HUDs, toggles, Focus, camera/mic).
    static func alertCategory(for kind: ActivityKind) -> AlertCategory? {
        switch kind {
        case .timerFinished: return .timers
        case .calendar: return .calendar
        case .charging, .lowBattery: return .battery
        case .bluetooth: return .devices
        case .download: return .downloads
        case .notification: return .notifications
        case .hud, .focus, .sensor, .toggle: return nil
        }
    }

    // MARK: Header cards (battery / sound)

    private var cardAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.86) }

    /// Header button clicked: toggles its card; a clicked card stays open until clicked again or elsewhere.
    func toggleHeaderCard(_ card: HeaderCard) {
        headerHoverWork?.cancel()
        headerCardByHover = false
        withAnimation(cardAnimation) { headerCard = headerCard == card ? nil : card }
    }

    func closeHeaderCard() {
        headerHoverWork?.cancel()
        withAnimation(cardAnimation) { headerCard = nil }
    }

    /// Window controller, on every pointer move: the hover region under the pointer ("hover.battery",
    /// "hover.sound", "hover.card" or nil). Resting on a button opens its card; leaving button and card closes a
    /// card that hover opened.
    func setHeaderHover(_ region: String?) {
        guard presentation == .expanded else {
            headerHoverRegion = nil
            return
        }
        guard region != headerHoverRegion else { return }
        headerHoverRegion = region
        headerHoverWork?.cancel()
        headerHoverWork = nil

        let hovered: HeaderCard?
        switch region {
        case "hover.battery": hovered = .battery
        case "hover.sound": hovered = .sound
        default: hovered = nil
        }

        if let card = hovered {
            guard headerCard != card else { return }
            schedule(after: 0.18) { [weak self] in
                guard let self = self else { return }
                self.headerCardByHover = true
                withAnimation(self.cardAnimation) { self.headerCard = card }
            }
        } else if region == "hover.card" {
            return   // inside the open card: keep it
        } else if headerCard != nil && headerCardByHover {
            schedule(after: 0.35) { [weak self] in
                guard let self = self, self.headerCardByHover else { return }
                withAnimation(self.cardAnimation) { self.headerCard = nil }
            }
        }
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        headerHoverWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
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
            didPost(.lowBattery(level: 0.1))
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
            DesktopLyricsController.shared.showDemo(until: now.addingTimeInterval(6))
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
        case .unplug:
            demoUnplugMinutes = 245
            let kind = ActivityKind.charging(level: 0.82, isCharging: false, pluggedIn: false)
            engine.post(kind, now: now)
            DispatchQueue.main.asyncAfter(deadline: .now() + kind.defaultDuration + 0.5) { [weak self] in
                self?.demoUnplugMinutes = nil
            }
        }
        refresh()
    }

    // MARK: Gating

    /// Settings → Popups → Quiet During Focus.
    private var isFocusActive: Bool {
        testFocusActive ?? FocusService.shared.state.isActive
    }

    private func isQuieted(_ kind: ActivityKind) -> Bool {
        settings.quietDuringFocus && kind.isQuietedDuringFocus && isFocusActive
    }

    private func isAllowed(_ kind: ActivityKind) -> Bool {
        switch kind {
        case .hud(let hud, _, _):
            guard settings.hudEnabled else { return false }
            switch hud {
            case .volume: return settings.volumeHUD
            case .brightness: return settings.brightnessHUD
            }
        case .charging(_, _, let pluggedIn):
            // Plug-in follows Charging; the unplug island has its own toggle (Battery → Unplug).
            return pluggedIn ? settings.chargingActivity : settings.unplugActivity
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
        var next = engine.presentation(now: now, showNowPlayingCompact: showCompact)
        // Settings → Now Playing → Show track info: Always keeps the title row under the notch while music plays.
        if next == .nowPlaying && settings.trackInfoMode == .always {
            next = .peek
        }
        // Hide DynaNotch: everything (live activities too) stays hidden once the "hidden" notice has been shown.
        if isUserHidden && (hideAt.map { now >= $0 } ?? true) {
            next = .hidden
        }
        if next != .timer && showsTimerControls {
            showsTimerControls = false
        } else if next == .timer && isHovering && settings.timerHoverControls && !showsTimerControls {
            showsTimerControls = true
        }
        if next != presentation {
            withAnimation(motion) {
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
        guard settings.showTrackPeek, settings.trackInfoMode == .onChange, !engine.isExpanded else { return }
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
            .sink { [weak self] sensor, active in
                // Our own Mirror tab turns the camera on; don't warn about it.
                if sensor == .camera && CameraService.shared.isOwnUse { return }
                self?.post(.sensor(sensor, active: active))
            }
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

        BreakReminderService.shared.reminders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] kind in
                self?.postNotification(title: kind.title, body: kind.message, symbol: kind.symbol, category: .timers)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .dynaNotchAppNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let info = note.userInfo, let title = info["title"] as? String else { return }
                // Services may name their alert-sound category (aiUsage, battery, downloads …).
                let category = (info["category"] as? String).flatMap { AlertCategory(rawValue: $0) } ?? .notifications
                self?.postNotification(title: title, body: info["body"] as? String ?? "",
                                       symbol: info["symbol"] as? String ?? "bell.fill", category: category)
            }
            .store(in: &cancellables)

        BatteryService.shared.fullyCharged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.settings.fullChargeActivity else { return }
                self.postNotification(title: "Fully Charged", body: "100 %", symbol: "battery.100percent.bolt",
                                      category: .battery)
                if self.isPrimary { EdgeGlowController.shared.flash(.systemGreen) }
            }
            .store(in: &cancellables)

        DriveMonitor.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self, self.settings.driveActivity else { return }
                self.postNotification(title: event.name, body: event.mounted ? "Drive connected" : "Drive ejected",
                                      symbol: event.mounted ? "externaldrive.fill" : "eject.fill", category: .downloads)
            }
            .store(in: &cancellables)

        DeviceBatteryService.shared.alerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alert in
                guard let self = self, self.settings.accessoryAlerts else { return }
                switch alert {
                case .low(let device):
                    self.postNotification(title: device.name, body: "Battery low · \(device.displayLevel ?? 0) %",
                                          symbol: "battery.25percent", category: .devices)
                case .full(let device):
                    self.postNotification(title: device.name, body: "Fully charged", symbol: "battery.100percent.bolt",
                                          category: .devices)
                }
            }
            .store(in: &cancellables)

        if isPrimary { AppActions.shared.viewModel = self }
    }

    /// ⌃⌥N / knock / palette: open (focused for typing) or close the panel.
    func togglePanelFromKeyboard() {
        if engine.isExpanded {
            collapse()
        } else {
            expand()
            NotificationCenter.default.post(name: .dynaNotchWantsKey, object: nil)
        }
    }

    /// Opens a tab focused for typing (clipboard search, palette …).
    func openFocused(_ tab: PanelTab) {
        open(tab: tab)
        NotificationCenter.default.post(name: .dynaNotchWantsKey, object: nil)
    }

    /// "Hide DynaNotch" shortcut (⌥Space by default): hides the whole island — live activities included — and
    /// makes it click-through until the shortcut is pressed again (or the panel is opened on purpose).
    @Published private(set) var isUserHidden = false
    /// While hiding, the "DynaNotch hidden" notice stays visible until this moment.
    private var hideAt: Date?
    private var hideWorkItem: DispatchWorkItem?
    private static let hideNoticeDuration: TimeInterval = 2.2

    func toggleUserHidden() {
        if isUserHidden {
            showAgain()
            return
        }
        collapse()
        isPinned = false
        let now = Date()
        let shortcut = HotKeyMap.parse(settings.hotkeyBindings).binding(for: .hide)?.display
        let body = shortcut.map { "Press \($0) to show it again" } ?? "Choose Show DynaNotch in the menu bar"
        engine.post(.notification(title: "DynaNotch hidden", body: body, symbol: "eye.slash.fill"),
                    now: now, duration: IslandViewModel.hideNoticeDuration)
        isUserHidden = true
        hideAt = now.addingTimeInterval(IslandViewModel.hideNoticeDuration)
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.hideWorkItem = nil
            self?.refresh()
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandViewModel.hideNoticeDuration + 0.02, execute: item)
        refresh()
    }

    private func showAgain() {
        guard isUserHidden else { return }
        isUserHidden = false
        hideAt = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        refresh()
    }

    /// App-originated island message (break reminders, drives, accessories…), using the Popups duration.
    func postNotification(title: String, body: String, symbol: String, category: AlertCategory = .notifications) {
        let kind = ActivityKind.notification(title: title, body: body, symbol: symbol)
        guard !isQuieted(kind) else { return }
        engine.post(kind, now: Date(), duration: settings.notificationDuration)
        didPost(kind, category: category)
        refresh()
    }

    /// Starts every v3 service whose feature is on (all `start()`s are idempotent).
    private func startV3Services() {
        BreakReminderService.shared.start()
        PomodoroStatsService.shared.start()
        BatteryHistoryService.shared.start()
        ScreenTimeService.shared.start()
        MeetingAlertController.shared.start()
        DriveMonitor.shared.start()
        MusicLaunchGuard.shared.start()
        KnockMonitor.shared.start()
        NetworkInfoService.shared.start()
        TrafficService.shared.start()
        ListeningHistoryService.shared.start()
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
            demoUnplugMinutes = nil
            post(.charging(level: info.level, isCharging: false, pluggedIn: false))
        case .lowBattery(let info, _):
            post(.lowBattery(level: info.level))
        }
    }

    // MARK: Media keys (called from the event tap; return true = consume)

    func handleMediaKey(_ event: MediaKeyEvent, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard let key = event.key else { return false }

        switch key {
        case .play, .next, .previous:
            let consumed = handlePlayerKey(event, key)
            lastMediaKeyResult = "\(key) \(event.isDown ? "down" : "up") \(consumed ? "consumed" : "passed")"
            return consumed
        case .soundUp, .soundDown, .mute, .brightnessUp, .brightnessDown:
            break
        default:
            return false   // fast / rewind / keyboard illumination go to the system
        }

        guard settings.hudEnabled && settings.replaceSystemHUD else {
            handledKeyCodes.remove(event.rawKeyCode)
            return false
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

    /// Settings → Now Playing → Media keys control the player: play / next / previous go to the app that is
    /// playing (MediaRemote) instead of macOS, which would otherwise launch Music.app.
    private func handlePlayerKey(_ event: MediaKeyEvent, _ key: MediaKey) -> Bool {
        if !event.isDown {
            if handledKeyCodes.contains(event.rawKeyCode) {
                handledKeyCodes.remove(event.rawKeyCode)
                return true
            }
            return false
        }
        let nowPlaying = NowPlayingService.shared
        // Nothing playing: ▶ opens the chosen default music app (Settings → Now Playing) instead of Music.app.
        if settings.mediaKeysControlPlayer, nowPlaying.snapshot.isEmpty, key == .play,
           MusicLaunchGuard.defaultPlayerBundleID != nil {
            if event.isRepeat { return true }
            guard MusicLaunchGuard.shared.openDefaultPlayer() else { return false }   // not installed → macOS
            handledKeyCodes.insert(event.rawKeyCode)
            return true
        }
        guard settings.mediaKeysControlPlayer, !nowPlaying.snapshot.isEmpty else {
            handledKeyCodes.remove(event.rawKeyCode)
            return false
        }
        handledKeyCodes.insert(event.rawKeyCode)
        if event.isRepeat { return true }
        switch key {
        case .play: nowPlaying.togglePlayPause()
        case .next: nowPlaying.next()
        case .previous: nowPlaying.previous()
        default: break
        }
        return true
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
