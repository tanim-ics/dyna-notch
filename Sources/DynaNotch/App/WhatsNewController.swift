import AppKit
import Combine
import SwiftUI
import os
import DynaNotchCore

/// Borderless key panel for the story (arrows, space, Esc).
private final class StoryWindow: NSPanel {
    var onKey: ((StoryKey) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onKey?(.close)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 124, 49: onKey?(.next)        // →, space
        case 123: onKey?(.previous)        // ←
        case 36: onKey?(.confirm)          // return
        default: super.keyDown(with: event)
        }
    }
}

enum StoryKey { case next, previous, confirm, close }

/// What the story is for: the features of the version just installed, or a preview of an available update.
enum StoryMode: String {
    case whatsNew
    case update
}

struct StorySlide: Equatable {
    let feature: FeatureNote
    let version: String
}

/// Playback state of the story: which slide, how long it has played, paused while held (CONTRACTS §6.21).
final class StoryModel: ObservableObject {
    static let slideDuration: TimeInterval = 5.5

    let mode: StoryMode
    let slides: [StorySlide]
    let version: String
    let headline: String?

    @Published private(set) var index = 0
    @Published private(set) var paused = false
    /// Seconds of the current slide played before the last pause.
    @Published private(set) var playedBefore: TimeInterval = 0
    /// When the current run (since start / resume) began.
    @Published private(set) var runStart = Date()

    var onFinish: (() -> Void)?
    private var advanceItem: DispatchWorkItem?

    /// Feature slides plus the closing card.
    var count: Int { slides.count + 1 }
    var isFinal: Bool { index >= slides.count }

    init(mode: StoryMode, notes: [ReleaseNote], version: String) {
        self.mode = mode
        self.version = version
        headline = notes.first?.headline
        slides = notes.flatMap { note in note.features.map { StorySlide(feature: $0, version: note.version) } }
    }

    func elapsed(at date: Date) -> TimeInterval {
        paused ? playedBefore : playedBefore + date.timeIntervalSince(runStart)
    }

    func start() { go(to: 0) }

    func go(to target: Int) {
        index = min(max(0, target), count - 1)
        playedBefore = 0
        paused = false
        runStart = Date()
        scheduleAdvance()
    }

    func next() {
        if isFinal {
            if mode == .whatsNew { onFinish?() }
        } else {
            go(to: index + 1)
        }
    }

    func previous() { go(to: index - 1) }

    func setPaused(_ pause: Bool) {
        guard pause != paused else { return }
        if pause {
            playedBefore += Date().timeIntervalSince(runStart)
            advanceItem?.cancel()
        } else {
            runStart = Date()
            scheduleAdvance()
        }
        paused = pause
    }

    func stop() {
        advanceItem?.cancel()
        advanceItem = nil
    }

    /// Feature slides move on by themselves; the closing card waits for a button.
    private func scheduleAdvance() {
        advanceItem?.cancel()
        guard !isFinal else { return }
        let item = DispatchWorkItem { [weak self] in self?.next() }
        advanceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, StoryModel.slideDuration - playedBefore), execute: item)
    }
}

/// The What's New / Update story as an island pop-up out of the notch (like the welcome).
final class WhatsNewController: NSObject {
    static let shared = WhatsNewController()

    static let lastSeenKey = "dn.data.lastSeenVersion"

