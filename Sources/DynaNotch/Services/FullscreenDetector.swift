import AppKit
import Combine
import CoreGraphics
import Foundation

/// Detects whether a normal-layer window of another app covers the whole target screen (full-screen app / video).
final class FullscreenDetector: ObservableObject {
    static let shared = FullscreenDetector()

    @Published private(set) var isFullscreen: Bool = false

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
        let value = computeFullscreen()
        if value != isFullscreen { isFullscreen = value }
    }

    private func computeFullscreen() -> Bool {
        guard let provider = screenProvider, let screen = provider() else { return false }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }

        for window in list {
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID else { continue }
            if let owner = window[kCGWindowOwnerName as String] as? String, FullscreenDetector.ignoredOwners.contains(owner) {
                continue
            }
            if let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0.01 { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if FullscreenDetector.matches(bounds, displayBounds) { return true }
        }
        return false
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
            abs(a.minY - b.minY) <= tolerance &&
            abs(a.maxX - b.maxX) <= tolerance &&
            abs(a.maxY - b.maxY) <= tolerance
    }
}
