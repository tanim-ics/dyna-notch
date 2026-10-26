import AppKit
import SwiftUI
import Combine
import os

/// Scripted UI tests without Accessibility permission (`dynanotch://ui/...`): synthesises real mouse events
/// inside DynaNotch's own windows and picks items from menus while they track, so SwiftUI handles them exactly
/// like a user's click. Coordinates are points from the window's top-left (snapshot pixels ÷ 2 on Retina).
final class UITestDriver {
    static let shared = UITestDriver()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "uitest")
    /// Last menu outcome, reported in `dynanotch://state`.
    private(set) var lastMenuResult = ""
    private var pendingMenuItem: String?
    private var pendingMenuDelay: TimeInterval = 0
    private var pendingPointerAway = false
    /// Moves the simulated pointer off the island (set by the app delegate).
    var movePointerAway: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] note in self?.menuDidOpen(note.object as? NSMenu) }
            .store(in: &cancellables)
    }

    /// Mouse down + up at `point` (top-left origin, points) in `window`. The mouse-up is queued before the
    /// mouse-down is delivered, because controls like switches and sliders run their own tracking loop that
    /// reads the release from the event queue (exactly what happens with a real click).
    func click(in window: NSWindow, at point: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
        guard let content = window.contentView else { return }
        let location = NSPoint(x: point.x, y: content.bounds.height - point.y)
        let time = ProcessInfo.processInfo.systemUptime
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: modifiers, timestamp: time,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                               pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
        logger.info("click \(point.x, privacy: .public),\(point.y, privacy: .public) in \(window.title, privacy: .public)")
    }

    /// `delay` keeps the menu open that long first, like a person reading it.
    /// `pointerAway` moves the simulated pointer onto the menu (off the island) once it is open, like a user.
    func chooseInNextMenu(_ title: String, delay: TimeInterval = 0, pointerAway: Bool = false) {
        pendingMenuItem = title
        pendingMenuDelay = delay
        pendingPointerAway = pointerAway
    }

    private func menuDidOpen(_ menu: NSMenu?) {
        guard let menu = menu, let title = pendingMenuItem else { return }
        pendingMenuItem = nil
        if pendingPointerAway { movePointerAway?() }
        // Run inside the menu's tracking loop, like a real selection.
        let timer = Timer(timeInterval: max(0.01, pendingMenuDelay), repeats: false) { [weak self] _ in
            if let (owner, index) = UITestDriver.find(title, in: menu) {
                self?.lastMenuResult = "chose \(title) [\(index) of \(owner.items.count)]"
                owner.performActionForItem(at: index)
                self?.logger.info("menu item \(title, privacy: .public) chosen")
            } else {
                self?.lastMenuResult = "missing \(title) in [\(menu.items.map(\.title).joined(separator: "|"))]"
                self?.logger.error("menu item \(title, privacy: .public) not found")
            }
            menu.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .default)
    }

    private static func find(_ title: String, in menu: NSMenu) -> (NSMenu, Int)? {
        for (index, item) in menu.items.enumerated() {
            if item.title == title { return (menu, index) }
            if let sub = item.submenu, let found = find(title, in: sub) { return found }
        }
        return nil
    }
}

/// Views tagged with `.uiTestID(_:)`. Frames are measured when asked, so they stay right after scrolling.
final class UITestRegistry {
    static let shared = UITestRegistry()

    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var views: [String: WeakView] = [:]

    func register(_ id: String, _ view: NSView) { views[id] = WeakView(view) }

    /// Live frames in each view's window, top-left origin (only views currently in a window).
    var frames: [String: CGRect] {
        var result: [String: CGRect] = [:]
        for (id, ref) in views {
            guard let view = ref.view, let window = view.window, let content = window.contentView else { continue }
            let rect = view.convert(view.bounds, to: nil)
            result[id] = CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        }
        return result
    }
}

/// Invisible AppKit view behind a tagged SwiftUI view; registers itself under the id.
private struct UITestAnchor: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        UITestRegistry.shared.register(id, view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        UITestRegistry.shared.register(id, nsView)
    }
}

extension View {
    /// Lets scripted UI tests click this view by name (`dynanotch://ui/click?id=<id>`).
    func uiTestID(_ id: String) -> some View { background(UITestAnchor(id: id).allowsHitTesting(false)) }
}
