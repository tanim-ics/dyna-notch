import SwiftUI
import AppKit
import DynaNotchCore

/// Apple Shortcuts: search and run your shortcuts from the notch.
struct ShortcutsTab: View {
    @EnvironmentObject var shortcuts: ShortcutsService

    @State private var query = ""

    private var filtered: [String] { shortcuts.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { shortcuts.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Shortcuts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                if !shortcuts.shortcuts.isEmpty {
                    Text("\(shortcuts.shortcuts.count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(PanelStyle.secondary)
                }
            }
            PanelInputField(symbol: "magnifyingglass", placeholder: "Search shortcuts", text: $query,
                            onSubmit: { if let first = filtered.first { shortcuts.run(first) } })
            if shortcuts.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
            } else {
                PanelIconButton(symbol: "arrow.clockwise", size: 11, help: "Reload") { shortcuts.refresh() }
            }
            PanelIconButton(symbol: "square.on.square", size: 11, help: "Open Shortcuts") {
                shortcuts.openInShortcutsApp()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = shortcuts.loadError, shortcuts.shortcuts.isEmpty {
            PanelEmptyState(symbol: "exclamationmark.triangle", title: "Couldn’t load shortcuts", detail: error)
        } else if shortcuts.shortcuts.isEmpty {
            if shortcuts.isLoading || shortcuts.lastLoaded == nil {
                PanelEmptyState(symbol: "square.stack.3d.up", title: "Loading shortcuts…")
            } else {
                VStack(spacing: 8) {
                    PanelEmptyState(symbol: "square.stack.3d.up", title: "No shortcuts yet",
                                    detail: "Create one in the Shortcuts app")
                    PanelPillButton(title: "Open Shortcuts", symbol: "plus") { shortcuts.openInShortcutsApp() }
                }
            }
        } else if filtered.isEmpty {
            PanelEmptyState(symbol: "magnifyingglass", title: "No matches")
        } else {
            VStack(spacing: 4) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 6)], spacing: 6) {
                        ForEach(filtered, id: \.self) { name in
                            ShortcutTile(name: name)
                        }
                    }
                }
                statusLine
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let running = shortcuts.running {
            statusText("Running “\(running)”…", symbol: "hourglass", color: PanelStyle.stopwatch)
        } else if let result = shortcuts.lastResult, Date().timeIntervalSince(result.date) < 30 {
            statusText(result.success ? "“\(result.name)” · \(result.message)" : "“\(result.name)” failed · \(result.message)",
                       symbol: result.success ? "checkmark.circle.fill" : "xmark.octagon.fill",
                       color: result.success ? PanelStyle.breakTime : IslandColors.low)
        }
    }

    private func statusText(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct ShortcutTile: View {
    let name: String

    @EnvironmentObject var shortcuts: ShortcutsService
    @State private var hovering = false

    private var isRunning: Bool { shortcuts.running == name }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tileColor.opacity(0.85))
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 22, height: 22)
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if hovering && !isRunning {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(PanelStyle.secondary)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.12 : 0.06))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { shortcuts.run(name) }
        .opacity(shortcuts.running != nil && !isRunning ? 0.5 : 1)
        .help("Run “\(name)”")
        .contextMenu {
            Button("Run") { shortcuts.run(name) }
            Button("Edit in Shortcuts") { shortcuts.openInShortcutsApp(name) }
        }
    }

    /// Stable colour per shortcut name, like the Shortcuts app's tiles.
    private var tileColor: Color {
        let palette: [Color] = [.blue, .orange, .pink, .purple, .teal, .green, .indigo, .red]
        let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return palette[Int(hash % UInt32(palette.count))]
    }
}
