import AppKit
import SwiftUI
import Combine

class NotchWindowController: NSWindowController {
    let viewModel = NotchViewModel()
    private let musicVM = MusicViewModel.shared
    private var cancellables = Set<AnyCancellable>()

    private var collapsedSize   = CGSize(width: 340, height: 36)
    private let expandedMusic   = CGSize(width: 390, height: 128)
    private let expandedHUD     = CGSize(width: 300, height: 76)
    private let expandedNotif   = CGSize(width: 370, height: 104)
    private let tuckedSize      = CGSize(width: 80, height: 2)

    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var currentTargetScreen: NSScreen?

    init() {
        let panel = NotchPanel()
        super.init(window: panel)

        let hostingView = NotchHostingView(
            rootView: NotchContainerView()
                .environmentObject(viewModel)
                .environmentObject(musicVM)
        )
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.panel = panel
        panel.contentView = hostingView

        currentTargetScreen = targetScreen
        positionAtScreen(animated: false)
        setupScreenObserver()
        setupFocusTracking()
        wireViewModels()
        observeState()
    }

    deinit {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    var targetScreen: NSScreen? {
        let pref = UserDefaults.standard.string(forKey: "displayMode") ?? "focused"
        if pref == "focused" {
            let mouseLoc = NSEvent.mouseLocation
            if let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
                return screenWithMouse
            }
            return NSScreen.main ?? NSScreen.screens.first
        } else if pref == "notch" {
            if let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notchScreen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    func getNotchDimensions(for screen: NSScreen) -> (hasNotch: Bool, width: CGFloat, height: CGFloat) {
        let hasNotch = screen.safeAreaInsets.top > 0
        var width: CGFloat = 200
        var height: CGFloat = 32

        if hasNotch {
            height = screen.safeAreaInsets.top
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let w = right.minX - left.maxX
                if w > 50 { width = w }
            } else {
                width = 185
            }
        } else {
            height = 32
            width = 200
        }
        return (hasNotch, width, height)
    }

    // MARK: – Wire view-models
    private func wireViewModels() {
        SystemEventsViewModel.shared.connect(to: viewModel)

        // Auto-expand when playback starts (and wasn't already playing)
        musicVM.$isPlaying
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.viewModel.musicPlaybackStarted() }
            .store(in: &cancellables)
    }

    private func updateCollapsedSize() {
        let hasMedia = viewModel.showMusicWidget && !musicVM.title.isEmpty
        if hasMedia {
            collapsedSize = CGSize(width: 340, height: 36)
        } else {
            collapsedSize = CGSize(width: 190, height: 32)
        }
    }

    private var currentExpandedSize: CGSize {
        switch viewModel.activeContent {
        case .hud: return expandedHUD
        case .notification: return expandedNotif
        default: return expandedMusic
        }
    }

