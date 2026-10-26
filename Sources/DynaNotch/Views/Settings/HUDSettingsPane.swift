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
                          detail: "Volume and brightness levels appear in the notch when they change.",
                          isOn: $settings.hudEnabled)
            Group {
                SettingToggle(symbol: "rectangle.badge.xmark", color: .blue, title: "Replace the System HUD",
                              detail: "Hide macOS's own volume / brightness overlay. Needs Accessibility.",
                              isOn: $settings.replaceSystemHUD)
                SettingRow(symbol: "rectangle.split.3x1.fill", color: .indigo, title: "Style",
                           detail: "Compact sits beside the notch; Expanded shows a bar below it.") {
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
                              detail: "Show the HUD for volume and mute.",
                              isOn: $settings.volumeHUD)
                SettingToggle(symbol: "sun.max.fill", color: .yellow, title: "Brightness",
                              detail: "Show the HUD for display brightness.",
                              isOn: $settings.brightnessHUD)
            }
            .disabled(!settings.hudEnabled)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            if mediaKeyTap.isActive {
                SettingValueRow(symbol: "checkmark.circle.fill", color: .green, title: "Media Keys",
                                detail: "Volume and brightness keys are handled by DynaNotch.",
                                value: "Working", valueColor: .green)
            } else {
                SettingRow(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Media Keys",
                           detail: "Without Accessibility DynaNotch only observes changes and the system HUD still shows.") {
                    Button("Allow…") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
            }
        }
    }
}
