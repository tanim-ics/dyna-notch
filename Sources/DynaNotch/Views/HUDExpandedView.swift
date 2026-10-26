import SwiftUI
import DynaNotchCore

/// HUD symbol names shared by compact and expanded HUD styles.
enum HUDSymbol {
    static func name(kind: HUDKind, level: Double, muted: Bool) -> String {
        switch kind {
        case .volume:
            if muted || level <= 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }

    static func displayLevel(level: Double, muted: Bool) -> Double {
        muted ? 0 : max(0, min(1, level))
    }
}

/// HUD in "expanded" style: icon · bar · percent in a row below the notch.
struct HUDExpandedView: View {
    let kind: HUDKind
    let level: Double
    let muted: Bool
    let notch: NotchMetrics

    private var shown: Double { HUDSymbol.displayLevel(level: level, muted: muted) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: notch.height)
            HStack(spacing: 10) {
                Image(systemName: HUDSymbol.name(kind: kind, level: level, muted: muted))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20)
                LevelBar(level: shown, color: LevelTint.color(for: shown, kind: kind))
                    .frame(height: 6)
                Text(Format.percent(shown))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: 34)
        }
    }
}
