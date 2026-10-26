import SwiftUI
import AppKit
import DynaNotchCore

/// Root of the notch panel: fills the fixed canvas and draws the island at top-centre.
struct IslandRootView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if vm.presentation != .hidden {
                island
            }
        }
        .frame(width: IslandLayout.canvasSize.width,
               height: IslandLayout.canvasSize.height,
               alignment: .top)
        .animation(motion, value: vm.presentation)
        .animation(motion, value: vm.isHovering)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Island

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    private var isExpanded: Bool { vm.presentation == .expanded }

    private var shape: IslandShape {
        IslandShape(isPill: vm.isPill, topRadius: vm.radii.top, bottomRadius: vm.radii.bottom)
    }

    private var hoverScale: CGFloat {
        vm.isHovering && vm.presentation == .idle ? 1.06 : 1
    }

    private var glowColor: Color {
        let show = isExpanded && settings.artworkGlow && nowPlaying.artwork != nil
        return show ? Color(nsColor: nowPlaying.accentColor).opacity(0.35) : Color.clear
    }

    private var island: some View {
        ZStack(alignment: .top) {
            background
            contentLayer
        }
        .frame(width: vm.islandSize.width, height: vm.islandSize.height)
        .contentShape(shape)
        .onTapGesture {
            // Clicks inside the open panel (between controls, around the scrubber) must not collapse it;
            // collapsing is driven by mouse-leave and outside clicks (window controller).
            if !isExpanded { vm.tap() }
        }
        .scaleEffect(hoverScale, anchor: .top)
        .offset(y: vm.topInset)
    }

    private var background: some View {
        shape
            .fill(Color.black)
            .shadow(color: glowColor, radius: isExpanded ? 28 : 0, x: 0, y: isExpanded ? 6 : 0)
            .shadow(color: Color.black.opacity(isExpanded ? 0.45 : 0),
                    radius: isExpanded ? 18 : 0,
                    x: 0,
                    y: isExpanded ? 8 : 0)
    }

    private var contentLayer: some View {
        ZStack(alignment: .top) {
            presentationContent
                .id(contentID)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        }
        .frame(width: vm.islandSize.width, height: vm.islandSize.height, alignment: .top)
        .clipShape(shape)
    }

    @ViewBuilder
    private var presentationContent: some View {
        switch vm.presentation {
        case .hidden:
            EmptyView()
        case .idle:
            Color.clear
        case .nowPlaying:
            CompactNowPlayingView()
        case .peek:
            PeekView()
        case .activity(let activity):
            ActivityView(activity: activity)
        case .expanded:
            ExpandedView()
        case .timer:
            CompactTimerView()
        case .lyrics:
            LyricsCompactView()
        }
    }

    /// Stable identity per presentation case; activities keyed by category so HUD updates do not re-transition.
    private var contentID: String {
        switch vm.presentation {
        case .hidden: return "hidden"
        case .idle: return "idle"
        case .nowPlaying: return "nowPlaying"
        case .peek: return "peek"
        case .activity(let activity):
            if case .hud = activity.kind {
                return "activity-hud-\(settings.hudStyle.rawValue)"
            }
            return "activity-\(activity.kind.category.rawValue)"
        case .expanded: return "expanded"
        case .timer: return "timer"
        case .lyrics: return "lyrics"
        }
    }
}

/// Island outline: the notch shape with concave ears, or a floating pill on non-notch displays.
struct IslandShape: Shape {
    var isPill: Bool
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if isPill {
            let radius = min(rect.height / 2, bottomRadius + 6)
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
        return NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
    }
}
