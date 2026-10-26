import AppKit
import SwiftUI
import DynaNotchCore
import os

extension Notification.Name {
    static let dynaNotchShowWelcome = Notification.Name("DynaNotch.showWelcome")
}

/// Borderless window that can take clicks and keys (Esc skips).
private final class WelcomeWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    var onArrow: ((Int) -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 124, 49, 36: onArrow?(1)     // →, space, return: next slide
        case 123: onArrow?(-1)            // ←: previous slide
        default: super.keyDown(with: event)
        }
    }
}

/// First-launch experience: an island pop-up grows out of the notch with the handwritten "hello",
/// "Welcome to DynaNotch" and tip cards, then shrinks back into the notch.
final class WelcomeController: NSObject {
    static let shared = WelcomeController()

    private var window: WelcomeWindow?
    private let closer = WelcomeCloser()
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "welcome")

    private override init() {
        super.init()
    }

    func show(greetingOnly: Bool = false) {
        guard window == nil,
              let screen = ScreenLocator.targetScreen(mode: AppSettings.shared.displayMode) else { return }
        let measured = ScreenLocator.metrics(for: screen)
        // Non-notch displays: a small black tab at the top edge to grow from.
        let notch = measured.hasPhysicalNotch ? measured
            : NotchMetrics(width: NotchMetrics.fallback.width, height: max(24, measured.height), hasPhysicalNotch: false)
        let handOff = AppActions.shared.viewModel?.expandedSize
            ?? CGSize(width: IslandLayout.expandedWidth, height: notch.height + IslandLayout.expandedContentHeight)
        let size = WelcomeView.canvasSize(notch: notch, handOff: handOff)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        // Above the island panel (.mainMenu + 3) so the pop-up covers it while it grows out of the notch.
        let panel = makeWindow(frame: frame, level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4))
        panel.contentView = NSHostingView(rootView: WelcomeView(notch: notch, greetingOnly: greetingOnly,
                                                                handOffSize: handOff, closer: closer) {
            [weak self] in self?.handOffToApp()
        })
        panel.onEscape = { [weak self] in self?.closer.close?() }
        panel.onArrow = { [weak self] step in step > 0 ? self?.closer.next?() : self?.closer.previous?() }
        window = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    var testWindow: NSWindow? { window }

    /// Debug (`dynanotch://snapshot-welcome/<name>`): renders the visible welcome window to a PNG.
    func snapshot(to url: URL) {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    // MARK: Private

    private func makeWindow(frame: NSRect, level: NSWindow.Level) -> WelcomeWindow {
        let panel = WelcomeWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }

    /// The welcome island has the panel's shape: open the real panel (Home) underneath, fade the pop-up out, and let
    /// the panel settle back into the notch a moment later unless the user is already using it.
    private func handOffToApp() {
        guard let panel = window else { return }
        logger.info("welcome hand-off")
        let vm = AppActions.shared.viewModel
        vm?.open(tab: .home)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.finish()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard let vm = vm, vm.presentation == .expanded, !vm.isHovering, !vm.isPinned else { return }
            vm.collapse()
        }
    }

    private func finish() {
        logger.info("welcome finished")
        window?.orderOut(nil)
        window?.alphaValue = 1
        window = nil
        closer.close = nil
        closer.next = nil
        closer.previous = nil
        AppSettings.shared.hasSeenWelcome = true
        AppSettings.shared.hasCompletedOnboarding = true
    }
}
