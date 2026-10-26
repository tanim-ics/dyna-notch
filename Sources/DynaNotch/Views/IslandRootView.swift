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
        .frame(width: vm.canvasSize.width,
               height: vm.canvasSize.height,
               alignment: .top)
        .animation(motion, value: vm.presentation)
        .animation(motion, value: vm.isHovering)
        .animation(motion, value: vm.showsTimerControls)
        .animation(motion, value: settings.pillScale)
        .animation(motion, value: settings.pillHeightOffset)
        .animation(motion, value: settings.panelWidth)
        .animation(motion, value: settings.panelMaxHeight)
        .animation(motion, value: settings.panelSizing)
        .animation(motion, value: vm.visibleTab)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Island

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : vm.motion
    }

    /// Settings → Behavior → Invisible Until Hover: the resting island fades out until the pointer arrives.
    private var restingOpacity: Double {
        vm.presentation == .idle && settings.invisibleUntilHover && !vm.isHovering ? 0 : 1
    }

    private var isExpanded: Bool { vm.presentation == .expanded }

    /// Settings → Appearance → Clock → Show with activities: on a pill (no camera housing in the middle) the clock
    /// stays in the centre of the compact row while music, timers and activities show.
    private var showsSideClock: Bool {
        settings.closedPillClock && settings.clockWithActivities && vm.isPill && !vm.notch.hasPhysicalNotch
            && vm.presentation.isCompactLike && !vm.showsTimerControls
    }

    private var shape: IslandShape {
        IslandShape(isPill: vm.isPill, topRadius: vm.radii.top, bottomRadius: vm.radii.bottom,
                    pillRowHeight: vm.notch.height)
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
        .gesture(TapGesture().onEnded {
            // Clicks inside the open panel (between controls, around the scrubber) must not collapse it;
            // collapsing is driven by mouse-leave and outside clicks (window controller).
            if !isExpanded { vm.tap() }
        }, including: vm.showsTimerControls ? .subviews : .all)   // timer controls handle their own taps
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DynaNotch")
        // Closed Pill Size scales the whole closed island (content included) from its top edge.
        .scaleEffect(hoverScale * vm.pillScale, anchor: .top)
        .opacity(restingOpacity)
        .offset(y: vm.topInset)
    }

    private var usesGlass: Bool { isExpanded && settings.islandMaterial == .glass }

    /// Settings → Appearance → Panel Fill ("" = the material preset).
    private var customFill: Color? {
        settings.panelFillHex.isEmpty ? nil : HexColor.color(settings.panelFillHex)
    }

    /// Solid fill under the content: black, or the custom fill on the black panel / a matching closed pill.
    /// On a hardware notch the notch row stays black so the island still merges with the camera housing.
    private var baseFill: AnyShapeStyle {
        guard let fill = customFill else { return AnyShapeStyle(Color.black) }
        let tinted = isExpanded ? !usesGlass : (vm.isPill && settings.pillMatchesPanel)
        guard tinted else { return AnyShapeStyle(Color.black) }
        if vm.isPill || vm.islandSize.height <= 0 { return AnyShapeStyle(fill) }
        let notchStop = min(0.95, vm.notch.height / vm.islandSize.height)
        return AnyShapeStyle(LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: notchStop),
            .init(color: fill, location: min(1, notchStop + 0.12)),
            .init(color: fill, location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }

    private var background: some View {
        ZStack {
            shape
                .fill(baseFill)
                .shadow(color: glowColor, radius: isExpanded ? 28 : 0, x: 0, y: isExpanded ? 6 : 0)
                .shadow(color: Color.black.opacity(isExpanded ? 0.45 : 0),
                        radius: isExpanded ? 18 : 0,
                        x: 0,
                        y: isExpanded ? 8 : 0)
            if usesGlass {
                IslandGlass(shape: shape, notchHeight: vm.notch.height,
                            preset: settings.materialPreset, translucency: settings.panelTranslucency,
                            customTint: customFill, blackNotchRow: !vm.isPill)
                    .transition(.opacity)
            }
        }
    }

    private var contentLayer: some View {
        ZStack(alignment: .top) {
            presentationContent
                .id(contentID)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            if showsSideClock {
                SideClock(height: vm.notch.height, width: max(0, vm.notch.width - 12))
                    .transition(.opacity)
            }
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
            IdleContent()
        case .nowPlaying:
            CompactNowPlayingView()
        case .peek:
            PeekView()
        case .activity(let activity):
            ActivityView(activity: activity)
        case .expanded:
            ExpandedView()
        case .timer:
            if vm.showsTimerControls {
                TimerControlsView()
            } else {
                CompactTimerView()
            }
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
        case .timer: return vm.showsTimerControls ? "timerControls" : "timer"
        case .lyrics: return "lyrics"
        }
    }
}

