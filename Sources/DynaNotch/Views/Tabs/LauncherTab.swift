import SwiftUI
import AppKit
import DynaNotchCore

/// Launcher: pinned apps, running apps and a search over installed apps. Click launches; right-click pins.
struct LauncherTab: View {
    @EnvironmentObject var launcher: LauncherService
    @EnvironmentObject var vm: IslandViewModel

    @State private var query = ""

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var results: [LaunchableApp] { launcher.search(query) }

    /// Running apps that are not already pinned.
    private var runningOnly: [LaunchableApp] {
        let pinnedIDs = Set(launcher.pinned.map(\.id))
        return launcher.running.filter { !pinnedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelInputField(symbol: "magnifyingglass", placeholder: "Search applications", text: $query,
                            onSubmit: { if let first = results.first { launch(first) } })
            if isSearching {
                if results.isEmpty {
                    PanelEmptyState(symbol: "app.dashed", title: "No apps found",
                                    detail: launcher.installed.isEmpty ? "Still indexing applications…" : nil)
                } else {
                    appGrid(Array(results.prefix(40)))
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        PanelCaption(launcher.pinned.isEmpty ? "Pinned · right-click an app to pin it" : "Pinned")
                        if launcher.pinned.isEmpty {
                            Text("No pinned apps yet")
                                .font(.system(size: 10))
                                .foregroundStyle(PanelStyle.tertiary)
                                .frame(height: 20)
                        } else {
                            appGrid(launcher.pinned, scrolls: false)
                        }
                        PanelCaption("Running")
                        appGrid(runningOnly, scrolls: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { launcher.start() }
    }

    @ViewBuilder
    private func appGrid(_ apps: [LaunchableApp], scrolls: Bool = true) -> some View {
        let grid = LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 66), spacing: 4)],
                             alignment: .leading, spacing: 4) {
            ForEach(apps) { app in
                AppCell(app: app, isPinned: launcher.isPinned(app), isRunning: isRunning(app)) {
                    launch(app)
                }
            }
        }
        if scrolls {
            ScrollView(.vertical, showsIndicators: false) { grid }
        } else {
            grid
        }
    }

    private func isRunning(_ app: LaunchableApp) -> Bool {
        launcher.running.contains { $0.id == app.id }
    }

    private func launch(_ app: LaunchableApp) {
        launcher.launch(app)
        query = ""
        vm.collapse()
    }
}

private struct AppCell: View {
    let app: LaunchableApp
    let isPinned: Bool
    let isRunning: Bool
    let action: () -> Void

    @EnvironmentObject var launcher: LauncherService
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: launcher.icon(for: app))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
            Text(app.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Circle()
                .fill(Color.white.opacity(isRunning ? 0.7 : 0))
                .frame(width: 3, height: 3)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help(app.name)
        .contextMenu {
            Button("Open") { action() }
            if app.bundleID != nil {
                Button(isPinned ? "Unpin" : "Pin to Launcher") { launcher.togglePin(app) }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
    }
}
