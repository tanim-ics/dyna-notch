import AppKit
import DynaNotchCore

/// Picks the screen the island lives on and measures its notch.
enum ScreenLocator {
    static func targetScreen(mode: DisplayMode) -> NSScreen? {
        let screens = NSScreen.screens
        switch mode {
        case .notchOrMain:
            if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return notched
            }
            return NSScreen.main ?? screens.first
        case .main:
            // The first screen is the one with the menu bar.
            return screens.first ?? NSScreen.main
        case .followMouse:
            return screenContainingMouse() ?? NSScreen.main ?? screens.first
        }
    }

    /// Screen under the cursor; edges inclusive so the very top row (y == maxY) still counts.
    static func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { screen in
            let f = screen.frame
            return location.x >= f.minX && location.x <= f.maxX && location.y >= f.minY && location.y <= f.maxY
        })
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        NotchMetrics.compute(screenWidth: screen.frame.width,
                             safeAreaTop: screen.safeAreaInsets.top,
                             leftAuxWidth: screen.auxiliaryTopLeftArea?.width,
                             rightAuxWidth: screen.auxiliaryTopRightArea?.width,
                             menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}
