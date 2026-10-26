import SwiftUI
import DynaNotchCore

struct HUDSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var mediaKeyTap: MediaKeyTap

    var body: some View {
        Form {
            hudSection
            statusSection
        }
        .formStyle(.grouped)
        .navigationTitle("HUD")
    }

    private var hudSection: some View {
        Section("Volume & Brightness") {
            Toggle("Show HUD in the island", isOn: $settings.hudEnabled)
                .toggleStyle(.switch)
            Toggle("Replace the system HUD", isOn: $settings.replaceSystemHUD)
                .toggleStyle(.switch)
                .disabled(!settings.hudEnabled)
            Picker("Style", selection: $settings.hudStyle) {
                ForEach(HUDStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            .disabled(!settings.hudEnabled)
            Toggle("Volume", isOn: $settings.volumeHUD)
                .toggleStyle(.switch)
                .disabled(!settings.hudEnabled)
            Toggle("Brightness", isOn: $settings.brightnessHUD)
                .toggleStyle(.switch)
                .disabled(!settings.hudEnabled)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Media keys") {
                if mediaKeyTap.isActive {
                    Label("Intercepted ✓", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                } else {
                    Label("Needs Accessibility", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                }
            }
            if !mediaKeyTap.isActive {
                Button("Open Accessibility Settings…") {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
        }
    }
}
