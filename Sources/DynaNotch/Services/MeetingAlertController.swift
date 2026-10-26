import AppKit
import Combine
import Foundation
import SwiftUI
import os
import DynaNotchCore

/// Borderless full-screen window that takes keys (Esc dismisses).
private final class MeetingAlertWindow: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Full-screen "your meeting starts now — Join" alert for calendar events with a video link.
/// Watches `CalendarService.upcoming` every 15 s while `settings.meetingAlert` is on; each event alerts once.
final class MeetingAlertController {
    static let shared = MeetingAlertController()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "meetingalert")
    private var started = false
    private var timer: AnyCancellable?
    private var window: MeetingAlertWindow?
    /// "id@start" of events already alerted.
    private var shown = Set<String>()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        timer = Timer.publish(every: 15, tolerance: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in self?.check(now: now) }
        DispatchQueue.main.async { [weak self] in self?.check(now: Date()) }
    }

    /// Shows a sample alert (Settings → Calendar → Preview).
    func preview() {
        let now = Date()
        let start = now.addingTimeInterval(60)
        let sample = CalendarItem(id: "preview", title: "Design Review", start: start, end: start.addingTimeInterval(1800),
                                  isAllDay: false, location: "Zoom")
        let url = URL(string: "https://zoom.us/j/0000000000") ?? URL(fileURLWithPath: "/")
        present(sample, url: url, isPreview: true)
    }

    func dismiss() {
        guard let panel = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.close()
        })
    }

    // MARK: Private (main queue)

    private func check(now: Date) {
        let settings = AppSettings.shared
        guard settings.meetingAlert, window == nil else { return }
        let calendar = CalendarService.shared
        guard calendar.access == .granted else { return }
        let lead = TimeInterval(settings.meetingAlertMinutes) * 60
        for item in calendar.upcoming where !item.isAllDay {
            let key = "\(item.id)@\(item.start.timeIntervalSince1970)"
            guard !shown.contains(key) else { continue }
            let untilStart = item.start.timeIntervalSince(now)
            // Due within the lead time, or started less than 5 minutes ago (e.g. the Mac just woke up).
            guard untilStart <= lead, untilStart > -300, now < item.end else { continue }
            guard let url = calendar.meetingURL(for: item) else { continue }
            shown.insert(key)
            present(item, url: url, isPreview: false)
            return
        }
    }

    private func present(_ item: CalendarItem, url: URL, isPreview: Bool) {
        if window != nil { dismissImmediately() }
        guard let screen = ScreenLocator.targetScreen(mode: AppSettings.shared.displayMode) ?? NSScreen.main
                ?? NSScreen.screens.first else { return }
        let panel = MeetingAlertWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.onEscape = { [weak self] in self?.dismiss() }
        let view = MeetingAlertView(
            item: item,
            url: url,
            onJoin: { [weak self] in
                NSWorkspace.shared.open(url)
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(screen.frame, display: true)
        window = panel
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }
        if !isPreview {
            AlertSoundPlayer.play(.calendar)
        }
        logger.info("meeting alert shown (preview: \(isPreview, privacy: .public))")
    }

    private func dismissImmediately() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}
