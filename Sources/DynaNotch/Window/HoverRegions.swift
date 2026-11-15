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

    // Each display's island has its own header, so one id can belong to several views (one per window).
    private var views: [String: [WeakView]] = [:]
    /// Region id → id of the clip area it must also be inside (icons in a scrolling row).
    private var clipOf: [String: String] = [:]
    /// Clip areas (never reported as regions themselves).
    private var clips: [String: [WeakView]] = [:]

    private init() {}

    func register(_ id: String, _ view: NSView, within clip: String? = nil) {
        views[id] = adding(view, to: views[id])
        clipOf[id] = clip
    }

    func registerClip(_ id: String, _ view: NSView) { clips[id] = adding(view, to: clips[id]) }

    private func adding(_ view: NSView, to list: [WeakView]?) -> [WeakView] {
        var live = (list ?? []).filter { $0.view != nil }
        if !live.contains(where: { $0.view === view }) { live.append(WeakView(view)) }
        return live
    }

    /// The first region under `point` (window coordinates, top-left origin) among views in `window`.
    func region(at point: NSPoint, in window: NSWindow) -> String? {
        for (id, refs) in views {
            guard let rect = frame(of: refs, in: window), rect.insetBy(dx: -2, dy: -2).contains(point) else { continue }
            // A region scrolled out of its row keeps its (off-row) frame, so it must also be inside the row.
            if let clip = clipOf[id] {
                guard let area = frame(of: clips[clip] ?? [], in: window), area.contains(point) else { continue }
            }
            return id
        }
        return nil
    }

    /// Frame of the view among `refs` that is showing in `window`.
    private func frame(of refs: [WeakView], in window: NSWindow) -> CGRect? {
        guard let content = window.contentView,
              let view = refs.lazy.compactMap({ $0.view }).first(where: {
                  $0.window === window && !$0.isHiddenOrHasHiddenAncestor
              }) else { return nil }
        let rect = view.convert(view.bounds, to: nil)
        return CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
}

private struct HoverRegionAnchor: NSViewRepresentable {
    let id: String
    var clip: String?
    var isClip = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        register(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { register(nsView) }

    private func register(_ view: NSView) {
        if isClip {
            HoverRegions.shared.registerClip(id, view)
        } else {
            HoverRegions.shared.register(id, view, within: clip)
        }
    }
}

extension View {
    /// Marks this view as a pointer-hover region of the island (see `HoverRegions`).
    func hoverRegion(_ id: String) -> some View { background(HoverRegionAnchor(id: id).allowsHitTesting(false)) }

    /// A hover region that only counts inside the clip area `clip` (see `hoverClip`), for views in a scrolling row.
    func hoverRegion(_ id: String, within clip: String) -> some View {
        background(HoverRegionAnchor(id: id, clip: clip).allowsHitTesting(false))
    }

    /// Marks this view as the visible area for regions registered `within:` it.
    func hoverClip(_ id: String) -> some View {
        background(HoverRegionAnchor(id: id, isClip: true).allowsHitTesting(false))
    }
}
