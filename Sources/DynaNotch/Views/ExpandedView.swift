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
            PanelHeader()
            PanelTabBody(tab: vm.visibleTab)
                .padding(.horizontal, vm.radii.top + 14)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: vm.islandSize.width, height: vm.islandSize.height, alignment: .top)
        .overlay(dropHighlight)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
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

// MARK: - Header

/// Tab icons left of the notch, quick toggles right of it.
struct PanelHeader: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings

    private static let toggleCount: CGFloat = 5
    private static let toggleSize: CGFloat = 22
    private static let toggleSpacing: CGFloat = 4

    private var horizontalPadding: CGFloat { vm.radii.top + 10 }
    private var gap: CGFloat { vm.notch.hasPhysicalNotch ? vm.notch.width + 16 : 0 }

    private var togglesWidth: CGFloat {
        PanelHeader.toggleCount * PanelHeader.toggleSize + (PanelHeader.toggleCount - 1) * PanelHeader.toggleSpacing
    }

    /// Width available to each side of the notch (or to the tabs when there is no notch).
    private var tabsWidth: CGFloat {
        let inner = vm.islandSize.width - 2 * horizontalPadding
        if vm.notch.hasPhysicalNotch {
            return max(0, (inner - gap) / 2)
        }
        return max(0, inner - togglesWidth - 12)
    }

    var body: some View {
        HStack(spacing: 0) {
            PanelTabStrip(tabs: settings.enabledTabs, width: tabsWidth)
                .frame(width: tabsWidth, alignment: .leading)
                .clipped()
            if vm.notch.hasPhysicalNotch {
                Color.clear.frame(width: gap)
            } else {
                Spacer(minLength: 12)
            }
            PanelQuickToggles(spacing: PanelHeader.toggleSpacing, size: PanelHeader.toggleSize)
                .frame(maxWidth: vm.notch.hasPhysicalNotch ? .infinity : nil, alignment: .trailing)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: vm.notch.height)
    }
}

struct PanelTabStrip: View {
    let tabs: [PanelTab]
    let width: CGFloat

    @EnvironmentObject var vm: IslandViewModel

    private let spacing: CGFloat = 2

    /// Button width shrinks to fit the available space (16…28 pt).
    private var buttonSize: CGFloat {
        let count = CGFloat(max(1, tabs.count))
        let perTab = (width - spacing * (count - 1)) / count
        return max(16, min(28, perTab.rounded(.down)))
    }

    private var iconSize: CGFloat {
        max(9, min(13, (buttonSize * 0.52).rounded()))
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(tabs, id: \.self) { tab in
                PanelTabButton(tab: tab,
                               isSelected: tab == vm.visibleTab,
                               size: buttonSize,
                               iconSize: iconSize) {
                    vm.select(tab)
                }
            }
        }
    }
}

struct PanelTabButton: View {
    let tab: PanelTab
    let isSelected: Bool
    let size: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbolName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.5))
                .frame(width: size, height: min(22, size))
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isSelected ? 0.12 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .help(tab.title)
    }
}

struct PanelQuickToggles: View {
    let spacing: CGFloat
    let size: CGFloat

    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var keepAwake: KeepAwakeService
    @EnvironmentObject var audio: AudioDeviceService

    private static let awakeTint = Color(red: 1.0, green: 0.75, blue: 0.3)

    var body: some View {
        HStack(spacing: spacing) {
            PanelIconButton(symbol: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                            size: 11, frame: size,
                            tint: keepAwake.isOn ? PanelQuickToggles.awakeTint : Color.white.opacity(0.6),
                            help: keepAwake.isOn ? "Keep Awake: On" : "Keep Awake: Off") {
                keepAwake.toggle()
            }
            PanelIconButton(symbol: audio.isMicMuted ? "mic.slash.fill" : "mic",
                            size: 11, frame: size,
                            tint: audio.isMicMuted ? IslandColors.low : Color.white.opacity(0.6),
                            help: audio.isMicMuted ? "Unmute microphone" : "Mute microphone") {
                audio.toggleMicMute()
            }
            PanelIconButton(symbol: vm.isPinned ? "pin.fill" : "pin",
                            size: 11, frame: size,
                            tint: vm.isPinned ? Color.white : Color.white.opacity(0.6),
                            help: vm.isPinned ? "Unpin panel" : "Pin panel open") {
                vm.togglePin()
            }
            PanelIconButton(symbol: "lock.fill", size: 11, frame: size,
                            tint: Color.white.opacity(0.6), help: "Lock screen") {
                ScreenLock.lock()
            }
            PanelIconButton(symbol: "gearshape.fill", size: 11, frame: size,
                            tint: Color.white.opacity(0.6), help: "Settings") {
                vm.openSettings()
            }
        }
    }
}
