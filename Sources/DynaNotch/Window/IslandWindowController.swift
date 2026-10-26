import AppKit
import SwiftUI
import Combine
import DynaNotchCore

/// Owns the island panel: placement on the target screen, click-through toggling, hover tracking,
/// outside clicks, two-finger swipes and full-screen suppression (CLAUDE.md §5, §6.3).
final class IslandWindowController: NSObject {
    private let viewModel: IslandViewModel
    private let settings: AppSettings
    private var panel: NotchPanel
    private let hostingView: NotchHostingView<AnyView>

    private var currentScreen: NSScreen?
    private var cancellables = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var isShown = false

    // Hover / click-through state
    private var lastInside = false

    // File drags towards the island (shelf)
    private var dragChangeCountAtMouseDown = 0
    private var isFileDragActive = false
    /// A menu opened from the expanded panel (tab ⋯, actions ⋯, output) is tracking: the pointer is over the
    /// menu, outside the island, but the panel must stay open until an item is chosen.
    private var isPanelMenuOpen = false
    /// After a panel menu closes the pointer is often below the panel (long menus); keep it open until the pointer
    /// comes back over the island, or for a few seconds.
    private var menuGraceUntil: Date?
    /// Scripted UI tests (`dynanotch://ui/pointer`): overrides the real pointer location for hover decisions.
    var testPointer: NSPoint?
    /// Scripted tests (`dynanotch://ui/override`): fake full screen, frontmost app and mirroring.
    var testFullscreen: Bool? { didSet { updateSuppression() } }
    var testFrontBundle: String? { didSet { updateSuppression() } }
    var testMirrored: Bool? { didSet { updateSuppression() } }
    private var workspaceObserver: NSObjectProtocol?
    /// Last suppression decision and why (state dump).
    private(set) var suppressionReason = "none"
    private var keyObserver: NSObjectProtocol?

    // Swipe accumulation
    private var scrollAccumX: CGFloat = 0
    private var scrollAccumY: CGFloat = 0
    private var lastSwipeAt: Date = .distantPast
    private static let swipeCooldown: TimeInterval = 0.6
    private static let horizontalThreshold: CGFloat = 45
    private static let verticalThreshold: CGFloat = 35

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        self.settings = AppSettings.shared

        let contentRect = NSRect(origin: .zero, size: IslandLayout.canvasSize)
        panel = NotchPanel(contentRect: contentRect)

        let root = IslandRootView()
            .environmentObject(viewModel)
            .environmentObject(AppSettings.shared)
            .environmentObject(NowPlayingService.shared)
            .environmentObject(BatteryService.shared)
            .environmentObject(CalendarService.shared)
            .environmentObject(FocusService.shared)
            .environmentObject(MediaKeyTap.shared)
            .environmentObject(TimerService.shared)
            .environmentObject(ClipboardService.shared)
            .environmentObject(ShelfService.shared)
            .environmentObject(NotesService.shared)
            .environmentObject(LyricsService.shared)
            .environmentObject(WeatherService.shared)
            .environmentObject(SystemMonitorService.shared)
            .environmentObject(AIUsageService.shared)
            .environmentObject(AudioDeviceService.shared)
            .environmentObject(KeepAwakeService.shared)
            .environmentObject(DeviceBatteryService.shared)
            .environmentObject(LauncherService.shared)
            .environmentObject(ShortcutsService.shared)
            .environmentObject(RemindersService.shared)
            .environmentObject(CameraService.shared)
            .environmentObject(ScreenTimeService.shared)
            .environmentObject(PomodoroStatsService.shared)
            .environmentObject(BatteryHistoryService.shared)
            .environmentObject(ColorHistory.shared)
        hostingView = NotchHostingView<AnyView>(rootView: AnyView(root))

        super.init()

