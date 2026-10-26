import AppKit
import SwiftUI
import Combine
import os
import DynaNotchCore

/// Settings → Now Playing → Desktop Lyrics: a click-through floating line of synced lyrics near the bottom centre of
/// the island's screen (current line + the next one dimmed). Hidden while paused, without synced lyrics, while the
/// screen is locked / asleep and while an app is full screen.
final class DesktopLyricsController: NSObject {
    static let shared = DesktopLyricsController()

    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "desktopLyrics")
    static let panelSize = CGSize(width: 900, height: 96)
    /// Distance from the bottom of the visible frame (above the Dock).
    static let bottomMargin: CGFloat = 56

    private var panel: NSPanel?
    private var screenProvider: (() -> NSScreen?)?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// `simulate/lyrics`: show sample lines without real music until this moment.
    private(set) var demoUntil: Date?
    /// Scripted tests / state: whether the floating line is on screen.
    private(set) var isShowing = false

    private override init() {
        super.init()
    }

    func start(screenProvider: @escaping () -> NSScreen?) {
        self.screenProvider = screenProvider
        guard !started else { return }
        started = true
        UserPresence.shared.start()

        let settings = AppSettings.shared
        let triggers: [AnyPublisher<Void, Never>] = [
            settings.$desktopLyrics.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            settings.$lyricsEnabled.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NowPlayingService.shared.$snapshot.map(\.isPlaying).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            LyricsService.shared.$lines.map(\.isEmpty).removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            FullscreenDetector.shared.$isFullscreen.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)   // @Published emits before the new value is stored
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        // Lock / sleep has no publisher of its own here; a slow poll is cheap.
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
    }

    func showDemo(until: Date) {
        demoUntil = until
        update()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, until.timeIntervalSinceNow) + 0.05) { [weak self] in
            self?.update()
        }
    }

    private var isDemo: Bool { demoUntil.map { $0 > Date() } ?? false }

    private var shouldShow: Bool {
        let settings = AppSettings.shared
        guard settings.desktopLyrics, !UserPresence.shared.isAway, !FullscreenDetector.shared.isFullscreen else {
            return false
        }
        if isDemo { return true }
        return settings.lyricsEnabled && NowPlayingService.shared.snapshot.isPlaying && !LyricsService.shared.lines.isEmpty
    }

    private func update() {
        if shouldShow {
            show()
        } else if isShowing {
            panel?.orderOut(nil)
            isShowing = false
        }
    }

    private func show() {
        guard let screen = screenProvider?() ?? NSScreen.main else { return }
        let panel = self.panel ?? makePanel()
        let size = DesktopLyricsController.panelSize
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + DesktopLyricsController.bottomMargin,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !isShowing {
            panel.orderFrontRegardless()
            isShowing = true
            DesktopLyricsController.logger.debug("desktop lyrics shown")
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: DesktopLyricsController.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.title = "DynaNotch Desktop Lyrics"
        let host = NSHostingView(rootView: DesktopLyricsView()
            .environmentObject(LyricsService.shared)
            .environmentObject(NowPlayingService.shared)
            .environmentObject(AppSettings.shared))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: DesktopLyricsController.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }
}

/// Current lyric line (large) with the next one dimmed below; lyricsOffset applied like the compact line.
struct DesktopLyricsView: View {
    @EnvironmentObject var lyrics: LyricsService
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let lines = currentLines(at: context.date)
            VStack(spacing: 4) {
                Text(lines.current)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .id("c-" + lines.current)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Text(lines.next)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .id("n-" + lines.next)
                    .transition(.opacity)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .shadow(color: Color.black.opacity(0.65), radius: 6, x: 0, y: 1)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: lines.current)
        }
        .environment(\.colorScheme, .dark)
    }

    private func currentLines(at date: Date) -> (current: String, next: String) {
        if DesktopLyricsController.shared.demoUntil.map({ $0 > date }) ?? false, lyrics.lines.isEmpty {
            return ("♪ Desktop lyrics float here", "and the next line waits below")
        }
        let all = lyrics.lines
        guard !all.isEmpty else { return ("", "") }
        let t = nowPlaying.snapshot.elapsed(at: date) + settings.lyricsOffset
        guard let index = LRCParser.currentIndex(at: t, in: all) else {
            return ("♪", all.first?.text ?? "")
        }
        let current = all[index].text.isEmpty ? "♪" : all[index].text
        let next = index + 1 < all.count ? all[index + 1].text : ""
        return (current, next)
    }
}
