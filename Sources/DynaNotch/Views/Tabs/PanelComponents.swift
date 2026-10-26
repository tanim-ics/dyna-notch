import SwiftUI
import AppKit
import DynaNotchCore

/// Shared styling for the expanded panel tabs.
enum PanelStyle {
    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.06)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.4)
    static let timer = Color(red: 1.0, green: 0.62, blue: 0.2)
    static let breakTime = Color(red: 0.3, green: 0.85, blue: 0.45)
    static let stopwatch = Color(red: 0.35, green: 0.62, blue: 1.0)
    static let today = Color(red: 0.25, green: 0.52, blue: 1.0)
}

/// Small uppercase section caption ("UP NEXT").
struct PanelCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(PanelStyle.tertiary)
            .lineLimit(1)
    }
}

/// Rounded dark card background.
struct PanelCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PanelStyle.cardFill)
            )
    }
}

/// Icon-only round button used across tabs.
struct PanelIconButton: View {
    let symbol: String
    var size: CGFloat = 12
    var frame: CGFloat = 22
    var tint: Color = Color.white.opacity(0.8)
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
    }
}

/// Capsule text button ("Clear", "Start").
struct PanelPillButton: View {
    let title: String
    var symbol: String?
    var tint: Color = Color.white.opacity(0.14)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol = symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Thin horizontal progress bar.
struct PanelBar: View {
    let fraction: Double
    var color: Color = .white
    var height: CGFloat = 5

    private var clamped: CGFloat {
        CGFloat(max(0, min(1, fraction.isFinite ? fraction : 0)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color).frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
    }
}

/// Centred icon + text placeholder.
struct PanelEmptyState: View {
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
            if let detail = detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Dark rounded text-field chrome.
struct PanelFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
    }
}

enum PanelKey {
    /// The panel is a non-activating NSPanel: ask the window controller to make it key so text fields get typing.
    static func request() {
        NotificationCenter.default.post(name: .dynaNotchWantsKey, object: nil)
    }
}

extension View {
    /// Makes the panel key when this view is clicked (text fields / editors).
    func requestsPanelKey() -> some View {
        simultaneousGesture(TapGesture().onEnded { PanelKey.request() })
    }

    func panelField() -> some View {
        modifier(PanelFieldBackground())
    }
}

/// Parses "#RGB", "#RRGGBB" and "#RRGGBBAA" into a SwiftUI colour.
enum HexColor {
    static func color(_ text: String) -> Color? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let r, g, b, a: Double
        if hex.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        return Color(red: r, green: g, blue: b).opacity(a)
    }
}

/// Progress ring with a track.
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress.isFinite ? progress : 0))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Timer tint by mode / phase.
enum TimerTint {
    static func color(for state: TimerState) -> Color {
        switch state.mode {
        case .stopwatch: return PanelStyle.stopwatch
        case .countdown: return PanelStyle.timer
        case .pomodoro:
            if let phase = state.phase, phase != .work { return PanelStyle.breakTime }
            return PanelStyle.timer
        }
    }

    static func title(for state: TimerState) -> String {
        switch state.mode {
        case .stopwatch: return "Stopwatch"
        case .countdown: return state.label.isEmpty ? "Timer" : state.label
        case .pomodoro: return state.phase?.title ?? "Pomodoro"
        }
    }

    /// Progress for rings; the stopwatch sweeps once a minute.
    static func ringProgress(for state: TimerState, at date: Date) -> Double {
        if state.mode == .stopwatch {
            return state.elapsed(at: date).truncatingRemainder(dividingBy: 60) / 60
        }
        return 1 - state.progress(at: date)
    }
}
