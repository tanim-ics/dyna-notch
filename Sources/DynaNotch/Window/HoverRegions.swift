import AppKit
import SwiftUI

/// Named areas of the island canvas that react to the pointer (header buttons that open a card on hover, and the
/// cards themselves). The window controller hit-tests them on every pointer move — the same pointer it uses for the
/// island's own hover, so it also follows the scripted test pointer.
final class HoverRegions {
    static let shared = HoverRegions()

    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var views: [String: WeakView] = [:]

    private init() {}

    func register(_ id: String, _ view: NSView) { views[id] = WeakView(view) }

    /// The first region under `point` (window coordinates, top-left origin) among views in `window`.
    func region(at point: NSPoint, in window: NSWindow) -> String? {
        guard let content = window.contentView else { return nil }
        for (id, ref) in views {
            guard let view = ref.view, view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
            let rect = view.convert(view.bounds, to: nil)
            let topLeft = CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
            if topLeft.insetBy(dx: -2, dy: -2).contains(point) { return id }
        }
        return nil
    }
}

private struct HoverRegionAnchor: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        HoverRegions.shared.register(id, view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        HoverRegions.shared.register(id, nsView)
    }
}

extension View {
    /// Marks this view as a pointer-hover region of the island (see `HoverRegions`).
    func hoverRegion(_ id: String) -> some View { background(HoverRegionAnchor(id: id).allowsHitTesting(false)) }
}
