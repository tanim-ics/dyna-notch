import AppKit
import SwiftUI
import os

/// Settings → Popups → Edge Glow: a soft coloured glow around every screen's edges for ~1.5 s on important alerts
/// (low battery red, fully charged green, timer finished orange). Click-through, one window per screen.
final class EdgeGlowController {
    static let shared = EdgeGlowController()

    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "edgeGlow")
    static let duration: TimeInterval = 1.5

    private var windows: [NSWindow] = []
    private var generation = 0
    /// Scripted tests: colour name and time of the last flash.
    private(set) var lastFlash: String = "none"

    private init() {}

    /// Flashes the glow if the setting is on; a new flash replaces one still showing.
    func flash(_ color: NSColor) {
        guard AppSettings.shared.edgeGlow else { return }
        generation += 1
        let current = generation
        closeWindows()
        lastFlash = "\(color) \(Date())"
        for screen in NSScreen.screens {
            let window = makeWindow(frame: screen.frame, color: color)
            window.orderFrontRegardless()
            windows.append(window)
        }
        EdgeGlowController.logger.debug("edge glow on \(self.windows.count) screens")
        DispatchQueue.main.asyncAfter(deadline: .now() + EdgeGlowController.duration + 0.25) { [weak self] in
            guard let self = self, self.generation == current else { return }
            self.closeWindows()
        }
    }

    var isShowing: Bool { !windows.isEmpty }

    private func closeWindows() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(frame: NSRect, color: NSColor) -> NSWindow {
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                             defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.title = "DynaNotch Edge Glow"
        window.sharingType = AppSettings.shared.screenSharingPrivacy ? .none : .readOnly
        let host = NSHostingView(rootView: EdgeGlowView(color: Color(nsColor: color),
                                                        duration: EdgeGlowController.duration))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.setFrame(frame, display: true)
        return window
    }
}

/// Blurred coloured border that fades in, holds and fades out within `duration`.
struct EdgeGlowView: View {
    let color: Color
    let duration: TimeInterval
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(color, lineWidth: 26)
                .blur(radius: 22)
            Rectangle()
                .strokeBorder(color.opacity(0.8), lineWidth: 4)
                .blur(radius: 4)
        }
        .opacity(opacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            let fadeIn = reduceMotion ? 0.1 : 0.35
            let fadeOut = reduceMotion ? 0.2 : 0.6
            withAnimation(.easeOut(duration: fadeIn)) { opacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, duration - fadeOut)) {
                withAnimation(.easeIn(duration: fadeOut)) { opacity = 0 }
            }
        }
    }
}
