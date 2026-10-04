import AppKit
import SwiftUI

class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var panel: NotchPanel?

    override class var requiresConstraintBasedLayout: Bool {
        return false
    }

    override var needsUpdateConstraints: Bool {
        get { return false }
        set { /* No-op: prevent reentrant layout crash during display cycle flush */ }
    }

    override func updateConstraints() {
        // Safe no-op
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panel = panel else { return super.hitTest(point) }

        // If tucked, clicks pass straight through to underlying windows
        if panel.isTucked { return nil }

        // Holding Command or Option allows clicking through to underlying browser tabs / windows
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.option) {
            return nil
        }

        // External display pass-through if enabled and collapsed
        if panel.shouldPassThroughClicks {
            return nil
        }

        // If outside the rounded pill path, pass clicks through
        if !panel.isPointInsideCapsule(point) {
            return nil
        }

        return super.hitTest(point)
    }
}

class NotchPanel: NSPanel {
    var capsuleCornerRadius: CGFloat = 16
    var isTucked: Bool = false
    var shouldPassThroughClicks: Bool = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sharingType = .readOnly
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func isPointInsideCapsule(_ point: NSPoint) -> Bool {
        guard let view = contentView else { return false }
        let bounds = view.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return false }
        let path = NSBezierPath(roundedRect: bounds, xRadius: capsuleCornerRadius, yRadius: capsuleCornerRadius)
        return path.contains(point)
    }

    func updateMousePassThrough(at screenPoint: NSPoint, modifiers: NSEvent.ModifierFlags) {
        if isTucked {
            if !ignoresMouseEvents { ignoresMouseEvents = true }
            return
        }
        if modifiers.contains(.command) || modifiers.contains(.option) {
            if !ignoresMouseEvents { ignoresMouseEvents = true }
            return
        }
        if shouldPassThroughClicks {
            if !ignoresMouseEvents { ignoresMouseEvents = true }
            return
        }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let inside = isPointInsideCapsule(windowPoint)
        let shouldIgnore = !inside
        if ignoresMouseEvents != shouldIgnore {
            ignoresMouseEvents = shouldIgnore
        }
    }

    override func updateConstraintsIfNeeded() {
        // Safe no-op for window auto-layout constraints
    }

    override func layoutIfNeeded() {
        // Safe no-op to prevent display-cycle recursion
    }

    required init?(coder: NSCoder) { fatalError() }
}
