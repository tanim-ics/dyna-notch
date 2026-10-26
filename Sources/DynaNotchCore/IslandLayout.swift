import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum HUDStyle: String, Equatable, Hashable, CaseIterable {
    case compact, expanded

    public var title: String {
        switch self {
        case .compact: return "Compact"
        case .expanded: return "Expanded"
        }
    }
}

public struct IslandRadii: Equatable {
    public var top: CGFloat
    public var bottom: CGFloat
    public init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }
}

/// Pure size / radius / rect math for the island.
public enum IslandLayout {
    public static let canvasSize = CGSize(width: 720, height: 320)
    public static let expandedWidth: CGFloat = 640
    /// Added below the notch height.
    public static let expandedContentHeight: CGFloat = 190
    /// A pill (non-notch displays) floats this far below the screen top.
    public static let pillTopInset: CGFloat = 6

    static let peekExtraHeight: CGFloat = 36
    static let hudExpandedExtraHeight: CGFloat = 34
    static let lyricsExtraHeight: CGFloat = 26
    static let notificationExtraHeight: CGFloat = 40

    private static func isNotification(_ activity: LiveActivity) -> Bool {
        if case .notification = activity.kind { return true }
        return false
    }

    private static func isExpandedHUD(_ activity: LiveActivity, hudStyle: HUDStyle) -> Bool {
        if case .hud = activity.kind, hudStyle == .expanded { return true }
        return false
    }

    public static func sideWidth(for p: IslandPresentation, hudStyle: HUDStyle) -> CGFloat {
        switch p {
        case .nowPlaying, .lyrics: return 44
        case .timer: return 64
        case .peek: return 110
        case .activity(let activity):
            switch activity.kind {
            case .hud: return hudStyle == .expanded ? 60 : 72
            case .charging, .lowBattery: return 64
            case .bluetooth: return 84
            case .focus: return 72
            case .calendar: return 96
            case .timerFinished: return 96
            case .notification: return 110
            case .download: return 84
            case .sensor: return 72
            case .toggle: return 64
            }
        case .idle, .expanded, .hidden:
            return 0
        }
    }

    public static func size(for p: IslandPresentation, notch: NotchMetrics, hudStyle: HUDStyle) -> CGSize {
        let top = radii(for: p, hudStyle: hudStyle).top
        let base = notch.width + 2 * top
        switch p {
        case .hidden:
            return .zero
        case .idle:
            return CGSize(width: base, height: notch.height)
        case .expanded:
            return CGSize(width: max(expandedWidth, base + 160), height: notch.height + expandedContentHeight)
        case .peek:
            let side = sideWidth(for: p, hudStyle: hudStyle)
            return CGSize(width: base + 2 * side, height: notch.height + peekExtraHeight)
        case .activity(let activity) where isExpandedHUD(activity, hudStyle: hudStyle):
            let side = sideWidth(for: p, hudStyle: hudStyle)
            return CGSize(width: base + 2 * side, height: notch.height + hudExpandedExtraHeight)
        case .activity(let activity) where isNotification(activity):
            let side = sideWidth(for: p, hudStyle: hudStyle)
            return CGSize(width: base + 2 * side, height: notch.height + notificationExtraHeight)
        case .lyrics:
            let side = sideWidth(for: p, hudStyle: hudStyle)
            return CGSize(width: base + 2 * side, height: notch.height + lyricsExtraHeight)
        case .nowPlaying, .activity, .timer:
            let side = sideWidth(for: p, hudStyle: hudStyle)
            return CGSize(width: base + 2 * side, height: notch.height)
        }
    }

    public static func radii(for p: IslandPresentation, hudStyle: HUDStyle) -> IslandRadii {
        switch p {
        case .idle, .hidden: return IslandRadii(top: 6, bottom: 9)
        case .nowPlaying, .timer: return IslandRadii(top: 6, bottom: 11)
        case .peek, .lyrics: return IslandRadii(top: 8, bottom: 16)
        case .activity(let activity):
            return isExpandedHUD(activity, hudStyle: hudStyle) || isNotification(activity)
                ? IslandRadii(top: 8, bottom: 16)
                : IslandRadii(top: 6, bottom: 11)
        case .expanded: return IslandRadii(top: 14, bottom: 28)
        }
    }

    /// Rect in canvas coordinates, origin top-left, island centred horizontally at y = 0.
    public static func canvasRect(for size: CGSize) -> CGRect {
        CGRect(x: (canvasSize.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }

    /// AppKit screen coordinates (origin bottom-left): (midX - w/2, maxY - h, w, h).
    public static func screenRect(for size: CGSize, screenFrame: CGRect, topInset: CGFloat = 0) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - topInset - size.height,
               width: size.width, height: size.height)
    }

    /// Panel frame for the canvas pinned to top-centre of `screenFrame`.
    public static func panelFrame(screenFrame: CGRect) -> CGRect {
        screenRect(for: canvasSize, screenFrame: screenFrame)
    }
}
