import SwiftUI
import AppKit
import DynaNotchCore

/// Clipboard history: search, pin, delete; click pastes, ⌥-click pastes plain text.
struct ClipboardTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var clipboard: ClipboardService
    @EnvironmentObject var vm: IslandViewModel

    @State private var query = ""

    private var items: [ClipItem] { clipboard.history.search(query) }

    var body: some View {
        if !settings.clipboardEnabled {
            VStack(spacing: 8) {
                PanelEmptyState(symbol: "doc.on.clipboard",
                                title: "Clipboard history is off",
                                detail: "Turn it on in Settings › Productivity")
                PanelPillButton(title: "Open Settings", symbol: "gearshape") { vm.openSettings() }
            }
        } else {
            VStack(spacing: 8) {
                header
                list
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("\(clipboard.history.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.secondary)
            }
            ClipboardSearchField(query: $query)
            PanelPillButton(title: "Clear", symbol: "trash") { clipboard.clear() }
                .disabled(clipboard.history.items.isEmpty)
        }
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            PanelEmptyState(symbol: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                            title: query.isEmpty ? "Nothing copied yet" : "No matches",
                            detail: query.isEmpty ? "Copied text, links, colours and images show up here" : nil)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { entry in
                        ClipRow(item: entry.element, index: entry.offset + 1)
                    }
                }
            }
        }
    }
}

struct ClipboardSearchField: View {
    @Binding var query: String
    @SwiftUI.FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PanelStyle.tertiary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.white)
                .focused($focused)
            if !query.isEmpty {
                Button { query = "" } label: {
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

struct ClipRow: View {
    let item: ClipItem
    let index: Int

    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var clipboard: ClipboardService
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ClipKindIcon(item: item)
            VStack(alignment: .leading, spacing: 1) {
                Text(previewText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                if let source = item.sourceApp, !source.isEmpty {
                    Text(source)
                        .font(.system(size: 9))
                        .foregroundStyle(PanelStyle.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            let plain = NSEvent.modifierFlags.contains(.option)
            vm.paste(item, plainText: plain)
        }
        .help("Click to paste · ⌥-click pastes plain text")
    }

    private var previewText: String {
        switch item.kind {
        case .image: return item.text.isEmpty ? "Image" : ClipClassifier.preview(item.text, max: 120)
        case .file:
            let paths = ClipFilePaths.all(of: item)
            let name = (filePath as NSString).lastPathComponent
            return paths.count > 1 ? "\(name) +\(paths.count - 1)" : name
        default: return ClipClassifier.preview(item.text, max: 160)
        }
    }

    private var filePath: String { ClipFilePaths.first(of: item) }

    @ViewBuilder
    private var trailing: some View {
        if hovering {
            HStack(spacing: 0) {
                PanelIconButton(symbol: item.pinned ? "pin.slash.fill" : "pin.fill", size: 10, frame: 20,
                                tint: Color.white.opacity(0.75), help: item.pinned ? "Unpin" : "Pin") {
                    clipboard.togglePin(item)
                }
                PanelIconButton(symbol: "trash", size: 10, frame: 20,
                                tint: Color.white.opacity(0.75), help: "Delete") {
                    clipboard.remove(item)
                }
            }
        } else {
            HStack(spacing: 4) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(PanelStyle.timer)
                }
                Text("\(index)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(PanelStyle.tertiary)
                    .frame(minWidth: 16, alignment: .trailing)
            }
            .frame(height: 20)
        }
    }
}

struct ClipKindIcon: View {
    let item: ClipItem

    @EnvironmentObject var clipboard: ClipboardService

    var body: some View {
        content
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .color:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(HexColor.color(item.text) ?? Color.gray)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        case .image:
            if let image = clipboard.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                symbol("photo")
            }
        case .file:
            Image(nsImage: NSWorkspace.shared.icon(forFile: filePath))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .link:
            symbol("link")
        case .text:
            symbol("text.alignleft")
        }
    }

    private var filePath: String { ClipFilePaths.first(of: item) }

    private func symbol(_ name: String) -> some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}

/// File clips store one path (or file URL) per line.
enum ClipFilePaths {
    static func all(of item: ClipItem) -> [String] {
        item.text
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                let text = String(line).trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("file://"), let url = URL(string: text) { return url.path }
                return text
            }
            .filter { !$0.isEmpty }
    }

    static func first(of item: ClipItem) -> String {
        all(of: item).first ?? item.text
    }
}