    // MARK: – Drive NSPanel frame from VM state
    private func observeState() {
        Publishers.CombineLatest(
            Publishers.CombineLatest4(
                viewModel.$isExpanded,
                viewModel.$activeContent,
                musicVM.$isPlaying,
                musicVM.$title
            ),
            viewModel.$isTucked
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] base, isTucked in
            guard let self else { return }
            let (expanded, _, _, _) = base
            if isTucked {
                guard let panel = self.window as? NotchPanel else { return }
                panel.isTucked = true
                panel.ignoresMouseEvents = true
                self.animateTo(self.tuckedSize, alpha: 0.3)
            } else {
                guard let panel = self.window as? NotchPanel else { return }
                panel.isTucked = false
                self.updateCollapsedSize()
                if expanded {
                    self.animateTo(self.currentExpandedSize, alpha: 1.0)
                } else {
                    self.animateTo(self.collapsedSize, alpha: 1.0)
                }
                self.updatePassThrough()
            }
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.currentTargetScreen = self.targetScreen
                self.positionAtScreen(animated: true)
                self.updatePassThrough()
            }
            .store(in: &cancellables)
    }

    // MARK: – Screen positioning
    private func positionAtScreen(animated: Bool = false) {
        guard let screen = targetScreen, let win = window else { return }
        let sf = screen.frame
        updateCollapsedSize()
        let size = viewModel.isTucked ? tuckedSize : (viewModel.isExpanded ? currentExpandedSize : collapsedSize)
        let x = sf.midX - size.width / 2
        let y = sf.maxY - size.height
        let targetRect = NSRect(x: round(x), y: round(y), width: round(size.width), height: round(size.height))

        let (hasNotch, notchW, _) = getNotchDimensions(for: screen)
        if viewModel.hasPhysicalNotch != hasNotch { viewModel.hasPhysicalNotch = hasNotch }
        if viewModel.physicalNotchWidth != notchW { viewModel.physicalNotchWidth = notchW }

        if animated {
            win.alphaValue = 0.1
            win.setFrame(targetRect, display: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.58, 0.12, 1.0)
                win.animator().alphaValue = viewModel.isTucked ? 0.3 : 1.0
            }
        } else {
            win.setFrame(targetRect, display: true)
            win.alphaValue = viewModel.isTucked ? 0.3 : 1.0
        }
        win.orderFrontRegardless()
    }

    private func setupScreenObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screenChanged() {
        currentTargetScreen = targetScreen
        positionAtScreen(animated: false)
    }

    private var lastPassThroughState: Bool?

    // MARK: – Focus Tracking & Hit Testing across displays
    private func setupFocusTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .flagsChanged]) { [weak self] _ in
            self?.checkFocusDisplay()
            self?.updatePassThrough()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .flagsChanged]) { [weak self] event in
            self?.updatePassThrough()
            return event
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(checkFocusDisplay),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func updatePassThrough() {
        guard let panel = window as? NotchPanel else { return }
        panel.isTucked = viewModel.isTucked
        panel.capsuleCornerRadius = viewModel.isExpanded ? 24 : 17
        panel.shouldPassThroughClicks = (viewModel.clickThroughExternal && !viewModel.isExpanded)

        let mouseLoc = NSEvent.mouseLocation
        let modifiers = NSEvent.modifierFlags

        let shouldIgnore: Bool
        if panel.isTucked || modifiers.contains(.command) || modifiers.contains(.option) || panel.shouldPassThroughClicks {
            shouldIgnore = true
        } else {
            let winFrame = panel.frame
            // Fast bounding box: if mouse is not within 20px of the panel, pass through immediately
            let paddedFrame = winFrame.insetBy(dx: -20, dy: -20)
            if !NSMouseInRect(mouseLoc, paddedFrame, false) {
                shouldIgnore = true
            } else {
                let windowPoint = panel.convertPoint(fromScreen: mouseLoc)
                shouldIgnore = !panel.isPointInsideCapsule(windowPoint)
            }
        }

        if lastPassThroughState != shouldIgnore {
            lastPassThroughState = shouldIgnore
            if panel.ignoresMouseEvents != shouldIgnore {
                panel.ignoresMouseEvents = shouldIgnore
            }
        }
    }

    @objc private func checkFocusDisplay() {
        let mode = UserDefaults.standard.string(forKey: "displayMode") ?? "focused"
        guard mode == "focused" else { return }

        let mouseLoc = NSEvent.mouseLocation
        if let current = currentTargetScreen, NSMouseInRect(mouseLoc, current.frame, false) {
            return
        }

        guard let newScreen = targetScreen else { return }
        if let last = currentTargetScreen, last.frame == newScreen.frame {
            return
        }

        currentTargetScreen = newScreen
        positionAtScreen(animated: true)
    }

    func animateTo(_ size: CGSize, alpha: CGFloat = 1.0) {
        guard let win = window, let screen = targetScreen else { return }
        let sf = screen.frame
        let x  = round(sf.midX - size.width / 2)
        let y  = round(sf.maxY - size.height)
        let targetRect = NSRect(x: x, y: y, width: round(size.width), height: round(size.height))

        if abs(win.frame.origin.x - targetRect.origin.x) < 1.0 &&
           abs(win.frame.origin.y - targetRect.origin.y) < 1.0 &&
           abs(win.frame.width - targetRect.width) < 1.0 &&
           abs(win.frame.height - targetRect.height) < 1.0 &&
           abs(win.alphaValue - alpha) < 0.05 {
            win.orderFrontRegardless()
            return
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.58, 0.12, 1.0)
            win.animator().setFrame(targetRect, display: false)
            win.animator().alphaValue = alpha
        }
        win.orderFrontRegardless()
    }
}
