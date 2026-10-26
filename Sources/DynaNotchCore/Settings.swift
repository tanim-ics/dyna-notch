import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum DisplayMode: String, Equatable, Hashable, CaseIterable {
    case notchOrMain, main, followMouse

    public var title: String {
        switch self {
        case .notchOrMain: return "Built-in (notch) display"
        case .main: return "Main display"
        case .followMouse: return "Follow mouse"
        }
    }
}

public enum ArtworkStyle: String, Equatable, Hashable, CaseIterable {
    case rounded, circle

    public var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .circle: return "Vinyl"
        }
    }
}

public enum VisualizerStyle: String, Equatable, Hashable, CaseIterable {
    case bars, none

    public var title: String {
        switch self {
        case .bars: return "Bars"
        case .none: return "Off"
        }
    }
}

public enum NonNotchStyle: String, Equatable, Hashable, CaseIterable {
    case notch, pill

    public var title: String {
        switch self {
        case .notch: return "Notch"
        case .pill: return "Floating pill"
        }
    }
}

/// UserDefaults keys, one per `AppSettings` property (same name), value = "dn." + name.
public enum SettingsKey {
    // General
    public static let showMenuBarIcon = "dn.showMenuBarIcon"
    public static let displayMode = "dn.displayMode"
    public static let hideInFullscreen = "dn.hideInFullscreen"
    public static let showOnNonNotchDisplays = "dn.showOnNonNotchDisplays"
    public static let hapticFeedback = "dn.hapticFeedback"
    public static let hasCompletedOnboarding = "dn.hasCompletedOnboarding"
    // Island
    public static let expandOnHover = "dn.expandOnHover"
    public static let hoverDelay = "dn.hoverDelay"
    public static let collapseDelay = "dn.collapseDelay"
    public static let clickToExpand = "dn.clickToExpand"
    public static let gesturesEnabled = "dn.gesturesEnabled"
    public static let expandedShowsCalendar = "dn.expandedShowsCalendar"
    public static let expandedShowsBattery = "dn.expandedShowsBattery"
    // Now Playing
    public static let nowPlayingEnabled = "dn.nowPlayingEnabled"
    public static let showCompactNowPlaying = "dn.showCompactNowPlaying"
    public static let showTrackPeek = "dn.showTrackPeek"
    public static let artworkStyle = "dn.artworkStyle"
    public static let visualizerStyle = "dn.visualizerStyle"
    public static let artworkGlow = "dn.artworkGlow"
    public static let pausedLingerSeconds = "dn.pausedLingerSeconds"
    // HUD
    public static let hudEnabled = "dn.hudEnabled"
    public static let replaceSystemHUD = "dn.replaceSystemHUD"
    public static let hudStyle = "dn.hudStyle"
    public static let volumeHUD = "dn.volumeHUD"
    public static let brightnessHUD = "dn.brightnessHUD"
    // Live activities
    public static let chargingActivity = "dn.chargingActivity"
    public static let lowBatteryActivity = "dn.lowBatteryActivity"
    public static let bluetoothActivity = "dn.bluetoothActivity"
    public static let focusActivity = "dn.focusActivity"
    public static let calendarActivity = "dn.calendarActivity"
    public static let calendarLeadMinutes = "dn.calendarLeadMinutes"
    public static let calendarEnabled = "dn.calendarEnabled"
    // v3: panel
    public static let nonNotchStyle = "dn.nonNotchStyle"
    public static let panelTabs = "dn.panelTabs"
    public static let rememberLastTab = "dn.rememberLastTab"
    public static let lastTab = "dn.lastTab"
    public static let hotkeysEnabled = "dn.hotkeysEnabled"
    // v3: lyrics & timer
    public static let lyricsEnabled = "dn.lyricsEnabled"
    public static let lyricsInCompact = "dn.lyricsInCompact"
    public static let pomodoroWorkMinutes = "dn.pomodoroWorkMinutes"
    public static let pomodoroShortBreakMinutes = "dn.pomodoroShortBreakMinutes"
    public static let pomodoroLongBreakMinutes = "dn.pomodoroLongBreakMinutes"
    public static let pomodoroCycles = "dn.pomodoroCycles"
    public static let timerSound = "dn.timerSound"
    public static let timerOverNowPlaying = "dn.timerOverNowPlaying"
    public static let showCompactTimer = "dn.showCompactTimer"
    // v3: clipboard, shelf, weather, AI
    public static let clipboardEnabled = "dn.clipboardEnabled"
    public static let clipboardLimit = "dn.clipboardLimit"
    public static let cleanLinks = "dn.cleanLinks"
    public static let pasteOnClick = "dn.pasteOnClick"
    public static let shelfEnabled = "dn.shelfEnabled"
    public static let shelfRemoveOnDragOut = "dn.shelfRemoveOnDragOut"
    public static let weatherEnabled = "dn.weatherEnabled"
    public static let weatherCity = "dn.weatherCity"
    public static let temperatureUnit = "dn.temperatureUnit"
    public static let aiUsageEnabled = "dn.aiUsageEnabled"
    // v3: activities
    public static let downloadActivity = "dn.downloadActivity"
    public static let privacyActivity = "dn.privacyActivity"
    public static let capsLockActivity = "dn.capsLockActivity"
    public static let notifyActivity = "dn.notifyActivity"

    public static var all: [String] {
        [
            showMenuBarIcon, displayMode, hideInFullscreen, showOnNonNotchDisplays, hapticFeedback, hasCompletedOnboarding,
            expandOnHover, hoverDelay, collapseDelay, clickToExpand, gesturesEnabled, expandedShowsCalendar,
            expandedShowsBattery,
            nowPlayingEnabled, showCompactNowPlaying, showTrackPeek, artworkStyle, visualizerStyle, artworkGlow,
            pausedLingerSeconds,
            hudEnabled, replaceSystemHUD, hudStyle, volumeHUD, brightnessHUD,
            chargingActivity, lowBatteryActivity, bluetoothActivity, focusActivity, calendarActivity,
            calendarLeadMinutes, calendarEnabled,
            nonNotchStyle, panelTabs, rememberLastTab, lastTab, hotkeysEnabled,
            lyricsEnabled, lyricsInCompact, pomodoroWorkMinutes, pomodoroShortBreakMinutes, pomodoroLongBreakMinutes,
            pomodoroCycles, timerSound, timerOverNowPlaying, showCompactTimer,
            clipboardEnabled, clipboardLimit, cleanLinks, pasteOnClick, shelfEnabled, shelfRemoveOnDragOut,
            weatherEnabled, weatherCity, temperatureUnit, aiUsageEnabled,
            downloadActivity, privacyActivity, capsLockActivity, notifyActivity,
        ]
    }
}
