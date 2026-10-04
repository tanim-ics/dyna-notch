import SwiftUI
import Combine

enum NotchContent: Equatable {
    case music
    case notification(NotchNotification)
    case hud(HUDType)
    case none
}

enum HUDType: Equatable {
    case volume(Float)
    case brightness(Float)
    case battery(Float, isCharging: Bool)
}

extension Notification.Name {
    static let testVolumeHUD     = Notification.Name("DynaNotch.testVolumeHUD")
    static let testBatteryHUD    = Notification.Name("DynaNotch.testBatteryHUD")
    static let testNotification  = Notification.Name("DynaNotch.testNotification")
    static let testMusicPreview  = Notification.Name("DynaNotch.testMusicPreview")
    static let toggleNotchExpand = Notification.Name("DynaNotch.toggleNotchExpand")
}

struct NotchNotification: Equatable {
    let appIcon: NSImage?
    let title:   String
    let body:    String
    let appName: String
    static func == (l: Self, r: Self) -> Bool { l.title == r.title && l.body == r.body }
}

class NotchViewModel: ObservableObject {
    @Published var isExpanded:     Bool          = false
    @Published var isTucked:       Bool          = false
    @Published var activeContent:  NotchContent  = .music
    @Published var hovering:       Bool          = false
    @Published var hasPhysicalNotch: Bool        = false
    @Published var physicalNotchWidth: CGFloat   = 185

    @AppStorage("expandOnHover")        var expandOnHover        = true
    @AppStorage("autoCollapseDelay")    var collapseDelay        = 2.0
    @AppStorage("showMusicWidget")      var showMusicWidget      = true
    @AppStorage("showVolumeHUD")        var showVolumeHUD        = true
    @AppStorage("showNotifications")    var showNotifications    = true
    @AppStorage("idleOpacity")          var idleOpacity: Double  = 0.5
    @AppStorage("displayMode")          var displayMode: String  = "focused"
    @AppStorage("clickThroughExternal") var clickThroughExternal = false

    func nextTrack() { MusicViewModel.shared.nextTrack() }
    func prevTrack() { MusicViewModel.shared.prevTrack() }
    func playPause() { MusicViewModel.shared.playPause() }

    private var collapseTimer: AnyCancellable?
    private var contentTimer:  AnyCancellable?
    private var tuckTimer:     AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.publisher(for: .testVolumeHUD)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showHUD(.volume(0.72))
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .testBatteryHUD)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showHUD(.battery(0.85, isCharging: true))
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .testNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let icon = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)
                self?.showNotification(NotchNotification(
                    appIcon: icon,
                    title: "DynaNotch Active",
                    body: "Dynamic Island is running and ready.",
                    appName: "DynaNotch"
                ))
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .toggleNotchExpand)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.toggleExpand()
            }
            .store(in: &cancellables)
    }

    // MARK: – Tuck / Quick Hide
    func tuck() {
        tuckTimer?.cancel()
        collapseTimer?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            isTucked = true
            isExpanded = false
        }
        // Auto untuck after 8 seconds
        tuckTimer = Just(())
            .delay(for: .seconds(8.0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.untuck()
            }
    }

    func untuck() {
        tuckTimer?.cancel()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
            isTucked = false
        }
    }

    func toggleTuck() {
        if isTucked { untuck() } else { tuck() }
    }

    // MARK: – Toggle
    func toggleExpand() {
        if isTucked {
            untuck()
            return
        }
        if isExpanded {
            collapse()
        } else {
            activeContent = .music
            expand(content: .music)
            scheduleCollapse(after: collapseDelay)
        }
    }

    // MARK: – Hover
    func setHovering(_ h: Bool) {
        hovering = h
        if isTucked {
            // Hovering at top edge while tucked restores after brief delay
            if h {
                untuck()
            }
            return
        }
        guard expandOnHover else { return }
        if h {
            collapseTimer?.cancel()
            expand(content: activeContent)
        } else {
            scheduleCollapse(after: collapseDelay)
        }
    }

    // MARK: – Music auto-expand
    func musicPlaybackStarted() {
        guard showMusicWidget else { return }
        guard !isExpanded else { return }
        activeContent = .music
        expand(content: .music)
        scheduleCollapse(after: 3.5)
    }

    // MARK: – HUD
    func showHUD(_ type: HUDType) {
        if case .volume = type, !showVolumeHUD { return }
        contentTimer?.cancel()
        activeContent = .hud(type)
        expand(content: .hud(type))
        contentTimer = Just(())
            .delay(for: .seconds(2.2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.hovering {
                    self.activeContent = .music
                } else {
                    self.collapse()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.activeContent = .music
                    }
                }
            }
    }

    // MARK: – Notification
    func showNotification(_ n: NotchNotification) {
        guard showNotifications else { return }
        contentTimer?.cancel()
        activeContent = .notification(n)
        expand(content: .notification(n))
        contentTimer = Just(())
            .delay(for: .seconds(4.0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.hovering {
                    self.activeContent = .music
                } else {
                    self.collapse()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.activeContent = .music
                    }
                }
            }
    }

    // MARK: – Private helpers
    private func expand(content: NotchContent) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.76)) {
            isExpanded = true
        }
    }

    func collapse() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            isExpanded = false
        }
    }

    private func scheduleCollapse(after delay: Double) {
        collapseTimer?.cancel()
        collapseTimer = Just(())
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.hovering == false else { return }
                self?.collapse()
            }
    }
}
