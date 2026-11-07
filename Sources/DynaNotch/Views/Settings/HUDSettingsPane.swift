import SwiftUI
import DynaNotchCore

struct HUDSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var mediaKeyTap: MediaKeyTap

    var body: some View {
        SettingsPageView(page: .hud) {
            hudSection
            statusSection
            RestoreDefaultsSection(keys: [
                SettingsKey.hudEnabled, SettingsKey.replaceSystemHUD, SettingsKey.hudStyle,
                SettingsKey.volumeHUD, SettingsKey.brightnessHUD,
            ])
        }
    }

    private var hudSection: some View {
        Section("Volume & Brightness") {
            SettingToggle(symbol: "speaker.wave.2.fill", color: .gray, title: "Show HUD in the Island",
                          detail: "Show volume and brightness in the notch.",
                          isOn: $settings.hudEnabled)
            Group {
                SettingToggle(symbol: "rectangle.badge.xmark", color: .blue, title: "Replace the System HUD",
                              detail: "Hide the macOS overlay. Needs Accessibility.",
                              isOn: $settings.replaceSystemHUD)
                SettingRow(symbol: "rectangle.split.3x1.fill", color: .indigo, title: "Style",
                           detail: "Next to the notch, or a bar below it.") {
                    Picker("Style", selection: $settings.hudStyle) {
                        ForEach(HUDStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingToggle(symbol: "speaker.wave.3.fill", color: .gray, title: "Volume",
                              detail: "Show it for volume.",
                              isOn: $settings.volumeHUD)
                SettingToggle(symbol: "sun.max.fill", color: .yellow, title: "Brightness",
                              detail: "Show it for brightness.",
                              isOn: $settings.brightnessHUD)
            }
            .disabled(!settings.hudEnabled)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            if mediaKeyTap.isActive {
                SettingValueRow(symbol: "checkmark.circle.fill", color: .green, title: "Media Keys",
                                detail: "DynaNotch is handling your volume and brightness keys.",
                                value: "Working", valueColor: .green)
            } else {
                SettingRow(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Media Keys",
                           detail: "Without Accessibility, the macOS overlay still shows too.") {
                    Button("Allow…") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
            }
        }
    }
}