        // The hosting view must never drive the window size (v1 layout-recursion crashes).
        hostingView.sizingOptions = []
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    deinit {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = keyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: Public

    func show() {
        guard !isShown else {
            reposition()
            return
        }
        isShown = true
        applySharingType()
        dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        reposition()   // positions and orders the panel front (unless hidden-idle on a non-notch screen)
        installObservers()
        installMonitors()
        startFullscreenDetection()
        DesktopLyricsController.shared.start(screenProvider: { [weak self] in self?.currentScreen })
    }

    /// Scripted UI tests: the island panel and a pointer position in canvas points (top-left origin).
    var testWindow: NSWindow { panel }
    var screenName: String { currentScreen?.localizedName ?? "none" }

    func setTestPointer(canvasPoint: NSPoint?) {
        if let p = canvasPoint {
            testPointer = NSPoint(x: panel.frame.minX + p.x, y: panel.frame.maxY - p.y)
        } else {
            testPointer = nil
        }
        updateHover()
    }

    /// Renders the panel canvas into a PNG (debug: `dynanotch://snapshot`), no Screen Recording permission needed.
    @discardableResult
    func snapshot(to url: URL) -> Bool {
        let bounds = hostingView.bounds
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        hostingView.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    // MARK: Positioning

    private func reposition() {
        guard let screen = ScreenLocator.targetScreen(mode: settings.displayMode) else { return }
        currentScreen = screen
        viewModel.setNotch(ScreenLocator.metrics(for: screen))
        // The canvas is fixed while the island animates; it only grows for a wider / taller panel setting.
        let frame = IslandLayout.panelFrame(screenFrame: screen.frame, canvas: viewModel.canvasSize)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        updateVisibility(presentation: viewModel.presentation)
        updateSuppression()   // mirroring may have changed with the screen configuration
        updateHover()
    }

    /// Non-notch screens with the fake notch turned off: hide the panel while idle.
    private func updateVisibility(presentation: IslandPresentation) {
        let hideIdle = presentation == .idle
            && !viewModel.isOnNotchDisplay
            && !settings.showOnNonNotchDisplays
        if hideIdle {
            if panel.isVisible { panel.orderOut(nil) }
        } else if isShown {
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    // MARK: Observers

    private func installObservers() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }

        // @Published emits before the value is stored → defer with receive(on:).
        settings.$displayMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        // Island shape (Notch / Floating pill) applies at once: re-measure, re-layout and redraw.
        Publishers.Merge(settings.$notchDisplayStyle.map { _ in () }, settings.$nonNotchStyle.map { _ in () })
            .dropFirst(2)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.viewModel.applySettingsNow()
                self.reposition()
                self.hostingView.needsDisplay = true
            }
            .store(in: &cancellables)

        keyObserver = NotificationCenter.default.addObserver(
            forName: .dynaNotchWantsKey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.viewModel.presentation == .expanded else { return }
            self.panel.ignoresMouseEvents = false
            self.panel.makeKey()
        }

        // Settings → Behavior → Screen Sharing Privacy: keep the island out of screenshots, recordings and shares.
        settings.$screenSharingPrivacy
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySharingType() }
            .store(in: &cancellables)

        // Settings → Appearance → Panel width / maximum height may need a bigger canvas.
        Publishers.Merge(settings.$panelWidth.map { _ in () }, settings.$panelMaxHeight.map { _ in () })
            .dropFirst(2)
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        settings.$showOnNonNotchDisplays
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        viewModel.$presentation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateVisibility(presentation: self.viewModel.presentation)
                if self.viewModel.presentation != .expanded && self.panel.isKeyWindow {
                    self.returnKeyFocus()
                }
                self.updateHover()
            }
            .store(in: &cancellables)

