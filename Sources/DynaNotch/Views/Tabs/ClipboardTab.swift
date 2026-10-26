import SwiftUI
import AppKit
import DynaNotchCore

/// Clipboard history: search, pin, delete; click pastes, ⌥-click pastes plain text, 1–9 pastes the n-th row.
struct ClipboardTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var clipboard: ClipboardService
    @EnvironmentObject var vm: IslandViewModel

    @State private var query = ""
    @State private var numberKeys = ClipNumberKeyMonitor()

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
            .onAppear {
                numberKeys.query = query
                numberKeys.install(vm: vm)
            }
            .onDisappear { numberKeys.remove() }
            .onChange(of: query) { numberKeys.query = query }
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
                        ClipRow(item: entry.element,
                                index: settings.pasteWithNumbers && entry.offset < 9 ? entry.offset + 1 : nil,
                                position: entry.offset)
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

/// Local key monitor: while the Clipboard tab is on screen and the panel is key, 1–9 pastes the n-th visible row
/// (ignored while a text field is being edited or with ⌘ / ⌃ / ⌥ / ⇧ held).
final class ClipNumberKeyMonitor {
    var query = ""
    private var monitor: Any?

    func install(vm: IslandViewModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak vm] event in
            guard let self = self, let vm = vm else { return event }
            return self.handle(event, vm: vm) ? nil : event
        }
    }

    func remove() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { remove() }

    private func handle(_ event: NSEvent, vm: IslandViewModel) -> Bool {
        guard AppSettings.shared.pasteWithNumbers,
              AppSettings.shared.clipboardEnabled,
              vm.presentation == .expanded, vm.selectedTab == .clipboard,
              event.window is NotchPanel else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty, !event.isARepeat else { return false }
        if event.window?.firstResponder is NSText { return false }   // typing in the search field
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let digit = Int(chars), (1...9).contains(digit) else { return false }
        let items = ClipboardService.shared.history.search(query)
        guard digit <= items.count else { return false }
        vm.paste(items[digit - 1])
        return true
    }
}

struct ClipRow: View {
    let item: ClipItem
    /// 1–9 badge for number-key pasting (nil = no badge).
    let index: Int?
    /// Row position in the list (UI-test ids).
    var position: Int = 0

    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var clipboard: ClipboardService
    @EnvironmentObject var settings: AppSettings
    @State private var hovering = false
    @State private var cleaned = false

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
            if settings.offerCleanCopy && clipboard.offersCleanCopy(for: item) {
                cleanLinkButton
            }
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
        .accessibilityLabel("Click to paste · ⌥-click pastes plain text")
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

    /// Settings › Clipboard › Offer a clean copy: the link was kept as copied; this copies it without trackers.
    @ViewBuilder
    private var cleanLinkButton: some View {
        if cleaned {
            CopiedBadge(text: "Clean copy")
        } else {
            Button {
                if clipboard.copyCleanLink(item) {
                    withAnimation(.easeOut(duration: 0.15)) { cleaned = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(.easeIn(duration: 0.2)) { cleaned = false }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Clean link")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Copy this link without tracking parameters")
            .accessibilityLabel("Copy this link without tracking parameters")
            .uiTestID("clipCleanLink.\(position)")
        }
    }

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
                if let index = index {
                    Text("\(index)")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(width: 15, height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                        .help("Press \(index) to paste")
                        .accessibilityLabel("Press \(index) to paste")
                }
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
