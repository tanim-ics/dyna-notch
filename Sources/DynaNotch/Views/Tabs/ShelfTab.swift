import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DynaNotchCore

/// File shelf: drop files on the island, drag them out again.
struct ShelfTab: View {
    @EnvironmentObject var shelf: ShelfService
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vm: IslandViewModel

    var body: some View {
        if !settings.shelfEnabled {
            VStack(spacing: 8) {
                PanelEmptyState(symbol: "tray", title: "Shelf is off", detail: "Turn it on in Settings › Productivity")
                PanelPillButton(title: "Open Settings", symbol: "gearshape") { vm.openSettings() }
            }
        } else {
            VStack(spacing: 8) {
                toolbar
                if settings.alchemyZones { AlchemyZones() }
                if shelf.items.isEmpty {
                    ShelfDropPlaceholder(retention: retentionText)
                } else {
                    tiles
                }
            }
        }
    }

    /// "Files leave after 1 day" — nil when kept until cleared.
    private var retentionText: String? {
        guard settings.shelfRetention != .untilCleared else { return nil }
        return "Files leave after \(settings.shelfRetention.title.lowercased())"
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Shelf")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("\(shelf.items.count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(PanelStyle.secondary)
            Spacer(minLength: 8)
            if let retention = retentionText, !shelf.items.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PanelStyle.tertiary)
                    Text(retention)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(PanelStyle.tertiary)
                .help("Settings › Tabs › Shelf retention")
                .accessibilityLabel("Settings › Tabs › Shelf retention")
                .uiTestID("shelfRetention")
            }
            if !shelf.items.isEmpty {
                PanelPillButton(title: "AirDrop All", symbol: "dot.radiowaves.up.forward") { shelf.airDrop(shelf.items) }
                PanelPillButton(title: "Clear", symbol: "trash") { shelf.clear() }
            }
        }
    }

    private var tiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(shelf.items) { item in
                    ShelfTile(item: item)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ShelfDropPlaceholder: View {
    var retention: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text("Drop files here")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(retention.map { "Drag them out again into any app · \($0)" } ?? "Drag them out again into any app")
                        .font(.system(size: 10))
                        .foregroundStyle(PanelStyle.tertiary)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShelfTile: View {
    let item: ShelfItem

    @EnvironmentObject var shelf: ShelfService
    @EnvironmentObject var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: shelf.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: 72, height: 26, alignment: .top)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0.04))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onDrag { dragProvider() }
        .contextMenu { menu }
        .help(shelf.url(for: item).path)
        .accessibilityLabel(shelf.url(for: item).path)
    }

    private func dragProvider() -> NSItemProvider {
        let url = shelf.url(for: item)
        if settings.shelfRemoveOnDragOut {
            // SwiftUI has no drag-ended callback: remove shortly after the drag starts.
            let captured = item
            let service = shelf
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                service.remove(captured)
            }
        }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open") { shelf.open(item) }
        Button("Reveal in Finder") { shelf.reveal(item) }
        Button("AirDrop") { shelf.airDrop([item]) }
        let url = shelf.url(for: item)
        let actions = AlchemyAction.allCases.filter { $0.accepts(fileExtension: url.pathExtension) }
        if !actions.isEmpty {
            Menu("Alchemy") {
                ForEach(actions, id: \.self) { action in
                    Button(action.detail) { AlchemyService.shared.run(action, on: url) }
                }
            }
        }
        Divider()
        Button("Remove from Shelf") { shelf.remove(item) }
    }
}

/// Drop Alchemy (CONTRACTS §6.15): drop a file on a zone to turn it into a cutout, its text, a smaller copy or a PNG.
/// Each zone is its own drop target, always on screen (nothing appears or disappears during a drag).
struct AlchemyZones: View {
    private static let zones: [AlchemyAction] = [.cutout, .text, .shrink, .png]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.zones, id: \.self) { action in
                AlchemyZone(action: action)
            }
        }
    }
}

private struct AlchemyZone: View {
    let action: AlchemyAction
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: action.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(action.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(targeted ? Color.black.opacity(0.85) : Color.white.opacity(0.8))
        .frame(maxWidth: .infinity, minHeight: 26)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(targeted ? Color.white.opacity(0.9) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .animation(.easeOut(duration: 0.12), value: targeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            for provider in files {
                FileURLLoader.load(from: provider) { url in
                    if let url = url { AlchemyService.shared.run(action, on: url) }
                }
            }
            return !files.isEmpty
        }
        .help("Drop a file here: \(action.detail.lowercased())")
        .accessibilityLabel("\(action.title) drop zone: \(action.detail)")
        .uiTestID("alchemy-\(action.rawValue)")
    }
}