        viewModel.$notch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateVisibility(presentation: self.viewModel.presentation)
                self.updateHover()
            }
            .store(in: &cancellables)

        // Safety poll in case a mouse-moved event was missed.
        Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateHover() }
            .store(in: &cancellables)
    }

    private func installMonitors() {
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                guard let self = self, self.viewModel.presentation == .expanded else { return }
                self.isPanelMenuOpen = true
                self.updateHover()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self = self, self.isPanelMenuOpen else { return }
                self.isPanelMenuOpen = false
                self.menuGraceUntil = Date().addingTimeInterval(3)
                // The chosen item's action runs right after tracking ends; re-check the pointer afterwards.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.updateHover() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.05) { self.updateHover() }
            }
            .store(in: &cancellables)
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.mouseMoved()
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.mouseMoved()
            return event
        }) {
            monitors.append(m)
        }
        // Clicks in other apps (always outside our island) collapse the expanded island (unless pinned).
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self = self else { return }
            if event.type == .leftMouseDown {
                self.dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            }
            if self.viewModel.presentation == .expanded {
                self.viewModel.collapseFromOutside()
            }
        }) {
            monitors.append(m)
        }
        // Files dragged from another app towards the notch open the shelf.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] _ in
            self?.checkFileDrag()
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            self?.endFileDrag()
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] event in
            self?.dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            DispatchQueue.main.async { self?.endFileDrag() }
            return event
        }) {
            monitors.append(m)
        }
        // Esc closes the panel while it has keyboard focus.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard let self = self else { return event }
            // Only Esc typed in the island itself: the command palette and Settings handle their own Esc.
            if event.keyCode == 53, event.window === self.panel, self.viewModel.presentation == .expanded {
                self.viewModel.collapse()
                return nil
            }
            return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: { [weak self] event in
            self?.handleScroll(event)
            return event
        }) {
            monitors.append(m)
        }
    }

    private func applySharingType() {
        let type: NSWindow.SharingType = settings.screenSharingPrivacy ? .none : .readOnly
        guard panel.sharingType != type else { return }
        panel.sharingType = type
        // AppKit (macOS 26+) never leaves `.none` once set: move the canvas into a fresh panel instead.
        if panel.sharingType != type { replacePanel() }
    }

    /// Swaps in a new `NotchPanel` hosting the same SwiftUI canvas, at the same frame and visibility.
    private func replacePanel() {
        let old = panel
        let fresh = NotchPanel(contentRect: old.frame)
        old.contentView = nil
        fresh.contentView = hostingView
        hostingView.frame = NSRect(origin: .zero, size: old.frame.size)
        fresh.setFrame(old.frame, display: false)
        fresh.ignoresMouseEvents = old.ignoresMouseEvents
        let wasVisible = old.isVisible
        panel = fresh
        if wasVisible { fresh.orderFrontRegardless() }
        old.orderOut(nil)
    }

    var sharingTypeName: String { panel.sharingType == NSWindow.SharingType.none ? "none" : "readOnly" }

    /// Full screen (Settings → Behavior → Full-screen apps: All / Playing media app) and Hide While Mirroring.
    private func startFullscreenDetection() {
        let detector = FullscreenDetector.shared
        detector.start(screenProvider: { [weak self] in self?.currentScreen })
        let triggers: [AnyPublisher<Void, Never>] = [
            detector.$isFullscreen.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$hideInFullscreen.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$fullscreenScope.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$hideWhileMirroring.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NowPlayingService.shared.$snapshot.map(\.bundleIdentifier).removeDuplicates().map { _ in () }
                .eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)   // @Published emits before the new value is stored
            .sink { [weak self] _ in self?.updateSuppression() }
            .store(in: &cancellables)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateSuppression()
        }
    }

    private func updateSuppression() {
        var reason = "none"
        let fullscreen = testFullscreen ?? FullscreenDetector.shared.isFullscreen
        if fullscreen && settings.hideInFullscreen {
            switch settings.fullscreenScope {
            case .allApps:
                reason = "fullscreen"
            case .mediaApp:
                if frontmostIsPlayingApp() { reason = "fullscreen-media" }
            }
        }
        if reason == "none" && settings.hideWhileMirroring && isMirroring() {
            reason = "mirroring"
        }
        suppressionReason = reason
        viewModel.setSuppressed(reason != "none")
    }

    /// The frontmost app is the one whose media is playing (bundle id, or the same app name for browsers / PWAs).
    private func frontmostIsPlayingApp() -> Bool {
        let nowPlaying = NowPlayingService.shared
        guard !nowPlaying.snapshot.isEmpty else { return false }
        let front = NSWorkspace.shared.frontmostApplication
        let bundle = testFrontBundle ?? front?.bundleIdentifier
        if let playing = nowPlaying.snapshot.bundleIdentifier, let bundle = bundle, playing == bundle { return true }
        if testFrontBundle == nil, let name = front?.localizedName, !name.isEmpty, name == nowPlaying.appName {
            return true
        }
        return false
    }

    /// The island's display is part of a mirror set (mirrored to a projector / AirPlay).
    private func isMirroring() -> Bool {
        if let forced = testMirrored { return forced }
        guard let screen = currentScreen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsInMirrorSet(CGDirectDisplayID(number.uint32Value)) != 0
    }

    // MARK: Mouse

    private func mouseMoved() {
        if lastInside { viewModel.noteInteraction() }
        if settings.displayMode == .followMouse,
           let screen = ScreenLocator.screenContainingMouse(),
           screen.frame != currentScreen?.frame {
            reposition()
            return   // reposition() already updated hover
        }
        updateHover()
    }

    private func updateHover() {
        guard let screen = currentScreen else { return }
        let presentation = viewModel.presentation
        var inside = false
        if presentation != .hidden && panel.isVisible {
            let island = IslandLayout.screenRect(for: viewModel.visibleIslandSize, screenFrame: screen.frame,
                                                 topInset: viewModel.topInset)
                .insetBy(dx: -4, dy: -4)
            // Extend upward to the screen top so the very top pixel row (y == screen maxY) counts as inside.
            let hitRect = NSRect(x: island.minX, y: island.minY, width: island.width,
                                 height: screen.frame.maxY - island.minY + 2)
            inside = hitRect.contains(testPointer ?? NSEvent.mouseLocation)
        }
        if let grace = menuGraceUntil {
            if inside || Date() >= grace || viewModel.presentation != .expanded {
                menuGraceUntil = nil
            } else {
                inside = true
            }
        }
        if isFileDragActive || isPanelMenuOpen { inside = true }
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        if inside != lastInside {
            lastInside = inside
            if !inside {
                scrollAccumX = 0
                scrollAccumY = 0
            }
        }
        if viewModel.isHovering != inside {
            viewModel.setHovering(inside)
        }
        updateHeaderHover(inside: inside)
    }

    /// Battery / sound header buttons open their card on hover (see `HoverRegions`).
    private func updateHeaderHover(inside: Bool) {
        var region: String?
        if inside && viewModel.presentation == .expanded {
            let p = testPointer ?? NSEvent.mouseLocation
            let point = NSPoint(x: p.x - panel.frame.minX, y: panel.frame.maxY - p.y)
            region = HoverRegions.shared.region(at: point, in: panel)
        }
        viewModel.setHeaderHover(region)
    }

    /// Hands keyboard focus back to the app the user was working in (our panel never activates DynaNotch).
    private func returnKeyFocus() {
        panel.resignKey()
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            front.activate()
        }
    }

    // MARK: File drags

    /// Zone around the notch that reacts to file drags (generous so the drop target is easy to hit).
    private func dragZone(on screen: NSScreen) -> NSRect {
        let width = max(viewModel.expandedSize.width, viewModel.visibleIslandSize.width) + 80
        let height: CGFloat = 90
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height + 2)
    }

    private func checkFileDrag() {
        guard settings.shelfEnabled, let screen = currentScreen else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCountAtMouseDown,
              pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        let inZone = dragZone(on: screen).contains(NSEvent.mouseLocation)
        if inZone && !isFileDragActive {
            isFileDragActive = true
            viewModel.beginFileDrag()
            updateHover()
        }
    }

    private func endFileDrag() {
        guard isFileDragActive else { return }
        isFileDragActive = false
        dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        updateHover()
    }

    // MARK: Swipes

    private func handleScroll(_ event: NSEvent) {
        // The open panel's lists (clipboard, emoji, launcher …) own scrolling; swipes only act on the compact island.
        guard settings.gesturesEnabled, viewModel.isHovering, viewModel.presentation != .expanded else { return }
        // Ignore inertial scrolling; only the fingers-on-trackpad part counts.
        if event.momentumPhase != [] { return }
        if event.phase == .began {
            scrollAccumX = 0
            scrollAccumY = 0
        }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        var dx = event.scrollingDeltaX * multiplier
        var dy = event.scrollingDeltaY * multiplier
        // Normalise to finger direction ("natural" scrolling reports inverted deltas).
        if !event.isDirectionInvertedFromDevice {
            dx = -dx
            dy = -dy
        }
        scrollAccumX += dx
        scrollAccumY += dy

        let now = Date()
        guard now.timeIntervalSince(lastSwipeAt) >= IslandWindowController.swipeCooldown else { return }

        var direction: SwipeDirection?
        if abs(scrollAccumX) > IslandWindowController.horizontalThreshold && abs(scrollAccumX) >= abs(scrollAccumY) {
            direction = scrollAccumX < 0 ? .left : .right
        } else if scrollAccumY < -IslandWindowController.verticalThreshold {
            direction = .up
        } else if scrollAccumY > IslandWindowController.verticalThreshold {
            direction = .down
        }

        if let direction = direction {
            lastSwipeAt = now
            scrollAccumX = 0
            scrollAccumY = 0
            viewModel.swipe(direction)
        }
    }
}
