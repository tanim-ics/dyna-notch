import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import DynaNotchCore

struct AboutSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    @State private var message: String?
    @State private var caches: [AppMaintenance.CacheInfo] = AppMaintenance.caches()
    @State private var cacheMessage: String?
    @State private var uninstallStage = 0
    @State private var uninstallText = ""

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build = build, build != short { return "\(short) (\(build))" }
        return short
    }

    var body: some View {
        SettingsPageView(page: .about) {
            Section {
                HStack(spacing: 14) {
                    appIcon
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DynaNotch")
                            .font(.system(size: 20, weight: .bold))
                        Text("Version \(version)")
                            .foregroundStyle(.secondary)
                        Text("A Dynamic Island for your Mac · by Tanim Rayhan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                SettingRow(symbol: "sparkles", color: .purple, title: "Feature Tour",
                           detail: "Replay the welcome and the tips that introduce the panel.") {
                    Button("Replay") {
                        NotificationCenter.default.post(name: .dynaNotchShowWelcome, object: nil)
                    }
                }
            }
            whatsNewSection
            cachesSection
            Section {
                SettingRow(symbol: "square.and.arrow.up.fill", color: .blue, title: "Export Settings",
                           detail: "Save every setting to a JSON file, e.g. before a reset or to move to another Mac.") {
                    Button("Export…", action: exportSettings)
                }
                SettingRow(symbol: "square.and.arrow.down.fill", color: .green, title: "Import Settings",
                           detail: "Load settings from a file exported earlier. Replaces your current settings.") {
                    Button("Import…", action: importSettings)
                }
                if let message = message {
                    Label(message, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Backup")
            } footer: {
                SettingsFooter("Clipboard history, notes and the shelf are not included in the file.")
            }
            Section {
                SettingRow(symbol: "arrow.counterclockwise", color: .red, title: "Reset All Settings",
                           detail: "Every page goes back to its defaults. Export a backup first if you might want them back.") {
                    InlineConfirmButton(title: "Reset All…", confirmTitle: "Reset") {
                        settings.resetToDefaults()
                        message = "All settings were reset."
                    }
                }
                SettingRow(symbol: "power", color: .gray, title: "Quit DynaNotch",
                           detail: "Closes the island until you open the app again.") {
                    DestructiveButton(title: "Quit") { NSApp.terminate(nil) }
                }
                uninstallRow
            } header: {
                Text("Reset")
            }
        }
    }

    // MARK: What's New

    @ViewBuilder
    private var whatsNewSection: some View {
        Section {
            if AppMaintenance.whatsNew.isEmpty {
                SettingRow(symbol: "sparkles", color: .purple, title: "What's New",
                           detail: "Release notes appear here after an update.")
            } else {
                ForEach(Array(AppMaintenance.whatsNew.prefix(3).enumerated()), id: \.offset) { _, release in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(release.version)").font(.headline)
                        ForEach(Array(release.items.enumerated()), id: \.offset) { _, item in
                            Label {
                                Text(item).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "sparkle").foregroundStyle(Color.purple)
                            }
                            .font(.callout)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("What's New")
        }
    }

    // MARK: Caches

    private var cacheTotal: Int64 { caches.reduce(0) { $0 + $1.bytes } }

    private var cachesSection: some View {
        Section {
            if caches.isEmpty {
                SettingRow(symbol: "internaldrive.fill", color: .gray, title: "Caches",
                           detail: "Nothing cached right now.")
            } else {
                ForEach(caches) { cache in
                    SettingValueRow(symbol: "internaldrive.fill", color: .gray, title: cache.name,
                                    detail: "Downloaded again or rebuilt when needed.",
                                    value: Format.bytes(Double(cache.bytes)))
                }
            }
            SettingRow(symbol: "trash.fill", color: .red, title: "Clear Caches",
                       detail: cacheMessage ?? "Frees \(Format.bytes(Double(cacheTotal))). Settings, notes, clipboard history and the shelf are kept.") {
                InlineConfirmButton(title: "Clear…", confirmTitle: "Clear") {
                    let before = cacheTotal
                    AppMaintenance.clearCaches()
                    caches = AppMaintenance.caches()
                    cacheMessage = "Cleared \(Format.bytes(Double(max(0, before - cacheTotal))))."
                }
                .disabled(cacheTotal == 0)
                .uiTestID("setting-clearCaches")
            }
        } header: {
            Text("Storage")
        } footer: {
            PrivacyFooter(text: "Everything lives in ~/Library/Application Support/DynaNotch on this Mac.")
        }
        .onAppear { caches = AppMaintenance.caches() }
    }

    // MARK: Uninstall

    @ViewBuilder
    private var uninstallRow: some View {
        SettingRow(symbol: "xmark.bin.fill", color: .red, title: "Uninstall DynaNotch",
                   detail: "Removes all settings and data, the login item and the hooks DynaNotch installed, then quits. Drag DynaNotch.app to the Trash afterwards.") {
            if uninstallStage == 0 {
                DestructiveButton(title: "Uninstall…") { uninstallStage = 1 }
                    .uiTestID("setting-uninstall")
            } else {
                Button("Cancel") {
                    uninstallStage = 0
                    uninstallText = ""
                }
                .uiTestID("setting-uninstall-cancel")
            }
        }
        if uninstallStage == 1 {
            VStack(alignment: .leading, spacing: 8) {
                Label("This can't be undone. Export your settings first if you might come back.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.red)
                HStack(spacing: 8) {
                    TextField("Type UNINSTALL", text: $uninstallText, prompt: Text("Type UNINSTALL to confirm"))
                        .labelsHidden()
                        .frame(width: 220)
                        .uiTestID("setting-uninstall-text")
                    DestructiveButton(title: "Uninstall DynaNotch") {
                        AppMaintenance.uninstall()
                    }
                    .disabled(uninstallText != "UNINSTALL")
                    .uiTestID("setting-uninstall-confirm")
                }
            }
            .padding(.leading, 32)
            .padding(.vertical, 4)
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DynaNotch Settings.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportJSON().write(to: url, options: .atomic)
            message = "Exported to \(url.lastPathComponent)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            message = "Could not read \(url.lastPathComponent)."
            return
        }
        message = settings.importJSON(data)
            ? "Imported settings from \(url.lastPathComponent)."
            : "\(url.lastPathComponent) is not a DynaNotch settings file."
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 64, height: 64)
        } else {
            Image(systemName: "capsule.portrait.fill")
                .font(.system(size: 44))
        }
    }
}
