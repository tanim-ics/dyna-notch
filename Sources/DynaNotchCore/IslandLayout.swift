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
    /// Unplug activity: wide enough for "On Battery" / "4 h 5 min left".
    public static let unpluggedSide: CGFloat = 100
    /// Timer controls on hover: compact timer row plus a row of buttons below the notch.
    public static let timerControlsSide: CGFloat = 64
    public static let timerControlsExtraHeight: CGFloat = 36
    /// Settings → Appearance → Closed Pill Size range.
    public static let pillScaleRange: ClosedRange<CGFloat> = 0.8...1.3

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
            case .charging(_, _, let pluggedIn): return pluggedIn ? 64 : unpluggedSide
            case .lowBattery: return 64
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

    /// Hover controls under the compact timer (pause / +1 min / stop).
    public static func timerControlsSize(notch: NotchMetrics) -> CGSize {
        let top = timerControlsRadii.top
        return CGSize(width: notch.width + 2 * top + 2 * timerControlsSide,
                      height: notch.height + timerControlsExtraHeight)
    }

    /// Same ear radius as the compact timer so its row lines up; rounder bottom like the peek.
    public static let timerControlsRadii = IslandRadii(top: 6, bottom: 16)

    /// Visible size of the closed pill scaled by Closed Pill Size (clamped to `pillScaleRange`).
    public static func scaled(_ size: CGSize, by scale: CGFloat) -> CGSize {
        let s = min(max(scale, pillScaleRange.lowerBound), pillScaleRange.upperBound)
        return CGSize(width: size.width * s, height: size.height * s)
    }

    // MARK: v3.4 panel size (Settings → Appearance → Panel)

    /// Settings → Appearance → Panel width range.
    public static let panelWidthRange: ClosedRange<CGFloat> = 520...820
    /// Settings → Appearance → Maximum panel height range (content below the notch row).
    public static let panelMaxHeightRange: ClosedRange<CGFloat> = 150...320
    /// Room around the open panel for its shadow / glow inside the canvas.
    public static let canvasMargin: CGFloat = 40

    /// Height a tab's content wants below the notch row (Fit Content); clamped by `expandedContentHeight(…)`.
    public static func preferredContentHeight(for tab: PanelTab) -> CGFloat {
        switch tab {
        case .home: return 190
        case .nowPlaying: return 176
        case .timer: return 176
        case .clipboard: return 240
        case .shelf: return 160
        case .notes: return 210
        case .calculator: return 220
        case .emoji: return 230
        case .quickSearch: return 160
        case .launcher: return 200
        case .shortcuts: return 220
        case .reminders: return 220
        case .mirror: return 230
        case .system: return 190
        case .aiUsage: return 190
        case .calendar: return 240
        case .quickSettings: return 176
        }
    }

    /// Content height below the notch row: Fixed → the maximum height; Fit Content → the tab's preferred height,
    /// never taller than the maximum. Always within `panelMaxHeightRange`.
    public static func expandedContentHeight(tab: PanelTab, sizing: PanelSizing, maxHeight: CGFloat) -> CGFloat {
        let maxH = clamp(maxHeight, panelMaxHeightRange)
        switch sizing {
        case .fixed: return maxH
        case .fitContent: return min(maxH, clamp(preferredContentHeight(for: tab), panelMaxHeightRange))
        }
    }

    /// Open panel size for a width setting and content height (width never narrower than the notch + header room).
    public static func expandedSize(notch: NotchMetrics, width: CGFloat, contentHeight: CGFloat) -> CGSize {
        let top = radii(for: .expanded, hudStyle: .compact).top
        let w = max(clamp(width, panelWidthRange), notch.width + 2 * top + 160)
        return CGSize(width: w, height: notch.height + contentHeight)
    }

    /// Canvas big enough for the widest / tallest panel the settings allow (never smaller than `canvasSize`).
    public static func canvasSize(panelWidth: CGFloat, panelMaxHeight: CGFloat, notchHeight: CGFloat) -> CGSize {
        let w = clamp(panelWidth, panelWidthRange) + 2 * canvasMargin
        let h = notchHeight + clamp(panelMaxHeight, panelMaxHeightRange) + canvasMargin
        return CGSize(width: max(canvasSize.width, ceil(w)), height: max(canvasSize.height, ceil(h)))
    }

    /// Rect in a canvas of the given size, origin top-left, island centred horizontally at y = 0.
    public static func canvasRect(for size: CGSize, canvas: CGSize) -> CGRect {
        CGRect(x: (canvas.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }

    /// Panel frame for a canvas of the given size pinned to top-centre of `screenFrame`.
    public static func panelFrame(screenFrame: CGRect, canvas: CGSize) -> CGRect {
        screenRect(for: canvas, screenFrame: screenFrame)
    }

    private static func clamp(_ v: CGFloat, _ r: ClosedRange<CGFloat>) -> CGFloat {
        min(max(v, r.lowerBound), r.upperBound)
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