/// Island outline: the notch shape with concave ears, or a floating pill on non-notch displays.
struct IslandShape: Shape {
    var isPill: Bool
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Pill Height: a pill at least this tall rounds its ends to at least half of it, so a thick pill stays a capsule.
    var pillRowHeight: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if isPill {
            let radius = min(rect.height / 2, max(bottomRadius + 6, pillRowHeight / 2))
            // Continuous corners at half the height read as squarish ends; a full-height radius draws a true capsule.
            if radius >= rect.height / 2 { return Capsule(style: .circular).path(in: rect) }
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
        return NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
    }
}

/// Frosted "glass" for the expanded panel: the desktop blurred behind the island, darkened so white text stays
/// legible, solid black across the notch row so it still merges with the hardware notch, and a hairline highlight.
struct IslandGlass: View {
    let shape: IslandShape
    let notchHeight: CGFloat
    var preset: MaterialPreset = .carbon
    var translucency: Double = 1
    /// Settings → Appearance → Panel Fill: replaces the preset's tint colour.
    var customTint: Color? = nil
    /// Keep the notch row black (hardware notch); a floating pill has no camera housing to merge with.
    var blackNotchRow: Bool = true

    var body: some View {
        let tint = customTint ?? Color(white: preset.tintWhite)
        let opacity = customTint == nil ? preset.opacity(translucency: translucency)
            : min(1, max(0.35, preset.opacity(translucency: translucency) + 0.25))
        ZStack {
            VisualEffectBlur(material: customTint == nil && preset.tintWhite > 0.3 ? .popover : .hudWindow)
            LinearGradient(stops: [
                .init(color: blackNotchRow ? Color.black.opacity(0.95) : tint.opacity(min(1, opacity + 0.12)),
                      location: 0),
                .init(color: tint.opacity(min(1, opacity + 0.12)), location: 0.3),
                .init(color: tint.opacity(opacity), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(shape)
        .overlay(
            shape.stroke(LinearGradient(colors: [Color.white.opacity(0.02), Color.white.opacity(0.18)],
                                        startPoint: .top, endPoint: .bottom),
                         lineWidth: 0.75)
        )
        .allowsHitTesting(false)
    }
}

/// Resting island content: empty on a hardware notch; optionally a clock on the closed pill elsewhere.
struct IdleContent: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if settings.closedPillClock && !vm.notch.hasPhysicalNotch {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(ClockText.string(for: context.date, format: settings.timeFormat, content: settings.clockContent))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Color.clear
        }
    }
}

/// Small clock kept in the middle of a compact pill row (Clock → Show with activities).
struct SideClock: View {
    let height: CGFloat
    let width: CGFloat
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Text(ClockText.string(for: context.date, format: settings.timeFormat,
                                  content: settings.clockContent == .date ? .date : .time, weekday: false))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: width, height: height)
        }
        .allowsHitTesting(false)
    }
}

/// Time text honouring Settings → General → Time Format.
enum ClockText {
    /// Settings → Appearance → Clock: time, date or both ("14:32", "Mon 26 Oct", "Mon 26 Oct 14:32").
    static func string(for date: Date, format: TimeFormat, content: ClockContent, weekday: Bool = true) -> String {
        let time = timeString(for: date, format: format)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(weekday ? "EEEdMMM" : "dMMM")
        let day = formatter.string(from: date)
        switch content {
        case .time: return weekday ? string(for: date, format: format) : time
        case .date: return day
        case .timeAndDate: return day + "  " + time
        }
    }

    static func timeString(for date: Date, format: TimeFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        switch format {
        case .system: formatter.setLocalizedDateFormatFromTemplate(format.template)
        case .h24: formatter.dateFormat = "HH:mm"
        case .h12: formatter.dateFormat = "h:mm a"
        }
        return formatter.string(from: date)
    }

    static func string(for date: Date, format: TimeFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE " + format.template)
        if format != .system {
            // The template's hour letter forces 12 h / 24 h regardless of the locale default.
            formatter.dateFormat = "EEE " + (format == .h24 ? "HH:mm" : "h:mm a")
        }
        return formatter.string(from: date)
    }
}

/// `NSVisualEffectView` blending with whatever is behind the window.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
