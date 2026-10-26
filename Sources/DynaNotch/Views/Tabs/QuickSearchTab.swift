import SwiftUI
import AppKit
import DynaNotchCore

/// Quick Search: type a query (or "gh swiftui", or a URL) and press Return to open it in the browser.
struct QuickSearchTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vm: IslandViewModel
    @ObservedObject private var recents = RecentSearches.shared

    @State private var query = ""

    /// Built-ins plus Settings → Quick Search custom engines; a custom engine replaces a built-in with the same id or shortcut.
    private var engines: [SearchEngine] {
        let custom = JSONList.decode(settings.customSearchEngines, as: SearchEngine.self)
            .filter { !$0.name.isEmpty && $0.template.contains("%@") }
        let ids = Set(custom.map(\.id))
        let shortcuts = Set(custom.map { $0.shortcut.lowercased() }.filter { !$0.isEmpty })
        return QuickSearch.builtIn.filter { !ids.contains($0.id) && !shortcuts.contains($0.shortcut.lowercased()) } + custom
    }

    private var resolution: QuickSearch.Resolution? {
        QuickSearch.resolve(query, engines: engines, defaultEngineID: settings.quickSearchEngine)
    }

    private var defaultEngine: SearchEngine {
        engines.first(where: { $0.id == settings.quickSearchEngine }) ?? engines[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelInputField(symbol: resolution?.engine?.symbol ?? (resolution == nil ? defaultEngine.symbol : "globe"),
                            placeholder: "Search \(defaultEngine.name), or type “gh swiftui”, “yt lofi”, a URL…",
                            text: $query,
                            fontSize: 13,
                            onSubmit: { open(resolution?.url) })
            hint
            PanelCaption("Engines · click to search, or set the default when empty")
            engineChips
            if !recents.items.isEmpty {
                recentRow
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var hint: some View {
        HStack(spacing: 6) {
            if let r = resolution {
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PanelStyle.tertiary)
                Text(r.engine.map { "Search \($0.name) for “\(r.query)”" } ?? "Open \(r.url.host ?? r.url.absoluteString)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(r.url.host ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.tertiary)
                    .lineLimit(1)
            } else {
                Text("Shortcuts: " + engines.map { "\($0.shortcut) \($0.name)" }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(height: 16)
    }

    private var engineChips: some View {
        let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(engines) { engine in
                EngineChip(engine: engine, isDefault: engine.id == settings.quickSearchEngine) {
                    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        settings.quickSearchEngine = engine.id
                    } else {
                        open(engine.url(for: text))
                    }
                }
            }
        }
    }

    private var recentRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PanelStyle.tertiary)
            ForEach(recents.items.prefix(5), id: \.self) { text in
                Button {
                    query = text
                    open(QuickSearch.resolve(text, engines: engines, defaultEngineID: settings.quickSearchEngine)?.url)
                } label: {
                    Text(text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            Spacer(minLength: 0)
            Button("Clear") { recents.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(PanelStyle.tertiary)
        }
    }

    private func open(_ url: URL?) {
        guard let url = url else { return }
        recents.add(query.trimmingCharacters(in: .whitespacesAndNewlines))
        NSWorkspace.shared.open(url)
        query = ""
        vm.collapse()
    }
}

private struct EngineChip: View {
    let engine: SearchEngine
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: engine.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                Text(engine.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(engine.shortcut)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelStyle.tertiary)
            }
            .foregroundStyle(isDefault ? Color.white : Color.white.opacity(0.8))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule().fill(Color.white.opacity(isDefault ? 0.18 : 0.07))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(isDefault ? 0.25 : 0), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .help(isDefault ? "\(engine.name) (default)" : engine.name)
    }
}

/// Last few Quick Search queries (UserDefaults `dn.data.recentSearches`).
final class RecentSearches: ObservableObject {
    static let shared = RecentSearches()
    private static let key = "dn.data.recentSearches"

    @Published private(set) var items: [String]

    private init() {
        items = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func add(_ text: String) {
        guard !text.isEmpty else { return }
        var list = items.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        list.insert(text, at: 0)
        items = Array(list.prefix(8))
        UserDefaults.standard.set(items, forKey: Self.key)
    }

    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

// MARK: - Shared tab input helpers (used by the v3.2 tool tabs)

/// Single-line field with an icon that makes the panel key when focused; Return calls `onSubmit`.
struct PanelInputField: View {
    let symbol: String
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 11
    var monospaced: Bool = false
    var onSubmit: () -> Void = {}

    @SwiftUI.FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: fontSize - 1, weight: .semibold))
                .foregroundStyle(PanelStyle.tertiary)
                .frame(width: fontSize + 3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(monospaced ? .system(size: fontSize, design: .monospaced) : .system(size: fontSize))
                .foregroundStyle(Color.white)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(PanelStyle.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .panelField()
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .requestsPanelKey()
        .onChange(of: focused) {
            if focused { PanelKey.request() }
        }
    }
}

enum PanelPasteboard {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

/// Small "Copied" capsule shown briefly after a copy.
struct CopiedBadge: View {
    var text: String = "Copied"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.green.opacity(0.55)))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
