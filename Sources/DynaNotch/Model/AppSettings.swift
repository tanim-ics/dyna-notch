import Foundation
import Combine
import DynaNotchCore

/// UserDefaults-backed user preferences (CLAUDE.md §6.2).
/// Every property persists itself in `didSet`; enums are stored as their raw value.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: General

    @Published var showMenuBarIcon: Bool = true {
        didSet { defaults.set(showMenuBarIcon, forKey: SettingsKey.showMenuBarIcon) }
    }
    @Published var displayMode: DisplayMode = .notchOrMain {
        didSet { defaults.set(displayMode.rawValue, forKey: SettingsKey.displayMode) }
    }
    @Published var hideInFullscreen: Bool = true {
        didSet { defaults.set(hideInFullscreen, forKey: SettingsKey.hideInFullscreen) }
    }
    @Published var showOnNonNotchDisplays: Bool = true {
        didSet { defaults.set(showOnNonNotchDisplays, forKey: SettingsKey.showOnNonNotchDisplays) }
    }
    @Published var hapticFeedback: Bool = true {
        didSet { defaults.set(hapticFeedback, forKey: SettingsKey.hapticFeedback) }
    }
    @Published var hasCompletedOnboarding: Bool = false {
        didSet { defaults.set(hasCompletedOnboarding, forKey: SettingsKey.hasCompletedOnboarding) }
    }

    // MARK: Island

    @Published var expandOnHover: Bool = true {
        didSet { defaults.set(expandOnHover, forKey: SettingsKey.expandOnHover) }
    }
    @Published var hoverDelay: Double = 0.15 {
        didSet {
            let clamped = AppSettings.clamp(hoverDelay, 0, 1)
            if clamped != hoverDelay { hoverDelay = clamped }
            defaults.set(hoverDelay, forKey: SettingsKey.hoverDelay)
        }
    }
    @Published var collapseDelay: Double = 0.35 {
        didSet {
            let clamped = AppSettings.clamp(collapseDelay, 0, 2)
            if clamped != collapseDelay { collapseDelay = clamped }
            defaults.set(collapseDelay, forKey: SettingsKey.collapseDelay)
        }
    }
    @Published var clickToExpand: Bool = true {
        didSet { defaults.set(clickToExpand, forKey: SettingsKey.clickToExpand) }
    }
    @Published var gesturesEnabled: Bool = true {
        didSet { defaults.set(gesturesEnabled, forKey: SettingsKey.gesturesEnabled) }
    }
    @Published var expandedShowsCalendar: Bool = true {
        didSet { defaults.set(expandedShowsCalendar, forKey: SettingsKey.expandedShowsCalendar) }
    }
    @Published var expandedShowsBattery: Bool = true {
        didSet { defaults.set(expandedShowsBattery, forKey: SettingsKey.expandedShowsBattery) }
    }

    // MARK: Now Playing

    @Published var nowPlayingEnabled: Bool = true {
        didSet { defaults.set(nowPlayingEnabled, forKey: SettingsKey.nowPlayingEnabled) }
    }
    @Published var showCompactNowPlaying: Bool = true {
        didSet { defaults.set(showCompactNowPlaying, forKey: SettingsKey.showCompactNowPlaying) }
    }
    @Published var showTrackPeek: Bool = true {
        didSet { defaults.set(showTrackPeek, forKey: SettingsKey.showTrackPeek) }
    }
    @Published var artworkStyle: ArtworkStyle = .rounded {
        didSet { defaults.set(artworkStyle.rawValue, forKey: SettingsKey.artworkStyle) }
    }
    @Published var visualizerStyle: VisualizerStyle = .bars {
        didSet { defaults.set(visualizerStyle.rawValue, forKey: SettingsKey.visualizerStyle) }
    }
    @Published var artworkGlow: Bool = true {
        didSet { defaults.set(artworkGlow, forKey: SettingsKey.artworkGlow) }
    }
    @Published var pausedLingerSeconds: Double = 15 {
        didSet { defaults.set(pausedLingerSeconds, forKey: SettingsKey.pausedLingerSeconds) }
    }

    // MARK: HUD

    @Published var hudEnabled: Bool = true {
        didSet { defaults.set(hudEnabled, forKey: SettingsKey.hudEnabled) }
    }
    @Published var replaceSystemHUD: Bool = true {
        didSet { defaults.set(replaceSystemHUD, forKey: SettingsKey.replaceSystemHUD) }
    }
    @Published var hudStyle: HUDStyle = .compact {
        didSet { defaults.set(hudStyle.rawValue, forKey: SettingsKey.hudStyle) }
    }
    @Published var volumeHUD: Bool = true {
        didSet { defaults.set(volumeHUD, forKey: SettingsKey.volumeHUD) }
    }
    @Published var brightnessHUD: Bool = true {
        didSet { defaults.set(brightnessHUD, forKey: SettingsKey.brightnessHUD) }
    }

    // MARK: Live activities

    @Published var chargingActivity: Bool = true {
        didSet { defaults.set(chargingActivity, forKey: SettingsKey.chargingActivity) }
    }
    @Published var lowBatteryActivity: Bool = true {
        didSet { defaults.set(lowBatteryActivity, forKey: SettingsKey.lowBatteryActivity) }
    }
    @Published var bluetoothActivity: Bool = true {
        didSet { defaults.set(bluetoothActivity, forKey: SettingsKey.bluetoothActivity) }
    }
    @Published var focusActivity: Bool = true {
        didSet { defaults.set(focusActivity, forKey: SettingsKey.focusActivity) }
    }
    @Published var calendarActivity: Bool = true {
        didSet { defaults.set(calendarActivity, forKey: SettingsKey.calendarActivity) }
    }
    @Published var calendarLeadMinutes: Int = 5 {
        didSet {
            let clamped = min(max(calendarLeadMinutes, 1), 60)
            if clamped != calendarLeadMinutes { calendarLeadMinutes = clamped }
            defaults.set(calendarLeadMinutes, forKey: SettingsKey.calendarLeadMinutes)
        }
    }
    @Published var calendarEnabled: Bool = true {
        didSet { defaults.set(calendarEnabled, forKey: SettingsKey.calendarEnabled) }
    }

    // MARK: Panel (v3)

    @Published var nonNotchStyle: NonNotchStyle = .pill {
        didSet { defaults.set(nonNotchStyle.rawValue, forKey: SettingsKey.nonNotchStyle) }
    }
    @Published var panelTabs: String = "home,nowPlaying,timer,clipboard,shelf,notes,system,aiUsage" {
        didSet { defaults.set(panelTabs, forKey: SettingsKey.panelTabs) }
    }
    @Published var rememberLastTab: Bool = true {
        didSet { defaults.set(rememberLastTab, forKey: SettingsKey.rememberLastTab) }
    }
    @Published var lastTab: String = "home" {
        didSet { defaults.set(lastTab, forKey: SettingsKey.lastTab) }
    }
    @Published var hotkeysEnabled: Bool = true {
        didSet { defaults.set(hotkeysEnabled, forKey: SettingsKey.hotkeysEnabled) }
    }

    // MARK: Lyrics & timer (v3)

    @Published var lyricsEnabled: Bool = true {
        didSet { defaults.set(lyricsEnabled, forKey: SettingsKey.lyricsEnabled) }
    }
    @Published var lyricsInCompact: Bool = true {
        didSet { defaults.set(lyricsInCompact, forKey: SettingsKey.lyricsInCompact) }
    }
    @Published var pomodoroWorkMinutes: Int = 25 {
        didSet {
            let clamped = min(max(pomodoroWorkMinutes, 1), 180)
            if clamped != pomodoroWorkMinutes { pomodoroWorkMinutes = clamped }
            defaults.set(pomodoroWorkMinutes, forKey: SettingsKey.pomodoroWorkMinutes)
        }
    }
    @Published var pomodoroShortBreakMinutes: Int = 5 {
        didSet {
            let clamped = min(max(pomodoroShortBreakMinutes, 1), 60)
            if clamped != pomodoroShortBreakMinutes { pomodoroShortBreakMinutes = clamped }
            defaults.set(pomodoroShortBreakMinutes, forKey: SettingsKey.pomodoroShortBreakMinutes)
        }
    }
    @Published var pomodoroLongBreakMinutes: Int = 15 {
        didSet {
            let clamped = min(max(pomodoroLongBreakMinutes, 1), 120)
            if clamped != pomodoroLongBreakMinutes { pomodoroLongBreakMinutes = clamped }
            defaults.set(pomodoroLongBreakMinutes, forKey: SettingsKey.pomodoroLongBreakMinutes)
        }
    }
    @Published var pomodoroCycles: Int = 4 {
        didSet {
            let clamped = min(max(pomodoroCycles, 1), 12)
            if clamped != pomodoroCycles { pomodoroCycles = clamped }
            defaults.set(pomodoroCycles, forKey: SettingsKey.pomodoroCycles)
        }
    }
    @Published var timerSound: Bool = true {
        didSet { defaults.set(timerSound, forKey: SettingsKey.timerSound) }
    }
    @Published var timerOverNowPlaying: Bool = true {
        didSet { defaults.set(timerOverNowPlaying, forKey: SettingsKey.timerOverNowPlaying) }
    }
    @Published var showCompactTimer: Bool = true {
        didSet { defaults.set(showCompactTimer, forKey: SettingsKey.showCompactTimer) }
    }

    // MARK: Clipboard, shelf, weather, AI (v3)

    @Published var clipboardEnabled: Bool = true {
        didSet { defaults.set(clipboardEnabled, forKey: SettingsKey.clipboardEnabled) }
    }
    @Published var clipboardLimit: Int = 50 {
        didSet {
            let clamped = min(max(clipboardLimit, 10), 500)
            if clamped != clipboardLimit { clipboardLimit = clamped }
            defaults.set(clipboardLimit, forKey: SettingsKey.clipboardLimit)
        }
    }
    @Published var cleanLinks: Bool = true {
        didSet { defaults.set(cleanLinks, forKey: SettingsKey.cleanLinks) }
    }
    @Published var pasteOnClick: Bool = true {
        didSet { defaults.set(pasteOnClick, forKey: SettingsKey.pasteOnClick) }
    }
    @Published var shelfEnabled: Bool = true {
        didSet { defaults.set(shelfEnabled, forKey: SettingsKey.shelfEnabled) }
    }
    @Published var shelfRemoveOnDragOut: Bool = false {
        didSet { defaults.set(shelfRemoveOnDragOut, forKey: SettingsKey.shelfRemoveOnDragOut) }
    }
    @Published var weatherEnabled: Bool = true {
        didSet { defaults.set(weatherEnabled, forKey: SettingsKey.weatherEnabled) }
    }
    @Published var weatherCity: String = "" {
        didSet { defaults.set(weatherCity, forKey: SettingsKey.weatherCity) }
    }
    @Published var temperatureUnit: TemperatureUnit = .celsius {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: SettingsKey.temperatureUnit) }
    }
    @Published var aiUsageEnabled: Bool = true {
        didSet { defaults.set(aiUsageEnabled, forKey: SettingsKey.aiUsageEnabled) }
    }

    // MARK: More live activities (v3)

    @Published var downloadActivity: Bool = true {
        didSet { defaults.set(downloadActivity, forKey: SettingsKey.downloadActivity) }
    }
    @Published var privacyActivity: Bool = true {
        didSet { defaults.set(privacyActivity, forKey: SettingsKey.privacyActivity) }
    }
    @Published var capsLockActivity: Bool = true {
        didSet { defaults.set(capsLockActivity, forKey: SettingsKey.capsLockActivity) }
    }
    @Published var notifyActivity: Bool = true {
        didSet { defaults.set(notifyActivity, forKey: SettingsKey.notifyActivity) }
    }

    // MARK: Look & onboarding (v3.1)

    @Published var islandMaterial: IslandMaterial = .glass {
        didSet { defaults.set(islandMaterial.rawValue, forKey: SettingsKey.islandMaterial) }
    }
    @Published var hasSeenWelcome: Bool = false {
        didSet { defaults.set(hasSeenWelcome, forKey: SettingsKey.hasSeenWelcome) }
    }

    /// Tabs shown in the panel: the configured order, minus features that are switched off.
    var enabledTabs: [PanelTab] {
        let tabs = PanelTab.parseList(panelTabs).filter { tab in
            switch tab {
            case .clipboard: return clipboardEnabled
            case .shelf: return shelfEnabled
            case .aiUsage: return aiUsageEnabled
            default: return true
            }
        }
        return tabs.isEmpty ? [.home] : tabs
    }

    var pomodoroConfig: PomodoroConfig {
        PomodoroConfig(work: TimeInterval(pomodoroWorkMinutes * 60),
                       shortBreak: TimeInterval(pomodoroShortBreakMinutes * 60),
                       longBreak: TimeInterval(pomodoroLongBreakMinutes * 60),
                       cyclesBeforeLongBreak: pomodoroCycles)
    }

    /// Every persisted key (kept local so this file depends only on the per-property constants).
    private static let allKeys: [String] = [
        SettingsKey.showMenuBarIcon, SettingsKey.displayMode, SettingsKey.hideInFullscreen,
        SettingsKey.showOnNonNotchDisplays, SettingsKey.hapticFeedback, SettingsKey.hasCompletedOnboarding,
        SettingsKey.expandOnHover, SettingsKey.hoverDelay, SettingsKey.collapseDelay, SettingsKey.clickToExpand,
        SettingsKey.gesturesEnabled, SettingsKey.expandedShowsCalendar, SettingsKey.expandedShowsBattery,
        SettingsKey.nowPlayingEnabled, SettingsKey.showCompactNowPlaying, SettingsKey.showTrackPeek,
        SettingsKey.artworkStyle, SettingsKey.visualizerStyle, SettingsKey.artworkGlow,
        SettingsKey.pausedLingerSeconds, SettingsKey.hudEnabled, SettingsKey.replaceSystemHUD,
        SettingsKey.hudStyle, SettingsKey.volumeHUD, SettingsKey.brightnessHUD,
        SettingsKey.chargingActivity, SettingsKey.lowBatteryActivity, SettingsKey.bluetoothActivity,
        SettingsKey.focusActivity, SettingsKey.calendarActivity, SettingsKey.calendarLeadMinutes,
        SettingsKey.calendarEnabled,
        SettingsKey.nonNotchStyle, SettingsKey.panelTabs, SettingsKey.rememberLastTab, SettingsKey.lastTab, SettingsKey.hotkeysEnabled, SettingsKey.lyricsEnabled, SettingsKey.lyricsInCompact, SettingsKey.pomodoroWorkMinutes, SettingsKey.pomodoroShortBreakMinutes, SettingsKey.pomodoroLongBreakMinutes, SettingsKey.pomodoroCycles, SettingsKey.timerSound, SettingsKey.timerOverNowPlaying, SettingsKey.showCompactTimer, SettingsKey.clipboardEnabled, SettingsKey.clipboardLimit, SettingsKey.cleanLinks, SettingsKey.pasteOnClick, SettingsKey.shelfEnabled, SettingsKey.shelfRemoveOnDragOut, SettingsKey.weatherEnabled, SettingsKey.weatherCity, SettingsKey.temperatureUnit, SettingsKey.aiUsageEnabled, SettingsKey.downloadActivity, SettingsKey.privacyActivity, SettingsKey.capsLockActivity, SettingsKey.notifyActivity,
        SettingsKey.islandMaterial, SettingsKey.hasSeenWelcome,
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Observers do not fire during init, so nothing is written back here.
        showMenuBarIcon = defaults.object(forKey: SettingsKey.showMenuBarIcon) as? Bool ?? true
        displayMode = defaults.string(forKey: SettingsKey.displayMode).flatMap { DisplayMode(rawValue: $0) } ?? .notchOrMain
        hideInFullscreen = defaults.object(forKey: SettingsKey.hideInFullscreen) as? Bool ?? true
        showOnNonNotchDisplays = defaults.object(forKey: SettingsKey.showOnNonNotchDisplays) as? Bool ?? true
        hapticFeedback = defaults.object(forKey: SettingsKey.hapticFeedback) as? Bool ?? true
        hasCompletedOnboarding = defaults.object(forKey: SettingsKey.hasCompletedOnboarding) as? Bool ?? false

        expandOnHover = defaults.object(forKey: SettingsKey.expandOnHover) as? Bool ?? true
        hoverDelay = AppSettings.clamp(defaults.object(forKey: SettingsKey.hoverDelay) as? Double ?? 0.15, 0, 1)
        collapseDelay = AppSettings.clamp(defaults.object(forKey: SettingsKey.collapseDelay) as? Double ?? 0.35, 0, 2)
        clickToExpand = defaults.object(forKey: SettingsKey.clickToExpand) as? Bool ?? true
        gesturesEnabled = defaults.object(forKey: SettingsKey.gesturesEnabled) as? Bool ?? true
        expandedShowsCalendar = defaults.object(forKey: SettingsKey.expandedShowsCalendar) as? Bool ?? true
        expandedShowsBattery = defaults.object(forKey: SettingsKey.expandedShowsBattery) as? Bool ?? true

        nowPlayingEnabled = defaults.object(forKey: SettingsKey.nowPlayingEnabled) as? Bool ?? true
        showCompactNowPlaying = defaults.object(forKey: SettingsKey.showCompactNowPlaying) as? Bool ?? true
        showTrackPeek = defaults.object(forKey: SettingsKey.showTrackPeek) as? Bool ?? true
        artworkStyle = defaults.string(forKey: SettingsKey.artworkStyle).flatMap { ArtworkStyle(rawValue: $0) } ?? .rounded
        visualizerStyle = defaults.string(forKey: SettingsKey.visualizerStyle).flatMap { VisualizerStyle(rawValue: $0) } ?? .bars
        artworkGlow = defaults.object(forKey: SettingsKey.artworkGlow) as? Bool ?? true
        pausedLingerSeconds = defaults.object(forKey: SettingsKey.pausedLingerSeconds) as? Double ?? 15

        hudEnabled = defaults.object(forKey: SettingsKey.hudEnabled) as? Bool ?? true
        replaceSystemHUD = defaults.object(forKey: SettingsKey.replaceSystemHUD) as? Bool ?? true
        hudStyle = defaults.string(forKey: SettingsKey.hudStyle).flatMap { HUDStyle(rawValue: $0) } ?? .compact
        volumeHUD = defaults.object(forKey: SettingsKey.volumeHUD) as? Bool ?? true
        brightnessHUD = defaults.object(forKey: SettingsKey.brightnessHUD) as? Bool ?? true

        chargingActivity = defaults.object(forKey: SettingsKey.chargingActivity) as? Bool ?? true
        lowBatteryActivity = defaults.object(forKey: SettingsKey.lowBatteryActivity) as? Bool ?? true
        bluetoothActivity = defaults.object(forKey: SettingsKey.bluetoothActivity) as? Bool ?? true
        focusActivity = defaults.object(forKey: SettingsKey.focusActivity) as? Bool ?? true
        calendarActivity = defaults.object(forKey: SettingsKey.calendarActivity) as? Bool ?? true
        calendarLeadMinutes = min(max(defaults.object(forKey: SettingsKey.calendarLeadMinutes) as? Int ?? 5, 1), 60)
        calendarEnabled = defaults.object(forKey: SettingsKey.calendarEnabled) as? Bool ?? true

        nonNotchStyle = defaults.string(forKey: SettingsKey.nonNotchStyle).flatMap { NonNotchStyle(rawValue: $0) } ?? .pill
        panelTabs = defaults.string(forKey: SettingsKey.panelTabs) ?? "home,nowPlaying,timer,clipboard,shelf,notes,system,aiUsage"
        rememberLastTab = defaults.object(forKey: SettingsKey.rememberLastTab) as? Bool ?? true
        lastTab = defaults.string(forKey: SettingsKey.lastTab) ?? "home"
        hotkeysEnabled = defaults.object(forKey: SettingsKey.hotkeysEnabled) as? Bool ?? true

        lyricsEnabled = defaults.object(forKey: SettingsKey.lyricsEnabled) as? Bool ?? true
        lyricsInCompact = defaults.object(forKey: SettingsKey.lyricsInCompact) as? Bool ?? true
        pomodoroWorkMinutes = min(max(defaults.object(forKey: SettingsKey.pomodoroWorkMinutes) as? Int ?? 25, 1), 180)
        pomodoroShortBreakMinutes = min(max(defaults.object(forKey: SettingsKey.pomodoroShortBreakMinutes) as? Int ?? 5, 1), 60)
        pomodoroLongBreakMinutes = min(max(defaults.object(forKey: SettingsKey.pomodoroLongBreakMinutes) as? Int ?? 15, 1), 120)
        pomodoroCycles = min(max(defaults.object(forKey: SettingsKey.pomodoroCycles) as? Int ?? 4, 1), 12)
        timerSound = defaults.object(forKey: SettingsKey.timerSound) as? Bool ?? true
        timerOverNowPlaying = defaults.object(forKey: SettingsKey.timerOverNowPlaying) as? Bool ?? true
        showCompactTimer = defaults.object(forKey: SettingsKey.showCompactTimer) as? Bool ?? true

        clipboardEnabled = defaults.object(forKey: SettingsKey.clipboardEnabled) as? Bool ?? true
        clipboardLimit = min(max(defaults.object(forKey: SettingsKey.clipboardLimit) as? Int ?? 50, 10), 500)
        cleanLinks = defaults.object(forKey: SettingsKey.cleanLinks) as? Bool ?? true
        pasteOnClick = defaults.object(forKey: SettingsKey.pasteOnClick) as? Bool ?? true
        shelfEnabled = defaults.object(forKey: SettingsKey.shelfEnabled) as? Bool ?? true
        shelfRemoveOnDragOut = defaults.object(forKey: SettingsKey.shelfRemoveOnDragOut) as? Bool ?? false
        weatherEnabled = defaults.object(forKey: SettingsKey.weatherEnabled) as? Bool ?? true
        weatherCity = defaults.string(forKey: SettingsKey.weatherCity) ?? ""
        temperatureUnit = defaults.string(forKey: SettingsKey.temperatureUnit).flatMap { TemperatureUnit(rawValue: $0) } ?? .celsius
        aiUsageEnabled = defaults.object(forKey: SettingsKey.aiUsageEnabled) as? Bool ?? true

        downloadActivity = defaults.object(forKey: SettingsKey.downloadActivity) as? Bool ?? true
        privacyActivity = defaults.object(forKey: SettingsKey.privacyActivity) as? Bool ?? true
        capsLockActivity = defaults.object(forKey: SettingsKey.capsLockActivity) as? Bool ?? true
        notifyActivity = defaults.object(forKey: SettingsKey.notifyActivity) as? Bool ?? true
        islandMaterial = defaults.string(forKey: SettingsKey.islandMaterial).flatMap { IslandMaterial(rawValue: $0) } ?? .glass
        hasSeenWelcome = defaults.object(forKey: SettingsKey.hasSeenWelcome) as? Bool ?? false
    }

    /// Removes every stored key and restores the contract defaults.
    func resetToDefaults() {
        for key in AppSettings.allKeys {
            defaults.removeObject(forKey: key)
        }
        showMenuBarIcon = true
        displayMode = .notchOrMain
        hideInFullscreen = true
        showOnNonNotchDisplays = true
        hapticFeedback = true
        hasCompletedOnboarding = false

        expandOnHover = true
        hoverDelay = 0.15
        collapseDelay = 0.35
        clickToExpand = true
        gesturesEnabled = true
        expandedShowsCalendar = true
        expandedShowsBattery = true

        nowPlayingEnabled = true
        showCompactNowPlaying = true
        showTrackPeek = true
        artworkStyle = .rounded
        visualizerStyle = .bars
        artworkGlow = true
        pausedLingerSeconds = 15

        hudEnabled = true
        replaceSystemHUD = true
        hudStyle = .compact
        volumeHUD = true
        brightnessHUD = true

        chargingActivity = true
        lowBatteryActivity = true
        bluetoothActivity = true
        focusActivity = true
        calendarActivity = true
        calendarLeadMinutes = 5
        calendarEnabled = true

        nonNotchStyle = .pill
        panelTabs = "home,nowPlaying,timer,clipboard,shelf,notes,system,aiUsage"
        rememberLastTab = true
        lastTab = "home"
        hotkeysEnabled = true

        lyricsEnabled = true
        lyricsInCompact = true
        pomodoroWorkMinutes = 25
        pomodoroShortBreakMinutes = 5
        pomodoroLongBreakMinutes = 15
        pomodoroCycles = 4
        timerSound = true
        timerOverNowPlaying = true
        showCompactTimer = true

        clipboardEnabled = true
        clipboardLimit = 50
        cleanLinks = true
        pasteOnClick = true
        shelfEnabled = true
        shelfRemoveOnDragOut = false
        weatherEnabled = true
        weatherCity = ""
        temperatureUnit = .celsius
        aiUsageEnabled = true

        downloadActivity = true
        privacyActivity = true
        capsLockActivity = true
        notifyActivity = true
        islandMaterial = .glass
        hasSeenWelcome = false
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        if value.isNaN { return lower }
        return min(max(value, lower), upper)
    }
}
