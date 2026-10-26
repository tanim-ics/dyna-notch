import SwiftUI
import AppKit
import DynaNotchCore

struct AboutSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            appIcon
            Text("DynaNotch 2.0")
                .font(.system(size: 22, weight: .bold))
            Text("A Dynamic Island for your Mac")
                .foregroundStyle(.secondary)
            Text("by Tanim Rayhan")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Reset all settings") { settings.resetToDefaults() }
                Button("Quit DynaNotch") { NSApp.terminate(nil) }
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .navigationTitle("About")
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 96, height: 96)
        } else {
            Image(systemName: "capsule.portrait.fill")
                .font(.system(size: 64))
        }
    }
}
