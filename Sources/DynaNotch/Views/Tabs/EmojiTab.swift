import SwiftUI
import AppKit
import DynaNotchCore

/// Emoji picker: search or browse by group; click copies, ⌥-click pastes into the frontmost app.
struct EmojiTab: View {
    @EnvironmentObject var vm: IslandViewModel
    @ObservedObject private var recents = RecentEmoji.shared

    @State private var query = ""
    @State private var group: EmojiGroup = .smileys
    @State private var copied: String?

    private var results: [EmojiEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return EmojiCatalog.all.filter { $0.group == group } }
        return EmojiCatalog.search(q)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PanelInputField(symbol: "magnifyingglass", placeholder: "Search emoji", text: $query,
                                onSubmit: { if let first = results.first { pick(first.character, paste: false) } })
                groupPicker
            }
            if query.isEmpty && !recents.items.isEmpty {
                recentRow
            }
            ZStack(alignment: .bottom) {
                grid
                if let copied = copied {
                    CopiedBadge(text: "Copied \(copied)")
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var groupPicker: some View {
        HStack(spacing: 1) {
            ForEach(EmojiGroup.allCases, id: \.self) { g in
                let selected = query.isEmpty && g == group
                Button {
                    query = ""
                    group = g
                } label: {
                    Image(systemName: g.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : PanelStyle.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(selected ? 0.16 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(g.title)
            }
        }
    }

    private var recentRow: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(PanelStyle.tertiary)
                .frame(width: 14)
            ForEach(recents.items.prefix(18), id: \.self) { emoji in
                EmojiCell(character: emoji, size: 16) { paste in pick(emoji, paste: paste) }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var grid: some View {
        if results.isEmpty {
            PanelEmptyState(symbol: "face.dashed", title: "No emoji found")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 32), spacing: 2)], spacing: 2) {
                    ForEach(results) { entry in
                        EmojiCell(character: entry.character, size: 19, help: entry.name.capitalized) { paste in
                            pick(entry.character, paste: paste)
                        }
                    }
                }
            }
        }
    }

    private func pick(_ emoji: String, paste: Bool) {
        recents.add(emoji)
        if paste {
            vm.paste(ClipItem(kind: .text, text: emoji, date: Date()), plainText: true)
        } else {
            PanelPasteboard.copy(emoji)
        }
        withAnimation(.easeOut(duration: 0.15)) { copied = emoji }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copied == emoji { withAnimation { copied = nil } }
        }
    }
}

private struct EmojiCell: View {
    let character: String
    var size: CGFloat = 19
    var help: String = ""
    let action: (_ paste: Bool) -> Void

    @State private var hovering = false

    var body: some View {
        Text(character)
            .font(.system(size: size))
            .frame(width: size + 11, height: size + 9)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.14 : 0))
            )
            .scaleEffect(hovering ? 1.12 : 1)
            .animation(.easeOut(duration: 0.1), value: hovering)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { action(NSEvent.modifierFlags.contains(.option)) }
            .help(help.isEmpty ? "Click to copy · ⌥-click to paste" : "\(help) · click to copy, ⌥-click to paste")
    }
}

/// Recently used emoji (UserDefaults `dn.data.recentEmoji`).
final class RecentEmoji: ObservableObject {
    static let shared = RecentEmoji()
    private static let key = "dn.data.recentEmoji"
    private static let limit = 24

    @Published private(set) var items: [String]

    private init() {
        items = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func add(_ emoji: String) {
        var list = items.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        items = Array(list.prefix(Self.limit))
        UserDefaults.standard.set(items, forKey: Self.key)
    }
}
