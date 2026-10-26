import AppKit
import Combine
import CoreGraphics
import Foundation

/// Detects whether a normal-layer window of another app covers the whole target screen (full-screen app / video).
final class FullscreenDetector: ObservableObject {
    static let shared = FullscreenDetector()

    @Published private(set) var isFullscreen: Bool = false
    /// Every display covered by another app's full-screen window (Show On → Every display: each island checks its own).
    @Published private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []

    private var screenProvider: (() -> NSScreen?)?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let ignoredOwners: Set<String> = ["Dock", "Window Server", "Finder"]
    private static let tolerance: CGFloat = 2

    private init() {}

    func start(screenProvider: @escaping () -> NSScreen?) {
        self.screenProvider = screenProvider
        guard observers.isEmpty else {
            evaluate()
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: OperationQueue.main) { [weak self] _ in
                self?.evaluate()
                // Space-switch animations finish a little later.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.evaluate() }
            }
            observers.append(token)
        }
        // App / Space switches (entering full screen creates a Space) drive this; the poll is only a safety net.
        Timer.publish(every: 10, tolerance: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
        evaluate()
    }

    // MARK: Private (main queue)

    private func evaluate() {
        let displays = computeFullscreenDisplays()
        if displays != fullscreenDisplays { fullscreenDisplays = displays }
        let target = screenProvider?().flatMap { ScreenLocator.displayID($0) }
        let value = target.map { displays.contains($0) } ?? false
        if value != isFullscreen { isFullscreen = value }
    }

    /// One window-list pass for all displays.
    private func computeFullscreenDisplays() -> Set<CGDirectDisplayID> {
        let displays: [(CGDirectDisplayID, CGRect)] = NSScreen.screens.compactMap { screen in
            guard let id = ScreenLocator.displayID(screen) else { return nil }
            let b = CGDisplayBounds(id)
            return b.width > 0 && b.height > 0 ? (id, b) : nil
        }
        guard !displays.isEmpty else { return [] }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        var result = Set<CGDirectDisplayID>()
        for window in list {
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID else { continue }
            if let owner = window[kCGWindowOwnerName as String] as? String, FullscreenDetector.ignoredOwners.contains(owner) {
                continue
            }
            if let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0.01 { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            for (id, displayBounds) in displays where FullscreenDetector.matches(bounds, displayBounds) {
                result.insert(id)
            }
        }
        return result
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
            abs(a.minY - b.minY) <= tolerance &&
            abs(a.maxX - b.maxX) <= tolerance &&
            abs(a.maxY - b.maxY) <= tolerance
    }
}
