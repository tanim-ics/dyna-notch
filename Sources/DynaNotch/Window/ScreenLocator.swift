import AppKit
import DynaNotchCore

/// Picks the screen the island lives on and measures its notch.
enum ScreenLocator {
    static func targetScreen(mode: DisplayMode) -> NSScreen? {
        let screens = NSScreen.screens
        switch mode {
        case .allDisplays:
            // The primary island goes to the notch display, else the main one — unless that display is switched off.
            let allowed = Set(DisplaySelection.allowed(screens.compactMap(ScreenLocator.keyed),
                                                       hidden: DisplaySelection.parse(AppSettings.shared.hiddenDisplays)))
            let ordered = screens.filter { $0.safeAreaInsets.top > 0 } + screens   // screens.first = menu-bar display
            return ordered.first(where: { ScreenLocator.displayID($0).map(allowed.contains) ?? false })
                ?? NSScreen.main ?? screens.first
        case .notchOrMain:
            if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notched
            }
            return NSScreen.main ?? screens.first
        case .main:
            // The first screen is the one with the menu bar.
            return screens.first ?? NSScreen.main
        case .external:
            // First display without a notch that isn't the built-in panel; else the main display.
            if let external = screens.first(where: { !ScreenLocator.isBuiltIn($0) }) { return external }
            return screens.first ?? NSScreen.main
        case .followMouse:
            return screenContainingMouse() ?? NSScreen.main ?? screens.first
        }
    }

    /// CoreGraphics display ID of a screen (nil for a screen without one).
    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Stable name of a display for Show On → Every display (survives reconnects and display-ID changes).
    static func displayKey(_ screen: NSScreen) -> String? {
        guard let id = displayID(screen) else { return nil }
        return DisplaySelection.key(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                    serial: CGDisplaySerialNumber(id))
    }

    static func keyed(_ screen: NSScreen) -> (id: UInt32, key: String)? {
        guard let id = displayID(screen), let key = displayKey(screen) else { return nil }
        return (id, key)
    }

    static func screen(displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first(where: { ScreenLocator.displayID($0) == displayID })
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    /// Screen under the cursor; edges inclusive so the very top row (y == maxY) still counts.
    static func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { screen in
            let f = screen.frame
            return location.x >= f.minX && location.x <= f.maxX && location.y >= f.minY && location.y <= f.maxY
        })
    }

    /// Width of the camera notch on the first notched screen (any screen, so a pill on an external display matches
    /// the MacBook's notch), else `NotchMetrics.fallback.width`.
    static func physicalNotchWidth() -> CGFloat {
        guard let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            return NotchMetrics.fallback.width
        }
        return metrics(for: notched).width
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        NotchMetrics.compute(screenWidth: screen.frame.width,
                             safeAreaTop: screen.safeAreaInsets.top,
                             leftAuxWidth: screen.auxiliaryTopLeftArea?.width,
                             rightAuxWidth: screen.auxiliaryTopRightArea?.width,
                             menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}
