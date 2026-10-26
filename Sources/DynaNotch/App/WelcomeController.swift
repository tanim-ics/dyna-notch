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

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// First-launch experience: full-screen "hello" → welcome → tip cards under the notch.
final class WelcomeController: NSObject {
    static let shared = WelcomeController()

    private var window: WelcomeWindow?
    private var tipsWindow: WelcomeWindow?

    private override init() {
        super.init()
    }

    func show() {
        guard window == nil, tipsWindow == nil,
              let screen = ScreenLocator.targetScreen(mode: AppSettings.shared.displayMode) else { return }
        let panel = makeWindow(frame: screen.frame, level: .screenSaver)
        panel.contentView = NSHostingView(rootView: WelcomeView { [weak self] in self?.finishGreeting(reason: "button") })
        panel.onEscape = { [weak self] in self?.finishGreeting(reason: "escape") }
        window = panel
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            panel.animator().alphaValue = 1
        }
    }

    /// Debug (`dynanotch://snapshot-welcome/<name>`): renders the visible welcome or tips window to a PNG.
    func snapshot(to url: URL) {
        guard let view = (window ?? tipsWindow)?.contentView,
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

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "welcome")

    private func finishGreeting(reason: String) {
        logger.info("greeting finished: \(reason, privacy: .public)")
        guard let panel = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.showTips()
        })
    }

    private func showTips() {
        guard let screen = ScreenLocator.targetScreen(mode: AppSettings.shared.displayMode) else {
            markSeen()
            return
        }
        let host = NSHostingView(rootView: WelcomeTipsView { [weak self] in self?.finishTips() })
        let size = host.fittingSize
        let notchHeight = ScreenLocator.metrics(for: screen).height
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - notchHeight - 14 - size.height,
                           width: size.width, height: size.height)
        let panel = makeWindow(frame: frame, level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4))
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.finishTips() }
        tipsWindow = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 1
        }
    }

    private func finishTips() {
        guard let panel = tipsWindow else { return }
        tipsWindow = nil
        markSeen()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func markSeen() {
        AppSettings.shared.hasSeenWelcome = true
        AppSettings.shared.hasCompletedOnboarding = true
    }
}
