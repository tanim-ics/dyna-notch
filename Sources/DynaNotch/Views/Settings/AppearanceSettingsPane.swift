import SwiftUI
import DynaNotchCore

struct AppearanceSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    private var isGlass: Bool { settings.islandMaterial == .glass }
    private var usesPill: Bool { settings.nonNotchStyle == .pill || settings.notchDisplayStyle == .pill }

    /// Pill Width starts at the camera notch's width (185 pt on Macs without one).
    private var pillWidthRange: ClosedRange<Double> {
        let r = IslandLayout.pillWidthRange(notchWidth: ScreenLocator.physicalNotchWidth())
        return Double(r.lowerBound)...Double(r.upperBound)
    }

    /// Shows (and edits) the width actually used: a stored value below the notch reads as the notch width.
    private var pillWidthBinding: Binding<Double> {
        Binding(get: { min(max(settings.pillWidth, pillWidthRange.lowerBound), pillWidthRange.upperBound) },
                set: { settings.pillWidth = $0 })
    }

    var body: some View {
        SettingsPageView(page: .appearance) {
            islandSection
            clockSection
            panelSizeSection
            surfaceSection
            presetSection
            fillSection
            motionSection
            RestoreDefaultsSection(keys: [
                SettingsKey.islandMaterial, SettingsKey.materialPreset, SettingsKey.panelTranslucency,
                SettingsKey.closedPillClock, SettingsKey.colorCodedLevels, SettingsKey.animationStyle,
                SettingsKey.animationSpeed, SettingsKey.nonNotchStyle, SettingsKey.notchDisplayStyle, SettingsKey.showOnNonNotchDisplays,
                SettingsKey.hapticFeedback, SettingsKey.pillScale, SettingsKey.pillHeightOffset, SettingsKey.pillWidth, SettingsKey.pillHeight,
                SettingsKey.clockContent, SettingsKey.clockWithActivities, SettingsKey.panelWidth,
                SettingsKey.panelSizing, SettingsKey.panelMaxHeight, SettingsKey.panelFillHex, SettingsKey.pillMatchesPanel,
            ])
        }
    }

    private var clockSection: some View {
        Section {
            SettingRow(symbol: "calendar.badge.clock", color: .orange, title: "Clock Shows",
                       detail: "What the clock on the closed pill displays. Uses the time format from General.") {
                Picker("Clock shows", selection: $settings.clockContent) {
                    ForEach(ClockContent.allCases, id: \.self) { content in
                        Text(content.title).tag(content)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-clockContent")
            }
            SettingToggle(symbol: "rectangle.badge.plus", color: .orange, title: "Show With Activities",
                          detail: "Keep the clock visible while music, timers or popups use the pill.",
                          isOn: $settings.clockWithActivities, testID: "setting-clockWithActivities")
        } header: {
            Text("Clock")
        } footer: {
            SettingsFooter(settings.closedPillClock && usesPill
                           ? "Example: \(clockExample)"
                           : "Turn on Clock on the Closed Pill (Island Shape) to use these.")
        }
        .disabled(!(settings.closedPillClock && usesPill))
    }

    private var clockExample: String {
        let f = DateFormatter()
        let time = settings.timeFormat.template
        switch settings.clockContent {
        case .time: f.setLocalizedDateFormatFromTemplate(time)
        case .date: f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        case .timeAndDate: f.setLocalizedDateFormatFromTemplate("EEEdMMM" + time)
        }
        return f.string(from: Date())
    }

    private var isFit: Bool { settings.panelSizing == .fitContent }
    private var isCompactSize: Bool {
        settings.panelWidth == 520 && settings.panelSizing == .fixed && settings.panelMaxHeight == 190
    }
    private var isDefaultSize: Bool {
        settings.panelWidth == 640 && settings.panelSizing == .fixed && settings.panelMaxHeight == 190
    }

    private var panelSizeSection: some View {
        Section {
            SliderRow(symbol: "arrow.left.and.right", color: .blue, title: "Panel Width",
                      detail: "How wide the open panel is. Wider shows more of each tab.",
                      value: $settings.panelWidth, range: 520...820, step: 10,
                      format: { String(format: "%.0f pt", $0) }, testID: "setting-panelWidth")
            SettingRow(symbol: "rectangle.expand.vertical", color: .indigo, title: "Sizing",
                       detail: "Fixed keeps one height for every tab; Fit Content grows or shrinks with the tab.") {
                Picker("Sizing", selection: $settings.panelSizing) {
                    ForEach(PanelSizing.allCases, id: \.self) { sizing in
                        Text(sizing.title).tag(sizing)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-panelSizing")
            }
            SliderRow(symbol: "arrow.up.and.down", color: .teal,
                      title: isFit ? "Maximum Height" : "Height",
                      detail: isFit ? "The tallest the panel grows to; longer tabs scroll."
                                    : "The height of the panel below the notch.",
                      value: $settings.panelMaxHeight, range: 150...320, step: 10,
                      format: { String(format: "%.0f pt", $0) }, testID: "setting-panelMaxHeight")
            SettingRow(symbol: "rectangle.on.rectangle", color: .gray, title: "Quick Sizes",
                       detail: "Compact is 520 pt wide; Default is 640 pt. Both are Fixed and 190 pt tall.") {
                HStack(spacing: 6) {
                    Button("Use Compact Size") {
                        settings.panelWidth = 520
                        settings.panelSizing = .fixed
                        settings.panelMaxHeight = 190
                    }
                    .disabled(isCompactSize)
                    .uiTestID("setting-panelCompact")
                    Button("Use Default Size") {
                        settings.panelWidth = 640
                        settings.panelSizing = .fixed
                        settings.panelMaxHeight = 190
                    }
                    .disabled(isDefaultSize)
                    .uiTestID("setting-panelDefault")
                }
            }
        } header: {
            Text("Expanded Panel")
        }
    }

    private var hasCustomFill: Bool { !settings.panelFillHex.isEmpty }

    private var customFillBinding: Binding<Bool> {
        Binding(get: { hasCustomFill }, set: { on in
            settings.panelFillHex = on ? "#1C1C1E" : ""
            if !on { settings.pillMatchesPanel = false }
        })
    }

    private var fillColorBinding: Binding<Color> {
        Binding(get: { SettingsColorHex.color(settings.panelFillHex) ?? Color(white: 0.11) },
                set: { settings.panelFillHex = SettingsColorHex.hex($0) })
    }

    private var fillSection: some View {
        Section {
            SettingRow(symbol: "paintpalette.fill", color: .pink, title: "Custom Panel Colour",
                       detail: "Paint the open panel with your own colour instead of the material.") {
                HStack(spacing: 8) {
                    if hasCustomFill {
                        Text(settings.panelFillHex)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ColorPicker("Panel colour", selection: fillColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .uiTestID("setting-panelFillColor")
                    }
                    Toggle("", isOn: customFillBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .uiTestID("setting-panelFill")
                }
            }
            SettingToggle(symbol: "capsule.fill", color: .pink, title: "Pill Uses the Same Colour",
                          detail: "Colour the closed island too. On a notch display it then no longer blends with the notch.",
                          isOn: $settings.pillMatchesPanel, testID: "setting-pillMatchesPanel")
                .disabled(!hasCustomFill)
        } header: {
            Text("Panel Colour")
        }
    }

    private var surfaceSection: some View {
        Section {
            SettingRow(symbol: "square.on.square.intersection.dashed", color: .blue, title: "Panel Surface",
                       detail: "Glass blurs the desktop behind the open panel; Black is solid and easiest to read.") {
                Picker("Panel surface", selection: $settings.islandMaterial) {
                    ForEach(IslandMaterial.allCases, id: \.self) { material in
                        Text(material.title).tag(material)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SliderRow(symbol: "circle.lefthalf.filled", color: .cyan, title: "Panel Translucency",
                      detail: "How much of the desktop shows through the glass. Needs the Glass surface.",
                      value: $settings.panelTranslucency, range: 0...1, step: 0.05, format: SettingsFormat.percent)
                .disabled(!isGlass)
        } header: {
            Text("Glass Surfaces")
        } footer: {
            SettingsFooter("The closed island always stays black so it blends with the notch.")
        }
    }

    private var presetSection: some View {
        Section {
            ForEach(MaterialPreset.allCases, id: \.self) { preset in
                Button {
                    settings.materialPreset = preset
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(white: preset.tintWhite)
                                .opacity(max(0.25, preset.opacity(translucency: settings.panelTranslucency))))
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.6)))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15)))
                            .frame(width: 34, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.title)
                            Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.materialPreset == preset {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                    .opacity(isGlass ? 1 : 0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Material")
        } footer: {
            SettingsFooter(isGlass ? "Tints the glass panel. Click a material to use it."
                         : "Materials tint the Glass surface — switch Panel Surface to Glass to use them.")
        }
        .disabled(!isGlass)
    }

    private var islandSection: some View {
        Section {
            ShapeChoiceRow(title: "MacBook display (with notch)",
                           detail: "Merge with the camera notch, or float a pill just below it.",
                           selection: $settings.notchDisplayStyle, hasNotch: true)
            ShapeChoiceRow(title: "Other displays",
                           detail: "External monitors and Macs without a notch.",
                           selection: $settings.nonNotchStyle, hasNotch: false)
            SettingToggle(symbol: "display", color: .indigo, title: "Show on Displays Without a Notch",
                          detail: "When off, the island only appears there for activities and when you hover the top edge.",
                          isOn: $settings.showOnNonNotchDisplays)
            SettingToggle(symbol: "clock.fill", color: .orange, title: "Clock on the Closed Pill",
                          detail: "Shows the time inside the resting pill. Needs the Floating pill shape.",
                          isOn: $settings.closedPillClock, testID: "setting-closedPillClock")
                .disabled(!usesPill)
            SliderRow(symbol: "arrow.left.and.right", color: .blue, title: "Pill Width",
                      detail: "Width of the resting pill; never narrower than the MacBook's notch. Activities add to it. Needs the Floating pill shape.",
                      value: pillWidthBinding, range: pillWidthRange, step: 5,
                      format: { String(format: "%.0f pt", $0) }, testID: "setting-pillWidth")
                .disabled(!usesPill)
            SliderRow(symbol: "arrow.up.and.down.square", color: .blue, title: "Pill Height",
                      detail: "Thickness of the pill. Taller also makes the open panel's top row taller. Needs the Floating pill shape.",
                      value: $settings.pillHeight, range: 28...44, step: 1,
                      format: { String(format: "%.0f pt", $0) }, testID: "setting-pillHeight")
                .disabled(!usesPill)
            SliderRow(symbol: "capsule.fill", color: .blue, title: "Pill Content Size",
                      detail: "Scale the icons and text inside the resting pill; Pill Width and Height keep its outline. Needs the Floating pill shape.",
                      value: $settings.pillScale, range: 0.8...1.3, step: 0.05, format: SettingsFormat.percent,
                      testID: "setting-pillScale")
                .disabled(!usesPill)
            SliderRow(symbol: "arrow.up.and.down", color: .teal, title: "Pill Height Adjustment",
                      detail: "Line the pill up with your notch: move it up (−) or down (+). Needs the Floating pill shape.",
                      value: $settings.pillHeightOffset, range: -6...12, step: 1, format: SettingsFormat.signedPoints,
                      testID: "setting-pillHeightOffset")
                .disabled(!usesPill)
            SettingToggle(symbol: "slider.horizontal.below.rectangle", color: .green, title: "Color-Coded Levels",
                          detail: "Volume and brightness bars turn green, yellow or red with the level.",
                          isOn: $settings.colorCodedLevels)
        } header: {
            Text("Island Shape")
        }
    }

    private var motionSection: some View {
        Section {
            SettingRow(symbol: "wind", color: .teal, title: "Animation Style",
                       detail: "Calm glides, Snappy is quick and direct, Bouncy overshoots a little.") {
                Picker("Animation style", selection: $settings.animationStyle) {
                    ForEach(AnimationStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SliderRow(symbol: "speedometer", color: .pink, title: "Animation Speed",
                      detail: "Higher is faster. 1.0× is the default feel.",
                      value: $settings.animationSpeed, range: 0.5...2, step: 0.1, format: SettingsFormat.multiplier)
            SettingToggle(symbol: "hand.tap.fill", color: .purple, title: "Haptic Feedback",
                          detail: "A gentle trackpad tick when the island opens.",
                          isOn: $settings.hapticFeedback)
        } header: {
            Text("Motion")
        } footer: {
            SettingsFooter("Reduce Motion in System Settings → Accessibility always wins.")
        }
    }
}

/// Two visual cards (Notch · Floating pill) with a miniature screen top showing each shape.
struct ShapeChoiceRow: View {
    let title: String
    let detail: String
    @Binding var selection: NonNotchStyle
    let hasNotch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(NonNotchStyle.allCases, id: \.self) { style in
                    Button { selection = style } label: {
                        VStack(spacing: 6) {
                            ShapePreview(style: style, hasNotch: hasNotch)
                                .frame(width: 150, height: 58)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selection == style ? Color.accentColor : Color.primary.opacity(0.12),
                                                  lineWidth: selection == style ? 2.5 : 1))
                            Text(style.title)
                                .font(.callout)
                                .foregroundStyle(selection == style ? Color.primary : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .uiTestID("shape-\(hasNotch ? "notch" : "other")-\(style.rawValue)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Miniature desktop: menu bar strip, optional hardware notch, and the island in the chosen shape.
struct ShapePreview: View {
    let style: NonNotchStyle
    let hasNotch: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.6), Color(red: 0.55, green: 0.35, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 9)
            if hasNotch {
                UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                    .fill(Color.black)
                    .frame(width: 34, height: 9)
            }
            if style == .notch {
                UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7)
                    .fill(Color.black)
                    .frame(width: 62, height: 14)
            } else {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 58, height: 13)
                    .offset(y: hasNotch ? 13 : 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
