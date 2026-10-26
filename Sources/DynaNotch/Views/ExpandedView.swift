import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DynaNotchCore

/// Fully expanded island panel: tab header around the notch + the selected tab.
struct ExpandedView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var shelf: ShelfService

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(showsBatteries: $vm.showsBatteries)
            PanelTabBody(tab: vm.visibleTab)
                .padding(.horizontal, vm.radii.top + 14)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: vm.islandSize.width, height: vm.islandSize.height, alignment: .top)
        .overlay(batteryOverlay)
        .overlay(dropHighlight)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    @ViewBuilder
    private var batteryOverlay: some View {
        if vm.showsBatteries {
            ZStack(alignment: .topTrailing) {
                // Tap anywhere else to dismiss.
                Color.black.opacity(0.001)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { vm.showsBatteries = false } }
                DeviceBatteryCard()
                    .padding(.top, vm.notch.height + 2)
                    .padding(.trailing, vm.radii.top + 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted && settings.shelfEnabled {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal, vm.radii.top + 6)
                .padding(.top, vm.notch.height)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard settings.shelfEnabled else { return false }
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            FileURLLoader.load(from: provider) { url in
                guard let url = url else { return }
                shelf.add(urls: [url])
                vm.select(.shelf)
            }
        }
        return true
    }
}

/// Loads a file URL from a drag provider; completion on the main queue.
enum FileURLLoader {
    static func load(from provider: NSItemProvider, completion: @escaping (URL?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let direct = item as? URL {
                url = direct
            } else if let text = item as? String {
                url = URL(string: text)
            }
            DispatchQueue.main.async {
                completion(url?.isFileURL == true ? url : nil)
            }
        }
    }
}

// MARK: - Tab body

struct PanelTabBody: View {
    let tab: PanelTab

    var body: some View {
        ZStack(alignment: .top) {
            content
                .id(tab)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.15), value: tab)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home: HomeTab()
        case .nowPlaying: NowPlayingTab()
        case .timer: TimerTab()
        case .clipboard: ClipboardTab()
        case .shelf: ShelfTab()
        case .notes: NotesTab()
        case .system: SystemTab()
        case .aiUsage: AIUsageTab()
        }
    }
}
