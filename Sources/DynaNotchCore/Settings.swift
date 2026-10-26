import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum DisplayMode: String, Equatable, Hashable, CaseIterable {
    case notchOrMain, main, external, followMouse, allDisplays

    public var title: String {
        switch self {
        case .notchOrMain: return "Built-in (notch) display"
        case .main: return "Main display"
        case .external: return "External display"
        case .followMouse: return "Follow mouse"
        case .allDisplays: return "Every display"
        }
    }

    /// Displays that get an extra island besides the primary one: every other display in `.allDisplays`
    /// (order kept, duplicates dropped), none in the single-island modes.
    public func extraDisplays(all: [UInt32], primary: UInt32?) -> [UInt32] {
        guard self == .allDisplays else { return [] }
        var seen = Set<UInt32>()
        return all.filter { $0 != primary && seen.insert($0).inserted }
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
    public static let notchDisplayStyle = "dn.notchDisplayStyle"
    public static let pillScale = "dn.pillScale"
    public static let pillHeightOffset = "dn.pillHeightOffset"
    public static let pillWidth = "dn.pillWidth"
    public static let pillHeight = "dn.pillHeight"
    public static let screenSharingPrivacy = "dn.screenSharingPrivacy"
    public static let hideWhileMirroring = "dn.hideWhileMirroring"
    public static let fullscreenScope = "dn.fullscreenScope"
    public static let autoCollapse = "dn.autoCollapse"
    public static let quietDuringFocus = "dn.quietDuringFocus"
    public static let peekOnHover = "dn.peekOnHover"
    public static let mediaKeysControlPlayer = "dn.mediaKeysControlPlayer"
    public static let preventMusicAutoLaunch = "dn.preventMusicAutoLaunch"
    public static let meetingOnlyWithLink = "dn.meetingOnlyWithLink"
    public static let hiddenCalendars = "dn.hiddenCalendars"
    public static let calendarHotkeys = "dn.calendarHotkeys"
    public static let timerHoverControls = "dn.timerHoverControls"
    public static let clipboardCaptureSound = "dn.clipboardCaptureSound"
    public static let shelfRetention = "dn.shelfRetention"
    public static let screenshotFolder = "dn.screenshotFolder"
    public static let unplugActivity = "dn.unplugActivity"
    public static let fullChargeLevel = "dn.fullChargeLevel"
    public static let clockContent = "dn.clockContent"
    public static let clockWithActivities = "dn.clockWithActivities"
    public static let panelWidth = "dn.panelWidth"
    public static let panelSizing = "dn.panelSizing"
    public static let panelMaxHeight = "dn.panelMaxHeight"
    public static let panelFillHex = "dn.panelFillHex"
    public static let pillMatchesPanel = "dn.pillMatchesPanel"
    public static let trackInfoMode = "dn.trackInfoMode"
    public static let desktopLyrics = "dn.desktopLyrics"
    public static let edgeGlow = "dn.edgeGlow"
    public static let alertSounds = "dn.alertSounds"
    public static let hotkeyBindings = "dn.hotkeyBindings"
    public static let knockEnabled = "dn.knockEnabled"
    public static let knockKey = "dn.knockKey"
    public static let knockActions = "dn.knockActions"
    public static let copyTwiceToOpen = "dn.copyTwiceToOpen"
    public static let offerCleanCopy = "dn.offerCleanCopy"
    public static let customSearchEngines = "dn.customSearchEngines"
    public static let homeCards = "dn.homeCards"
    public static let homeColumns = "dn.homeColumns"
    public static let worldClocks = "dn.worldClocks"
    public static let savedLinks = "dn.savedLinks"
    public static let repeatTimer = "dn.repeatTimer"
    public static let repeatAlarm = "dn.repeatAlarm"
    public static let pomodoroOnly = "dn.pomodoroOnly"
    public static let aiLimitWarnings = "dn.aiLimitWarnings"
    public static let aiLimitWarnPercent = "dn.aiLimitWarnPercent"
    public static let aiMenuBarReadout = "dn.aiMenuBarReadout"
    public static let aiHidePersonalInfo = "dn.aiHidePersonalInfo"
    public static let batteryInMenuBar = "dn.batteryInMenuBar"
    public static let drainWarnings = "dn.drainWarnings"
    public static let dmgInstallOffer = "dn.dmgInstallOffer"
    public static let nextMeetingInMenuBar = "dn.nextMeetingInMenuBar"
    public static let listeningHistory = "dn.listeningHistory"
    public static let defaultMusicApp = "dn.defaultMusicApp"
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
    // v3.1
    public static let islandMaterial = "dn.islandMaterial"
    public static let hasSeenWelcome = "dn.hasSeenWelcome"
    // v3.2
    public static let materialPreset = "dn.materialPreset"
    public static let panelTranslucency = "dn.panelTranslucency"
    public static let animationStyle = "dn.animationStyle"
    public static let animationSpeed = "dn.animationSpeed"
    public static let colorCodedLevels = "dn.colorCodedLevels"
    public static let closedPillClock = "dn.closedPillClock"
    public static let timeFormat = "dn.timeFormat"
    public static let helloIntro = "dn.helloIntro"
    public static let defaultTab = "dn.defaultTab"
    public static let openOnCurrentActivity = "dn.openOnCurrentActivity"
    public static let idleTimeout = "dn.idleTimeout"
    public static let invisibleUntilHover = "dn.invisibleUntilHover"
    public static let notificationDuration = "dn.notificationDuration"
    public static let lyricsOffset = "dn.lyricsOffset"
    public static let pomodoroAutoContinue = "dn.pomodoroAutoContinue"
    public static let breakLookAway = "dn.breakLookAway"
    public static let breakStandUp = "dn.breakStandUp"
    public static let standUpMinutes = "dn.standUpMinutes"
    public static let breakDrinkWater = "dn.breakDrinkWater"
    public static let drinkWaterMinutes = "dn.drinkWaterMinutes"
    public static let lowBatteryThreshold = "dn.lowBatteryThreshold"
    public static let fullChargeActivity = "dn.fullChargeActivity"
    public static let accessoryAlerts = "dn.accessoryAlerts"
    public static let clipboardIgnoredApps = "dn.clipboardIgnoredApps"
    public static let clipboardAutoClearMinutes = "dn.clipboardAutoClearMinutes"
    public static let pasteWithNumbers = "dn.pasteWithNumbers"
    public static let meetingAlert = "dn.meetingAlert"
    public static let meetingAlertMinutes = "dn.meetingAlertMinutes"
    public static let screenTimeEnabled = "dn.screenTimeEnabled"
    public static let quickSearchEngine = "dn.quickSearchEngine"
    public static let launcherApps = "dn.launcherApps"
    public static let colorFormat = "dn.colorFormat"
    public static let driveActivity = "dn.driveActivity"
    public static let screenshotToShelf = "dn.screenshotToShelf"
    public static let headerButtons = "dn.headerButtons"
    /// Bookkeeping for `PanelTab.migrate` (not a user setting, so not in `all`).
    public static let knownTabs = "dn.knownTabs"

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
            islandMaterial, hasSeenWelcome,
            materialPreset, panelTranslucency, animationStyle, animationSpeed, colorCodedLevels, closedPillClock, timeFormat, helloIntro, defaultTab, openOnCurrentActivity, idleTimeout, invisibleUntilHover, notificationDuration, lyricsOffset, pomodoroAutoContinue, breakLookAway, breakStandUp, standUpMinutes, breakDrinkWater, drinkWaterMinutes, lowBatteryThreshold, fullChargeActivity, accessoryAlerts, clipboardIgnoredApps, clipboardAutoClearMinutes, pasteWithNumbers, meetingAlert, meetingAlertMinutes, screenTimeEnabled, quickSearchEngine, launcherApps, colorFormat, driveActivity, screenshotToShelf, headerButtons, notchDisplayStyle, pillScale, pillHeightOffset, screenSharingPrivacy, hideWhileMirroring, fullscreenScope, autoCollapse, quietDuringFocus, peekOnHover, mediaKeysControlPlayer, preventMusicAutoLaunch, meetingOnlyWithLink, hiddenCalendars, calendarHotkeys, timerHoverControls, clipboardCaptureSound, shelfRetention, screenshotFolder, unplugActivity, fullChargeLevel, clockContent, clockWithActivities, panelWidth, panelSizing, panelMaxHeight, panelFillHex, pillMatchesPanel, trackInfoMode, desktopLyrics, edgeGlow, alertSounds, hotkeyBindings, knockEnabled, knockKey, knockActions, copyTwiceToOpen, offerCleanCopy, customSearchEngines, homeCards, homeColumns, worldClocks, savedLinks, repeatTimer, repeatAlarm, pomodoroOnly, aiLimitWarnings, aiLimitWarnPercent, aiMenuBarReadout, aiHidePersonalInfo, batteryInMenuBar, drainWarnings, dmgInstallOffer, nextMeetingInMenuBar, listeningHistory, defaultMusicApp, pillWidth, pillHeight,
        ]
    }
}

/// Hide in Full Screen: for every full-screen app, or only when the full-screen app is the one playing media.
public enum FullscreenScope: String, Equatable, Hashable, CaseIterable {
    case allApps, mediaApp

    public var title: String {
        switch self {
        case .allApps: return "All Apps"
        case .mediaApp: return "Playing Media App"
        }
    }
}

/// How long dropped files stay on the Shelf.
public enum ShelfRetention: String, Equatable, Hashable, CaseIterable {
    case untilCleared, hour, day, week

    public var title: String {
        switch self {
        case .untilCleared: return "Until Cleared"
        case .hour: return "1 Hour"
        case .day: return "1 Day"
        case .week: return "1 Week"
        }
    }

    /// nil = keep forever.
    public var seconds: TimeInterval? {
        switch self {
        case .untilCleared: return nil
        case .hour: return 3600
        case .day: return 86_400
        case .week: return 604_800
        }
    }

    /// Items to drop: added more than `seconds` before `now`.
    public func expired(_ items: [ShelfItem], now: Date) -> [ShelfItem] {
        guard let seconds = seconds else { return [] }
        return items.filter { now.timeIntervalSince($0.addedAt) > seconds }
    }
}