    private var window: StoryWindow?
    private(set) var model: StoryModel?
    private let closer = WelcomeCloser()
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "whatsnew")

    private override init() {
        super.init()
    }

    var isShown: Bool { window != nil }
    var testWindow: NSWindow? { window }

    var state: [String: Any] {
        [
            "shown": isShown,
            "mode": model?.mode.rawValue ?? "",
            "index": model?.index ?? -1,
            "count": model?.count ?? 0,
            "paused": model?.paused ?? false,
            "title": model.flatMap { $0.isFinal ? "final" : $0.slides[$0.index].feature.title } ?? "",
        ]
    }

    /// Release notes shipped inside this app (`Contents/Resources/WhatsNew.json`).
    static var bundledNotes: [ReleaseNote] {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return ReleaseNotes.decode(data)
    }

    /// At launch: play the story once when this version is newer than the last one the user saw.
    func showIfUpdated(delay: TimeInterval) {
        let defaults = UserDefaults.standard
        let current = UpdateService.currentVersion
        let lastSeen = defaults.string(forKey: WhatsNewController.lastSeenKey)
        let show = UpdateCheck.shouldShowWhatsNew(lastSeen: lastSeen, current: current,
                                                  hasSeenWelcome: AppSettings.shared.hasSeenWelcome)
        let notes = ReleaseNotes.between(WhatsNewController.bundledNotes, after: lastSeen, upTo: current)
        // A fresh install sees the welcome instead; remember the version either way.
        defaults.set(current, forKey: WhatsNewController.lastSeenKey)
        guard show, !notes.isEmpty else { return }
        logger.info("updated from \(lastSeen ?? "?", privacy: .public) to \(current, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.waitForWelcome { self?.present(mode: .whatsNew, notes: notes, version: current) }
        }
    }

    /// Settings / menu / hook: the story of the installed version.
    func showCurrent() {
        let current = UpdateService.currentVersion
        var notes = ReleaseNotes.between(WhatsNewController.bundledNotes, after: nil, upTo: current)
        if notes.isEmpty { notes = Array(WhatsNewController.bundledNotes.prefix(1)) }
        guard !notes.isEmpty else { return }
        present(mode: .whatsNew, notes: notes, version: current)
    }

    /// The Update button: what the available version brings, ending with "Update Now".
    func showUpdate() {
        let service = UpdateService.shared
        guard let update = service.update else {
            service.checkNow()
            return
        }
        present(mode: .update, notes: service.updateNotes, version: update.version)
    }

    func handle(_ key: StoryKey) {
        guard let model = model else { return }
        switch key {
        case .next: model.next()
        case .previous: model.previous()
        case .close: closer.close?()
        case .confirm:
            if model.isFinal, model.mode == .update { UpdateService.shared.install() } else { model.next() }
        }
    }

    /// Debug (`dynanotch://snapshot-whatsnew/<name>`).
    func snapshot(to url: URL) {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    // MARK: Private

    /// The hello / tips own the notch first.
    private func waitForWelcome(attempt: Int = 0, then action: @escaping () -> Void) {
        if WelcomeController.shared.testWindow != nil, attempt < 60 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.waitForWelcome(attempt: attempt + 1, then: action)
            }
        } else {
            action()
        }
    }

    private func present(mode: StoryMode, notes: [ReleaseNote], version: String) {
        if window != nil { finish() }
        guard let screen = ScreenLocator.targetScreen(mode: AppSettings.shared.displayMode) else { return }
        let measured = ScreenLocator.metrics(for: screen)
        let notch = measured.hasPhysicalNotch ? measured
            : NotchMetrics(width: NotchMetrics.fallback.width, height: max(24, measured.height), hasPhysicalNotch: false)
        let size = WhatsNewStoryView.canvasSize(notch: notch)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = StoryWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let story = StoryModel(mode: mode, notes: notes, version: version)
        story.onFinish = { [weak self] in self?.closer.close?() }
        model = story
        panel.contentView = NSHostingView(rootView: WhatsNewStoryView(notch: notch, model: story, closer: closer) {
            [weak self] in self?.finish()
        }
        .environmentObject(UpdateService.shared))
        panel.onKey = { [weak self] key in self?.handle(key) }
        window = panel
        logger.info("story \(mode.rawValue, privacy: .public) for \(version, privacy: .public), \(story.slides.count) slides")
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        model?.stop()
        model = nil
        window?.orderOut(nil)
        window = nil
        closer.close = nil
        UserDefaults.standard.set(UpdateService.currentVersion, forKey: WhatsNewController.lastSeenKey)
    }
}
