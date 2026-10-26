import SwiftUI
import DynaNotchCore

/// Compact island row: leading content left of the notch, trailing content right of it,
/// kept inside the concave ears.
struct CompactRow<Leading: View, Trailing: View>: View {
    let notch: NotchMetrics
    let side: CGFloat
    let radii: IslandRadii
    let leadingAlignment: Alignment
    let trailingAlignment: Alignment
    let leading: Leading
    let trailing: Trailing

    init(notch: NotchMetrics,
         side: CGFloat,
         radii: IslandRadii,
         leadingAlignment: Alignment = .center,
         trailingAlignment: Alignment = .center,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.notch = notch
        self.side = side
        self.radii = radii
        self.leadingAlignment = leadingAlignment
        self.trailingAlignment = trailingAlignment
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: max(0, side), alignment: leadingAlignment)
            Spacer(minLength: notch.width)
            trailing
                .frame(width: max(0, side), alignment: trailingAlignment)
        }
        .padding(.horizontal, radii.top)
        .frame(height: notch.height)
    }
}

/// Shared island colours.
enum IslandColors {
    static let charging = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let low = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let focus = Color(red: 0.45, green: 0.45, blue: 1.0)
    static let calendar = Color(red: 1.0, green: 0.38, blue: 0.34)
    static let secondary = Color.white.opacity(0.6)
}

/// Battery SF Symbol names.
enum BatteryGlyph {
    static func name(level: Double, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        let l = max(0, min(1, level))
        if l >= 0.875 { return "battery.100percent" }
        if l >= 0.625 { return "battery.75percent" }
        if l >= 0.375 { return "battery.50percent" }
        if l >= 0.125 { return "battery.25percent" }
        return "battery.0percent"
    }
}

/// Settings → Appearance → Color-Coded Levels: volume / brightness bars go red when low, amber in between,
/// green when high; plain white otherwise.
enum LevelTint {
    static func color(for level: Double, kind: HUDKind) -> Color {
        guard AppSettings.shared.colorCodedLevels else { return .white }
        if level < 0.25 { return IslandColors.low }
        if level < 0.6 { return Color(red: 1.0, green: 0.72, blue: 0.2) }
        return IslandColors.charging
    }
}
