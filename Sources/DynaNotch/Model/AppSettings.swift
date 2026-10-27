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
    /// Shape on displays with a camera notch: merge with it, or float a pill just below it.
    @Published var notchDisplayStyle: NonNotchStyle = .notch {
        didSet { defaults.set(notchDisplayStyle.rawValue, forKey: SettingsKey.notchDisplayStyle) }
    }
    @Published var panelTabs: String = AppSettings.defaultPanelTabs {
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

    // MARK: Appearance & behavior (v3.2)

    @Published var materialPreset: MaterialPreset = .carbon {
        didSet { defaults.set(materialPreset.rawValue, forKey: SettingsKey.materialPreset) }
    }
    @Published var panelTranslucency: Double = 1.0 {
        didSet {
            let clamped = AppSettings.clamp(panelTranslucency, 0, 1)
            if clamped != panelTranslucency { panelTranslucency = clamped }
            defaults.set(panelTranslucency, forKey: SettingsKey.panelTranslucency)
        }
    }
    @Published var animationStyle: AnimationStyle = .calm {
        didSet { defaults.set(animationStyle.rawValue, forKey: SettingsKey.animationStyle) }
    }
    @Published var animationSpeed: Double = 1.0 {
        didSet {
            let clamped = AppSettings.clamp(animationSpeed, 0.5, 2)
            if clamped != animationSpeed { animationSpeed = clamped }
            defaults.set(animationSpeed, forKey: SettingsKey.animationSpeed)
        }
    }
    @Published var colorCodedLevels: Bool = false {
        didSet { defaults.set(colorCodedLevels, forKey: SettingsKey.colorCodedLevels) }
    }
    @Published var closedPillClock: Bool = false {
        didSet { defaults.set(closedPillClock, forKey: SettingsKey.closedPillClock) }
    }
    @Published var timeFormat: TimeFormat = .system {
        didSet { defaults.set(timeFormat.rawValue, forKey: SettingsKey.timeFormat) }
    }
    @Published var helloIntro: Bool = false {
        didSet { defaults.set(helloIntro, forKey: SettingsKey.helloIntro) }
    }
    @Published var defaultTab: String = "previous" {
        didSet { defaults.set(defaultTab, forKey: SettingsKey.defaultTab) }
    }
    @Published var openOnCurrentActivity: Bool = true {
        didSet { defaults.set(openOnCurrentActivity, forKey: SettingsKey.openOnCurrentActivity) }
    }
    @Published var idleTimeout: Double = 0 {
        didSet {
            let clamped = AppSettings.clamp(idleTimeout, 0, 600)
            if clamped != idleTimeout { idleTimeout = clamped }
            defaults.set(idleTimeout, forKey: SettingsKey.idleTimeout)
        }
    }
    @Published var invisibleUntilHover: Bool = false {
        didSet { defaults.set(invisibleUntilHover, forKey: SettingsKey.invisibleUntilHover) }
    }
    @Published var notificationDuration: Double = 4.5 {
        didSet {
            let clamped = AppSettings.clamp(notificationDuration, 1, 15)
            if clamped != notificationDuration { notificationDuration = clamped }
            defaults.set(notificationDuration, forKey: SettingsKey.notificationDuration)
        }
    }
    @Published var lyricsOffset: Double = 0 {
        didSet {
            let clamped = AppSettings.clamp(lyricsOffset, -5, 5)
            if clamped != lyricsOffset { lyricsOffset = clamped }
            defaults.set(lyricsOffset, forKey: SettingsKey.lyricsOffset)
        }
    }

    // MARK: Timer & wellbeing (v3.2)

    @Published var pomodoroAutoContinue: Bool = true {
        didSet { defaults.set(pomodoroAutoContinue, forKey: SettingsKey.pomodoroAutoContinue) }
    }
    @Published var breakLookAway: Bool = false {
        didSet { defaults.set(breakLookAway, forKey: SettingsKey.breakLookAway) }
    }
    @Published var breakStandUp: Bool = false {
        didSet { defaults.set(breakStandUp, forKey: SettingsKey.breakStandUp) }
    }
    @Published var standUpMinutes: Int = 60 {
        didSet {
            let clamped = min(max(standUpMinutes, 15), 180)
            if clamped != standUpMinutes { standUpMinutes = clamped }
            defaults.set(standUpMinutes, forKey: SettingsKey.standUpMinutes)
        }
    }
    @Published var breakDrinkWater: Bool = false {
        didSet { defaults.set(breakDrinkWater, forKey: SettingsKey.breakDrinkWater) }
    }
    @Published var drinkWaterMinutes: Int = 45 {
        didSet {
            let clamped = min(max(drinkWaterMinutes, 15), 180)
            if clamped != drinkWaterMinutes { drinkWaterMinutes = clamped }
            defaults.set(drinkWaterMinutes, forKey: SettingsKey.drinkWaterMinutes)
        }
    }

    // MARK: Battery & devices (v3.2)

    @Published var lowBatteryThreshold: Int = 20 {
        didSet {
            let clamped = min(max(lowBatteryThreshold, 5), 50)
            if clamped != lowBatteryThreshold { lowBatteryThreshold = clamped }
            defaults.set(lowBatteryThreshold, forKey: SettingsKey.lowBatteryThreshold)
        }
    }
    @Published var fullChargeActivity: Bool = false {
        didSet { defaults.set(fullChargeActivity, forKey: SettingsKey.fullChargeActivity) }
    }
    @Published var accessoryAlerts: Bool = true {
        didSet { defaults.set(accessoryAlerts, forKey: SettingsKey.accessoryAlerts) }
    }

    // MARK: Clipboard, search, tools (v3.2)

    @Published var clipboardIgnoredApps: String = AppSettings.defaultIgnoredApps {
        didSet { defaults.set(clipboardIgnoredApps, forKey: SettingsKey.clipboardIgnoredApps) }
    }
    @Published var clipboardAutoClearMinutes: Int = 0 {
        didSet {
            let clamped = min(max(clipboardAutoClearMinutes, 0), 120)
            if clamped != clipboardAutoClearMinutes { clipboardAutoClearMinutes = clamped }
            defaults.set(clipboardAutoClearMinutes, forKey: SettingsKey.clipboardAutoClearMinutes)
        }
    }
    @Published var pasteWithNumbers: Bool = true {
        didSet { defaults.set(pasteWithNumbers, forKey: SettingsKey.pasteWithNumbers) }
    }
    @Published var meetingAlert: Bool = false {
        didSet { defaults.set(meetingAlert, forKey: SettingsKey.meetingAlert) }
    }
    @Published var meetingAlertMinutes: Int = 1 {
        didSet {
            let clamped = min(max(meetingAlertMinutes, 0), 15)
            if clamped != meetingAlertMinutes { meetingAlertMinutes = clamped }
            defaults.set(meetingAlertMinutes, forKey: SettingsKey.meetingAlertMinutes)
        }
    }
    @Published var screenTimeEnabled: Bool = true {
        didSet { defaults.set(screenTimeEnabled, forKey: SettingsKey.screenTimeEnabled) }
    }
    @Published var quickSearchEngine: String = "google" {
        didSet { defaults.set(quickSearchEngine, forKey: SettingsKey.quickSearchEngine) }
    }
    @Published var launcherApps: String = "" {
        didSet { defaults.set(launcherApps, forKey: SettingsKey.launcherApps) }
    }
    @Published var colorFormat: String = "hex" {
        didSet { defaults.set(colorFormat, forKey: SettingsKey.colorFormat) }
    }
    @Published var driveActivity: Bool = true {
        didSet { defaults.set(driveActivity, forKey: SettingsKey.driveActivity) }
    }
    @Published var screenshotToShelf: Bool = false {
        didSet { defaults.set(screenshotToShelf, forKey: SettingsKey.screenshotToShelf) }
    }
    @Published var headerButtons: String = "battery,output,keepAwake,actions,pin,lock" {
        didSet { defaults.set(headerButtons, forKey: SettingsKey.headerButtons) }
    }

    // MARK: v3.3 (Notchy audit #2, §2e P1)

    @Published var pillScale: Double = 1.0 {
        didSet {
            let clamped = AppSettings.clamp(pillScale, 0.8, 1.3)
            if clamped != pillScale { pillScale = clamped }
            defaults.set(pillScale, forKey: SettingsKey.pillScale)
        }
    }
    @Published var pillHeightOffset: Double = 0 {
        didSet {
            let clamped = AppSettings.clamp(pillHeightOffset, -6, 12)
            if clamped != pillHeightOffset { pillHeightOffset = clamped }
            defaults.set(pillHeightOffset, forKey: SettingsKey.pillHeightOffset)
        }
    }
    // MARK: Pill size (CONTRACTS §6.9) — resting pill width (clamped to ≥ the notch where used) and height.

    @Published var pillWidth: Double = 185 {
        didSet {
            let clamped = AppSettings.clamp(pillWidth, 150, 420)
            if clamped != pillWidth { pillWidth = clamped }
            defaults.set(pillWidth, forKey: SettingsKey.pillWidth)
        }
    }
    @Published var pillHeight: Double = 36 {
        didSet {
            let clamped = AppSettings.clamp(pillHeight, 28, 44)
            if clamped != pillHeight { pillHeight = clamped }
            defaults.set(pillHeight, forKey: SettingsKey.pillHeight)
        }
    }

    // MARK: Lock screen (CONTRACTS §6.11)

    @Published var unlockActivity: Bool = true {
        didSet { defaults.set(unlockActivity, forKey: SettingsKey.unlockActivity) }
    }
    @Published var lockScreenWidgets: Bool = true {
        didSet { defaults.set(lockScreenWidgets, forKey: SettingsKey.lockScreenWidgets) }
    }
    @Published var lockScreenWeather: Bool = true {
        didSet { defaults.set(lockScreenWeather, forKey: SettingsKey.lockScreenWeather) }
    }
    @Published var lockScreenBatteries: Bool = true {
        didSet { defaults.set(lockScreenBatteries, forKey: SettingsKey.lockScreenBatteries) }
    }
    @Published var screenSharingPrivacy: Bool = false {
        didSet { defaults.set(screenSharingPrivacy, forKey: SettingsKey.screenSharingPrivacy) }
    }
    @Published var hideWhileMirroring: Bool = false {
        didSet { defaults.set(hideWhileMirroring, forKey: SettingsKey.hideWhileMirroring) }
    }
    @Published var fullscreenScope: FullscreenScope = .allApps {
        didSet { defaults.set(fullscreenScope.rawValue, forKey: SettingsKey.fullscreenScope) }
    }
    @Published var autoCollapse: Bool = true {
        didSet { defaults.set(autoCollapse, forKey: SettingsKey.autoCollapse) }
    }
    @Published var quietDuringFocus: Bool = false {
        didSet { defaults.set(quietDuringFocus, forKey: SettingsKey.quietDuringFocus) }
    }
    @Published var peekOnHover: Bool = false {
        didSet { defaults.set(peekOnHover, forKey: SettingsKey.peekOnHover) }
    }
    @Published var mediaKeysControlPlayer: Bool = true {
        didSet { defaults.set(mediaKeysControlPlayer, forKey: SettingsKey.mediaKeysControlPlayer) }
    }
    @Published var preventMusicAutoLaunch: Bool = false {
        didSet { defaults.set(preventMusicAutoLaunch, forKey: SettingsKey.preventMusicAutoLaunch) }
    }
    @Published var meetingOnlyWithLink: Bool = true {
        didSet { defaults.set(meetingOnlyWithLink, forKey: SettingsKey.meetingOnlyWithLink) }
    }
    @Published var hiddenCalendars: String = "" {
        didSet { defaults.set(hiddenCalendars, forKey: SettingsKey.hiddenCalendars) }
    }
    @Published var calendarHotkeys: Bool = true {
        didSet { defaults.set(calendarHotkeys, forKey: SettingsKey.calendarHotkeys) }
    }
    @Published var timerHoverControls: Bool = true {
        didSet { defaults.set(timerHoverControls, forKey: SettingsKey.timerHoverControls) }
    }
    @Published var clipboardCaptureSound: Bool = false {
        didSet { defaults.set(clipboardCaptureSound, forKey: SettingsKey.clipboardCaptureSound) }
    }
    @Published var shelfRetention: ShelfRetention = .untilCleared {
        didSet { defaults.set(shelfRetention.rawValue, forKey: SettingsKey.shelfRetention) }
    }
    @Published var screenshotFolder: String = "" {
        didSet { defaults.set(screenshotFolder, forKey: SettingsKey.screenshotFolder) }
    }
    @Published var unplugActivity: Bool = true {
        didSet { defaults.set(unplugActivity, forKey: SettingsKey.unplugActivity) }
    }
    @Published var fullChargeLevel: Int = 100 {
        didSet {
            let clamped = min(max(fullChargeLevel, 80), 100)
            if clamped != fullChargeLevel { fullChargeLevel = clamped }
            defaults.set(fullChargeLevel, forKey: SettingsKey.fullChargeLevel)
        }
    }

    // MARK: v3.4 (Notchy audit #2, §2e P2)

    @Published var clockContent: ClockContent = .time {
        didSet { defaults.set(clockContent.rawValue, forKey: SettingsKey.clockContent) }
    }
    @Published var clockWithActivities: Bool = false {
        didSet { defaults.set(clockWithActivities, forKey: SettingsKey.clockWithActivities) }
    }
    @Published var panelWidth: Double = 640 {
        didSet {
            let clamped = AppSettings.clamp(panelWidth, 520, 820)
            if clamped != panelWidth { panelWidth = clamped }
            defaults.set(panelWidth, forKey: SettingsKey.panelWidth)
        }
    }
    @Published var panelSizing: PanelSizing = .fixed {
        didSet { defaults.set(panelSizing.rawValue, forKey: SettingsKey.panelSizing) }
    }
    @Published var panelMaxHeight: Double = 190 {
        didSet {
            let clamped = AppSettings.clamp(panelMaxHeight, 150, 320)
            if clamped != panelMaxHeight { panelMaxHeight = clamped }
            defaults.set(panelMaxHeight, forKey: SettingsKey.panelMaxHeight)
        }
    }
    @Published var panelFillHex: String = "" {
        didSet { defaults.set(panelFillHex, forKey: SettingsKey.panelFillHex) }
    }
    @Published var pillMatchesPanel: Bool = false {
        didSet { defaults.set(pillMatchesPanel, forKey: SettingsKey.pillMatchesPanel) }
    }
    @Published var trackInfoMode: TrackInfoMode = .onChange {
        didSet { defaults.set(trackInfoMode.rawValue, forKey: SettingsKey.trackInfoMode) }
    }
    @Published var desktopLyrics: Bool = false {
        didSet { defaults.set(desktopLyrics, forKey: SettingsKey.desktopLyrics) }
    }
    @Published var edgeGlow: Bool = false {
        didSet { defaults.set(edgeGlow, forKey: SettingsKey.edgeGlow) }
    }
    @Published var alertSounds: String = "" {
        didSet { defaults.set(alertSounds, forKey: SettingsKey.alertSounds) }
    }
    @Published var hotkeyBindings: String = "" {
        didSet { defaults.set(hotkeyBindings, forKey: SettingsKey.hotkeyBindings) }
    }
    @Published var knockEnabled: Bool = false {
        didSet { defaults.set(knockEnabled, forKey: SettingsKey.knockEnabled) }
    }
    @Published var knockKey: KnockKey = .control {
        didSet { defaults.set(knockKey.rawValue, forKey: SettingsKey.knockKey) }
    }
    @Published var knockActions: String = "1=togglePanel,2=clipboard,3=commandPalette" {
        didSet { defaults.set(knockActions, forKey: SettingsKey.knockActions) }
    }
    @Published var copyTwiceToOpen: Bool = false {
        didSet { defaults.set(copyTwiceToOpen, forKey: SettingsKey.copyTwiceToOpen) }
    }
    @Published var offerCleanCopy: Bool = false {
        didSet { defaults.set(offerCleanCopy, forKey: SettingsKey.offerCleanCopy) }
    }
    @Published var customSearchEngines: String = "" {
        didSet { defaults.set(customSearchEngines, forKey: SettingsKey.customSearchEngines) }
    }
    @Published var homeCards: String = "" {
        didSet { defaults.set(homeCards, forKey: SettingsKey.homeCards) }
    }
    @Published var homeColumns: Int = 3 {
        didSet {
            let clamped = min(max(homeColumns, 2), 4)
            if clamped != homeColumns { homeColumns = clamped }
            defaults.set(homeColumns, forKey: SettingsKey.homeColumns)
        }
    }
    @Published var worldClocks: String = "America/New_York,Europe/London,Asia/Tokyo" {
        didSet { defaults.set(worldClocks, forKey: SettingsKey.worldClocks) }
    }
    @Published var savedLinks: String = "" {
        didSet { defaults.set(savedLinks, forKey: SettingsKey.savedLinks) }
    }
    @Published var repeatTimer: Bool = false {
        didSet { defaults.set(repeatTimer, forKey: SettingsKey.repeatTimer) }
    }
    @Published var repeatAlarm: Bool = false {
        didSet { defaults.set(repeatAlarm, forKey: SettingsKey.repeatAlarm) }
    }
    @Published var pomodoroOnly: Bool = false {
        didSet { defaults.set(pomodoroOnly, forKey: SettingsKey.pomodoroOnly) }
    }
    @Published var aiLimitWarnings: Bool = true {
        didSet { defaults.set(aiLimitWarnings, forKey: SettingsKey.aiLimitWarnings) }
    }
    @Published var aiLimitWarnPercent: Int = 80 {
        didSet {
            let clamped = min(max(aiLimitWarnPercent, 50), 95)
            if clamped != aiLimitWarnPercent { aiLimitWarnPercent = clamped }
            defaults.set(aiLimitWarnPercent, forKey: SettingsKey.aiLimitWarnPercent)
        }
    }
    @Published var aiMenuBarReadout: Bool = false {
        didSet { defaults.set(aiMenuBarReadout, forKey: SettingsKey.aiMenuBarReadout) }
    }
    @Published var aiHidePersonalInfo: Bool = false {
        didSet { defaults.set(aiHidePersonalInfo, forKey: SettingsKey.aiHidePersonalInfo) }
    }
    @Published var batteryInMenuBar: Bool = false {
        didSet { defaults.set(batteryInMenuBar, forKey: SettingsKey.batteryInMenuBar) }
    }
    @Published var drainWarnings: Bool = false {
        didSet { defaults.set(drainWarnings, forKey: SettingsKey.drainWarnings) }
    }
    @Published var dmgInstallOffer: Bool = true {
        didSet { defaults.set(dmgInstallOffer, forKey: SettingsKey.dmgInstallOffer) }
    }
    @Published var nextMeetingInMenuBar: Bool = false {
        didSet { defaults.set(nextMeetingInMenuBar, forKey: SettingsKey.nextMeetingInMenuBar) }
    }
    @Published var listeningHistory: Bool = true {
        didSet { defaults.set(listeningHistory, forKey: SettingsKey.listeningHistory) }
    }
    @Published var defaultMusicApp: String = "" {
        didSet { defaults.set(defaultMusicApp, forKey: SettingsKey.defaultMusicApp) }
    }

    static let defaultPanelTabs = PanelTab.serialize(PanelTab.allCases)

    /// Password managers whose copies are never recorded.
    static let defaultIgnoredApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.Passwords", "com.apple.keychainaccess",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc", "com.lastpass.LastPass", "in.sinew.Enpass-Desktop",
    ].joined(separator: ",")

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
        SettingsKey.materialPreset, SettingsKey.panelTranslucency, SettingsKey.animationStyle, SettingsKey.animationSpeed, SettingsKey.colorCodedLevels, SettingsKey.closedPillClock, SettingsKey.timeFormat, SettingsKey.helloIntro, SettingsKey.defaultTab, SettingsKey.openOnCurrentActivity, SettingsKey.idleTimeout, SettingsKey.invisibleUntilHover, SettingsKey.notificationDuration, SettingsKey.lyricsOffset, SettingsKey.pomodoroAutoContinue, SettingsKey.breakLookAway, SettingsKey.breakStandUp, SettingsKey.standUpMinutes, SettingsKey.breakDrinkWater, SettingsKey.drinkWaterMinutes, SettingsKey.lowBatteryThreshold, SettingsKey.fullChargeActivity, SettingsKey.accessoryAlerts, SettingsKey.clipboardIgnoredApps, SettingsKey.clipboardAutoClearMinutes, SettingsKey.pasteWithNumbers, SettingsKey.meetingAlert, SettingsKey.meetingAlertMinutes, SettingsKey.screenTimeEnabled, SettingsKey.quickSearchEngine, SettingsKey.launcherApps, SettingsKey.colorFormat, SettingsKey.driveActivity, SettingsKey.screenshotToShelf, SettingsKey.headerButtons, SettingsKey.notchDisplayStyle, SettingsKey.pillScale, SettingsKey.pillHeightOffset, SettingsKey.screenSharingPrivacy, SettingsKey.hideWhileMirroring, SettingsKey.fullscreenScope, SettingsKey.autoCollapse, SettingsKey.quietDuringFocus, SettingsKey.peekOnHover, SettingsKey.mediaKeysControlPlayer, SettingsKey.preventMusicAutoLaunch, SettingsKey.meetingOnlyWithLink, SettingsKey.hiddenCalendars, SettingsKey.calendarHotkeys, SettingsKey.timerHoverControls, SettingsKey.clipboardCaptureSound, SettingsKey.shelfRetention, SettingsKey.screenshotFolder, SettingsKey.unplugActivity, SettingsKey.fullChargeLevel, SettingsKey.clockContent, SettingsKey.clockWithActivities, SettingsKey.panelWidth, SettingsKey.panelSizing, SettingsKey.panelMaxHeight, SettingsKey.panelFillHex, SettingsKey.pillMatchesPanel, SettingsKey.trackInfoMode, SettingsKey.desktopLyrics, SettingsKey.edgeGlow, SettingsKey.alertSounds, SettingsKey.hotkeyBindings, SettingsKey.knockEnabled, SettingsKey.knockKey, SettingsKey.knockActions, SettingsKey.copyTwiceToOpen, SettingsKey.offerCleanCopy, SettingsKey.customSearchEngines, SettingsKey.homeCards, SettingsKey.homeColumns, SettingsKey.worldClocks, SettingsKey.savedLinks, SettingsKey.repeatTimer, SettingsKey.repeatAlarm, SettingsKey.pomodoroOnly, SettingsKey.aiLimitWarnings, SettingsKey.aiLimitWarnPercent, SettingsKey.aiMenuBarReadout, SettingsKey.aiHidePersonalInfo, SettingsKey.batteryInMenuBar, SettingsKey.drainWarnings, SettingsKey.dmgInstallOffer, SettingsKey.nextMeetingInMenuBar, SettingsKey.listeningHistory, SettingsKey.defaultMusicApp, SettingsKey.pillWidth, SettingsKey.pillHeight, SettingsKey.unlockActivity, SettingsKey.lockScreenWidgets, SettingsKey.lockScreenWeather, SettingsKey.lockScreenBatteries,
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
        notchDisplayStyle = defaults.string(forKey: SettingsKey.notchDisplayStyle).flatMap { NonNotchStyle(rawValue: $0) } ?? .notch
        panelTabs = defaults.string(forKey: SettingsKey.panelTabs) ?? AppSettings.defaultPanelTabs
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
        materialPreset = defaults.string(forKey: SettingsKey.materialPreset).flatMap { MaterialPreset(rawValue: $0) } ?? .carbon
        panelTranslucency = AppSettings.clamp(defaults.object(forKey: SettingsKey.panelTranslucency) as? Double ?? 1.0, 0, 1)
        animationStyle = defaults.string(forKey: SettingsKey.animationStyle).flatMap { AnimationStyle(rawValue: $0) } ?? .calm
        animationSpeed = AppSettings.clamp(defaults.object(forKey: SettingsKey.animationSpeed) as? Double ?? 1.0, 0.5, 2)
        colorCodedLevels = defaults.object(forKey: SettingsKey.colorCodedLevels) as? Bool ?? false
        closedPillClock = defaults.object(forKey: SettingsKey.closedPillClock) as? Bool ?? false
        timeFormat = defaults.string(forKey: SettingsKey.timeFormat).flatMap { TimeFormat(rawValue: $0) } ?? .system
        helloIntro = defaults.object(forKey: SettingsKey.helloIntro) as? Bool ?? false
        defaultTab = defaults.string(forKey: SettingsKey.defaultTab) ?? "previous"
        openOnCurrentActivity = defaults.object(forKey: SettingsKey.openOnCurrentActivity) as? Bool ?? true
        idleTimeout = AppSettings.clamp(defaults.object(forKey: SettingsKey.idleTimeout) as? Double ?? 0, 0, 600)
        invisibleUntilHover = defaults.object(forKey: SettingsKey.invisibleUntilHover) as? Bool ?? false
        notificationDuration = AppSettings.clamp(defaults.object(forKey: SettingsKey.notificationDuration) as? Double ?? 4.5, 1, 15)
        lyricsOffset = AppSettings.clamp(defaults.object(forKey: SettingsKey.lyricsOffset) as? Double ?? 0, -5, 5)
        pomodoroAutoContinue = defaults.object(forKey: SettingsKey.pomodoroAutoContinue) as? Bool ?? true
        breakLookAway = defaults.object(forKey: SettingsKey.breakLookAway) as? Bool ?? false
        breakStandUp = defaults.object(forKey: SettingsKey.breakStandUp) as? Bool ?? false
        standUpMinutes = min(max(defaults.object(forKey: SettingsKey.standUpMinutes) as? Int ?? 60, 15), 180)
        breakDrinkWater = defaults.object(forKey: SettingsKey.breakDrinkWater) as? Bool ?? false
        drinkWaterMinutes = min(max(defaults.object(forKey: SettingsKey.drinkWaterMinutes) as? Int ?? 45, 15), 180)
        lowBatteryThreshold = min(max(defaults.object(forKey: SettingsKey.lowBatteryThreshold) as? Int ?? 20, 5), 50)
        fullChargeActivity = defaults.object(forKey: SettingsKey.fullChargeActivity) as? Bool ?? false
        accessoryAlerts = defaults.object(forKey: SettingsKey.accessoryAlerts) as? Bool ?? true
        clipboardIgnoredApps = defaults.string(forKey: SettingsKey.clipboardIgnoredApps) ?? AppSettings.defaultIgnoredApps
        clipboardAutoClearMinutes = min(max(defaults.object(forKey: SettingsKey.clipboardAutoClearMinutes) as? Int ?? 0, 0), 120)
        pasteWithNumbers = defaults.object(forKey: SettingsKey.pasteWithNumbers) as? Bool ?? true
        meetingAlert = defaults.object(forKey: SettingsKey.meetingAlert) as? Bool ?? false
        meetingAlertMinutes = min(max(defaults.object(forKey: SettingsKey.meetingAlertMinutes) as? Int ?? 1, 0), 15)
        screenTimeEnabled = defaults.object(forKey: SettingsKey.screenTimeEnabled) as? Bool ?? true
        quickSearchEngine = defaults.string(forKey: SettingsKey.quickSearchEngine) ?? "google"
        launcherApps = defaults.string(forKey: SettingsKey.launcherApps) ?? ""
        colorFormat = defaults.string(forKey: SettingsKey.colorFormat) ?? "hex"
        driveActivity = defaults.object(forKey: SettingsKey.driveActivity) as? Bool ?? true
        screenshotToShelf = defaults.object(forKey: SettingsKey.screenshotToShelf) as? Bool ?? false
        headerButtons = defaults.string(forKey: SettingsKey.headerButtons) ?? "battery,output,keepAwake,actions,pin,lock"
        pillScale = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillScale) as? Double ?? 1.0, 0.8, 1.3)
        pillHeightOffset = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillHeightOffset) as? Double ?? 0, -6, 12)
        pillWidth = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillWidth) as? Double ?? 185, 150, 420)
        pillHeight = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillHeight) as? Double ?? 36, 28, 44)
        unlockActivity = defaults.object(forKey: SettingsKey.unlockActivity) as? Bool ?? true
        lockScreenWidgets = defaults.object(forKey: SettingsKey.lockScreenWidgets) as? Bool ?? true
        lockScreenWeather = defaults.object(forKey: SettingsKey.lockScreenWeather) as? Bool ?? true
        lockScreenBatteries = defaults.object(forKey: SettingsKey.lockScreenBatteries) as? Bool ?? true
        screenSharingPrivacy = defaults.object(forKey: SettingsKey.screenSharingPrivacy) as? Bool ?? false
        hideWhileMirroring = defaults.object(forKey: SettingsKey.hideWhileMirroring) as? Bool ?? false
        fullscreenScope = defaults.string(forKey: SettingsKey.fullscreenScope).flatMap { FullscreenScope(rawValue: $0) } ?? .allApps
        autoCollapse = defaults.object(forKey: SettingsKey.autoCollapse) as? Bool ?? true
        quietDuringFocus = defaults.object(forKey: SettingsKey.quietDuringFocus) as? Bool ?? false
        peekOnHover = defaults.object(forKey: SettingsKey.peekOnHover) as? Bool ?? false
        mediaKeysControlPlayer = defaults.object(forKey: SettingsKey.mediaKeysControlPlayer) as? Bool ?? true
        preventMusicAutoLaunch = defaults.object(forKey: SettingsKey.preventMusicAutoLaunch) as? Bool ?? false
        meetingOnlyWithLink = defaults.object(forKey: SettingsKey.meetingOnlyWithLink) as? Bool ?? true
        hiddenCalendars = defaults.string(forKey: SettingsKey.hiddenCalendars) ?? ""
        calendarHotkeys = defaults.object(forKey: SettingsKey.calendarHotkeys) as? Bool ?? true
        timerHoverControls = defaults.object(forKey: SettingsKey.timerHoverControls) as? Bool ?? true
        clipboardCaptureSound = defaults.object(forKey: SettingsKey.clipboardCaptureSound) as? Bool ?? false
        shelfRetention = defaults.string(forKey: SettingsKey.shelfRetention).flatMap { ShelfRetention(rawValue: $0) } ?? .untilCleared
        screenshotFolder = defaults.string(forKey: SettingsKey.screenshotFolder) ?? ""
        unplugActivity = defaults.object(forKey: SettingsKey.unplugActivity) as? Bool ?? true
        fullChargeLevel = min(max(defaults.object(forKey: SettingsKey.fullChargeLevel) as? Int ?? 100, 80), 100)
        clockContent = defaults.string(forKey: SettingsKey.clockContent).flatMap { ClockContent(rawValue: $0) } ?? .time
        clockWithActivities = defaults.object(forKey: SettingsKey.clockWithActivities) as? Bool ?? false
        panelWidth = AppSettings.clamp(defaults.object(forKey: SettingsKey.panelWidth) as? Double ?? 640, 520, 820)
        panelSizing = defaults.string(forKey: SettingsKey.panelSizing).flatMap { PanelSizing(rawValue: $0) } ?? .fixed
        panelMaxHeight = AppSettings.clamp(defaults.object(forKey: SettingsKey.panelMaxHeight) as? Double ?? 190, 150, 320)
        panelFillHex = defaults.string(forKey: SettingsKey.panelFillHex) ?? ""
        pillMatchesPanel = defaults.object(forKey: SettingsKey.pillMatchesPanel) as? Bool ?? false
        trackInfoMode = defaults.string(forKey: SettingsKey.trackInfoMode).flatMap { TrackInfoMode(rawValue: $0) } ?? .onChange
        desktopLyrics = defaults.object(forKey: SettingsKey.desktopLyrics) as? Bool ?? false
        edgeGlow = defaults.object(forKey: SettingsKey.edgeGlow) as? Bool ?? false
        alertSounds = defaults.string(forKey: SettingsKey.alertSounds) ?? ""
        hotkeyBindings = defaults.string(forKey: SettingsKey.hotkeyBindings) ?? ""
        knockEnabled = defaults.object(forKey: SettingsKey.knockEnabled) as? Bool ?? false
        knockKey = defaults.string(forKey: SettingsKey.knockKey).flatMap { KnockKey(rawValue: $0) } ?? .control
        knockActions = defaults.string(forKey: SettingsKey.knockActions) ?? "1=togglePanel,2=clipboard,3=commandPalette"
        copyTwiceToOpen = defaults.object(forKey: SettingsKey.copyTwiceToOpen) as? Bool ?? false
        offerCleanCopy = defaults.object(forKey: SettingsKey.offerCleanCopy) as? Bool ?? false
        customSearchEngines = defaults.string(forKey: SettingsKey.customSearchEngines) ?? ""
        homeCards = defaults.string(forKey: SettingsKey.homeCards) ?? ""
        homeColumns = min(max(defaults.object(forKey: SettingsKey.homeColumns) as? Int ?? 3, 2), 4)
        worldClocks = defaults.string(forKey: SettingsKey.worldClocks) ?? "America/New_York,Europe/London,Asia/Tokyo"
        savedLinks = defaults.string(forKey: SettingsKey.savedLinks) ?? ""
        repeatTimer = defaults.object(forKey: SettingsKey.repeatTimer) as? Bool ?? false
        repeatAlarm = defaults.object(forKey: SettingsKey.repeatAlarm) as? Bool ?? false
        pomodoroOnly = defaults.object(forKey: SettingsKey.pomodoroOnly) as? Bool ?? false
        aiLimitWarnings = defaults.object(forKey: SettingsKey.aiLimitWarnings) as? Bool ?? true
        aiLimitWarnPercent = min(max(defaults.object(forKey: SettingsKey.aiLimitWarnPercent) as? Int ?? 80, 50), 95)
        aiMenuBarReadout = defaults.object(forKey: SettingsKey.aiMenuBarReadout) as? Bool ?? false
        aiHidePersonalInfo = defaults.object(forKey: SettingsKey.aiHidePersonalInfo) as? Bool ?? false
        batteryInMenuBar = defaults.object(forKey: SettingsKey.batteryInMenuBar) as? Bool ?? false
        drainWarnings = defaults.object(forKey: SettingsKey.drainWarnings) as? Bool ?? false
        dmgInstallOffer = defaults.object(forKey: SettingsKey.dmgInstallOffer) as? Bool ?? true
        nextMeetingInMenuBar = defaults.object(forKey: SettingsKey.nextMeetingInMenuBar) as? Bool ?? false
        listeningHistory = defaults.object(forKey: SettingsKey.listeningHistory) as? Bool ?? true
        defaultMusicApp = defaults.string(forKey: SettingsKey.defaultMusicApp) ?? ""

        // Tabs added by an update join an already-customised tab list once.
        if let stored = defaults.string(forKey: SettingsKey.panelTabs) {
            let migrated = PanelTab.migrate(stored: stored, known: defaults.string(forKey: SettingsKey.knownTabs))
            if migrated != stored {
                panelTabs = migrated
                defaults.set(migrated, forKey: SettingsKey.panelTabs)
            }
        }
        defaults.set(AppSettings.defaultPanelTabs, forKey: SettingsKey.knownTabs)
    }

    /// Re-reads every property from UserDefaults (missing keys → contract defaults).
    private func reloadFromDefaults() {
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
        notchDisplayStyle = defaults.string(forKey: SettingsKey.notchDisplayStyle).flatMap { NonNotchStyle(rawValue: $0) } ?? .notch
        panelTabs = defaults.string(forKey: SettingsKey.panelTabs) ?? AppSettings.defaultPanelTabs
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
        materialPreset = defaults.string(forKey: SettingsKey.materialPreset).flatMap { MaterialPreset(rawValue: $0) } ?? .carbon
        panelTranslucency = AppSettings.clamp(defaults.object(forKey: SettingsKey.panelTranslucency) as? Double ?? 1.0, 0, 1)
        animationStyle = defaults.string(forKey: SettingsKey.animationStyle).flatMap { AnimationStyle(rawValue: $0) } ?? .calm
        animationSpeed = AppSettings.clamp(defaults.object(forKey: SettingsKey.animationSpeed) as? Double ?? 1.0, 0.5, 2)
        colorCodedLevels = defaults.object(forKey: SettingsKey.colorCodedLevels) as? Bool ?? false
        closedPillClock = defaults.object(forKey: SettingsKey.closedPillClock) as? Bool ?? false
        timeFormat = defaults.string(forKey: SettingsKey.timeFormat).flatMap { TimeFormat(rawValue: $0) } ?? .system
        helloIntro = defaults.object(forKey: SettingsKey.helloIntro) as? Bool ?? false
        defaultTab = defaults.string(forKey: SettingsKey.defaultTab) ?? "previous"
        openOnCurrentActivity = defaults.object(forKey: SettingsKey.openOnCurrentActivity) as? Bool ?? true
        idleTimeout = AppSettings.clamp(defaults.object(forKey: SettingsKey.idleTimeout) as? Double ?? 0, 0, 600)
        invisibleUntilHover = defaults.object(forKey: SettingsKey.invisibleUntilHover) as? Bool ?? false
        notificationDuration = AppSettings.clamp(defaults.object(forKey: SettingsKey.notificationDuration) as? Double ?? 4.5, 1, 15)
        lyricsOffset = AppSettings.clamp(defaults.object(forKey: SettingsKey.lyricsOffset) as? Double ?? 0, -5, 5)
        pomodoroAutoContinue = defaults.object(forKey: SettingsKey.pomodoroAutoContinue) as? Bool ?? true
        breakLookAway = defaults.object(forKey: SettingsKey.breakLookAway) as? Bool ?? false
        breakStandUp = defaults.object(forKey: SettingsKey.breakStandUp) as? Bool ?? false
        standUpMinutes = min(max(defaults.object(forKey: SettingsKey.standUpMinutes) as? Int ?? 60, 15), 180)
        breakDrinkWater = defaults.object(forKey: SettingsKey.breakDrinkWater) as? Bool ?? false
        drinkWaterMinutes = min(max(defaults.object(forKey: SettingsKey.drinkWaterMinutes) as? Int ?? 45, 15), 180)
        lowBatteryThreshold = min(max(defaults.object(forKey: SettingsKey.lowBatteryThreshold) as? Int ?? 20, 5), 50)
        fullChargeActivity = defaults.object(forKey: SettingsKey.fullChargeActivity) as? Bool ?? false
        accessoryAlerts = defaults.object(forKey: SettingsKey.accessoryAlerts) as? Bool ?? true
        clipboardIgnoredApps = defaults.string(forKey: SettingsKey.clipboardIgnoredApps) ?? AppSettings.defaultIgnoredApps
        clipboardAutoClearMinutes = min(max(defaults.object(forKey: SettingsKey.clipboardAutoClearMinutes) as? Int ?? 0, 0), 120)
        pasteWithNumbers = defaults.object(forKey: SettingsKey.pasteWithNumbers) as? Bool ?? true
        meetingAlert = defaults.object(forKey: SettingsKey.meetingAlert) as? Bool ?? false
        meetingAlertMinutes = min(max(defaults.object(forKey: SettingsKey.meetingAlertMinutes) as? Int ?? 1, 0), 15)
        screenTimeEnabled = defaults.object(forKey: SettingsKey.screenTimeEnabled) as? Bool ?? true
        quickSearchEngine = defaults.string(forKey: SettingsKey.quickSearchEngine) ?? "google"
        launcherApps = defaults.string(forKey: SettingsKey.launcherApps) ?? ""
        colorFormat = defaults.string(forKey: SettingsKey.colorFormat) ?? "hex"
        driveActivity = defaults.object(forKey: SettingsKey.driveActivity) as? Bool ?? true
        screenshotToShelf = defaults.object(forKey: SettingsKey.screenshotToShelf) as? Bool ?? false
        headerButtons = defaults.string(forKey: SettingsKey.headerButtons) ?? "battery,output,keepAwake,actions,pin,lock"
        pillScale = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillScale) as? Double ?? 1.0, 0.8, 1.3)
        pillHeightOffset = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillHeightOffset) as? Double ?? 0, -6, 12)
        pillWidth = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillWidth) as? Double ?? 185, 150, 420)
        pillHeight = AppSettings.clamp(defaults.object(forKey: SettingsKey.pillHeight) as? Double ?? 36, 28, 44)
        unlockActivity = defaults.object(forKey: SettingsKey.unlockActivity) as? Bool ?? true
        lockScreenWidgets = defaults.object(forKey: SettingsKey.lockScreenWidgets) as? Bool ?? true
        lockScreenWeather = defaults.object(forKey: SettingsKey.lockScreenWeather) as? Bool ?? true
        lockScreenBatteries = defaults.object(forKey: SettingsKey.lockScreenBatteries) as? Bool ?? true
        screenSharingPrivacy = defaults.object(forKey: SettingsKey.screenSharingPrivacy) as? Bool ?? false
        hideWhileMirroring = defaults.object(forKey: SettingsKey.hideWhileMirroring) as? Bool ?? false
        fullscreenScope = defaults.string(forKey: SettingsKey.fullscreenScope).flatMap { FullscreenScope(rawValue: $0) } ?? .allApps
        autoCollapse = defaults.object(forKey: SettingsKey.autoCollapse) as? Bool ?? true
        quietDuringFocus = defaults.object(forKey: SettingsKey.quietDuringFocus) as? Bool ?? false
        peekOnHover = defaults.object(forKey: SettingsKey.peekOnHover) as? Bool ?? false
        mediaKeysControlPlayer = defaults.object(forKey: SettingsKey.mediaKeysControlPlayer) as? Bool ?? true
        preventMusicAutoLaunch = defaults.object(forKey: SettingsKey.preventMusicAutoLaunch) as? Bool ?? false
        meetingOnlyWithLink = defaults.object(forKey: SettingsKey.meetingOnlyWithLink) as? Bool ?? true
        hiddenCalendars = defaults.string(forKey: SettingsKey.hiddenCalendars) ?? ""
        calendarHotkeys = defaults.object(forKey: SettingsKey.calendarHotkeys) as? Bool ?? true
        timerHoverControls = defaults.object(forKey: SettingsKey.timerHoverControls) as? Bool ?? true
        clipboardCaptureSound = defaults.object(forKey: SettingsKey.clipboardCaptureSound) as? Bool ?? false
        shelfRetention = defaults.string(forKey: SettingsKey.shelfRetention).flatMap { ShelfRetention(rawValue: $0) } ?? .untilCleared
        screenshotFolder = defaults.string(forKey: SettingsKey.screenshotFolder) ?? ""
        unplugActivity = defaults.object(forKey: SettingsKey.unplugActivity) as? Bool ?? true
        fullChargeLevel = min(max(defaults.object(forKey: SettingsKey.fullChargeLevel) as? Int ?? 100, 80), 100)
        clockContent = defaults.string(forKey: SettingsKey.clockContent).flatMap { ClockContent(rawValue: $0) } ?? .time
        clockWithActivities = defaults.object(forKey: SettingsKey.clockWithActivities) as? Bool ?? false
        panelWidth = AppSettings.clamp(defaults.object(forKey: SettingsKey.panelWidth) as? Double ?? 640, 520, 820)
        panelSizing = defaults.string(forKey: SettingsKey.panelSizing).flatMap { PanelSizing(rawValue: $0) } ?? .fixed
        panelMaxHeight = AppSettings.clamp(defaults.object(forKey: SettingsKey.panelMaxHeight) as? Double ?? 190, 150, 320)
        panelFillHex = defaults.string(forKey: SettingsKey.panelFillHex) ?? ""
        pillMatchesPanel = defaults.object(forKey: SettingsKey.pillMatchesPanel) as? Bool ?? false
        trackInfoMode = defaults.string(forKey: SettingsKey.trackInfoMode).flatMap { TrackInfoMode(rawValue: $0) } ?? .onChange
        desktopLyrics = defaults.object(forKey: SettingsKey.desktopLyrics) as? Bool ?? false
        edgeGlow = defaults.object(forKey: SettingsKey.edgeGlow) as? Bool ?? false
        alertSounds = defaults.string(forKey: SettingsKey.alertSounds) ?? ""
        hotkeyBindings = defaults.string(forKey: SettingsKey.hotkeyBindings) ?? ""
        knockEnabled = defaults.object(forKey: SettingsKey.knockEnabled) as? Bool ?? false
        knockKey = defaults.string(forKey: SettingsKey.knockKey).flatMap { KnockKey(rawValue: $0) } ?? .control
        knockActions = defaults.string(forKey: SettingsKey.knockActions) ?? "1=togglePanel,2=clipboard,3=commandPalette"
        copyTwiceToOpen = defaults.object(forKey: SettingsKey.copyTwiceToOpen) as? Bool ?? false
        offerCleanCopy = defaults.object(forKey: SettingsKey.offerCleanCopy) as? Bool ?? false
        customSearchEngines = defaults.string(forKey: SettingsKey.customSearchEngines) ?? ""
        homeCards = defaults.string(forKey: SettingsKey.homeCards) ?? ""
        homeColumns = min(max(defaults.object(forKey: SettingsKey.homeColumns) as? Int ?? 3, 2), 4)
        worldClocks = defaults.string(forKey: SettingsKey.worldClocks) ?? "America/New_York,Europe/London,Asia/Tokyo"
        savedLinks = defaults.string(forKey: SettingsKey.savedLinks) ?? ""
        repeatTimer = defaults.object(forKey: SettingsKey.repeatTimer) as? Bool ?? false
        repeatAlarm = defaults.object(forKey: SettingsKey.repeatAlarm) as? Bool ?? false
        pomodoroOnly = defaults.object(forKey: SettingsKey.pomodoroOnly) as? Bool ?? false
        aiLimitWarnings = defaults.object(forKey: SettingsKey.aiLimitWarnings) as? Bool ?? true
        aiLimitWarnPercent = min(max(defaults.object(forKey: SettingsKey.aiLimitWarnPercent) as? Int ?? 80, 50), 95)
        aiMenuBarReadout = defaults.object(forKey: SettingsKey.aiMenuBarReadout) as? Bool ?? false
        aiHidePersonalInfo = defaults.object(forKey: SettingsKey.aiHidePersonalInfo) as? Bool ?? false
        batteryInMenuBar = defaults.object(forKey: SettingsKey.batteryInMenuBar) as? Bool ?? false
        drainWarnings = defaults.object(forKey: SettingsKey.drainWarnings) as? Bool ?? false
        dmgInstallOffer = defaults.object(forKey: SettingsKey.dmgInstallOffer) as? Bool ?? true
        nextMeetingInMenuBar = defaults.object(forKey: SettingsKey.nextMeetingInMenuBar) as? Bool ?? false
        listeningHistory = defaults.object(forKey: SettingsKey.listeningHistory) as? Bool ?? true
        defaultMusicApp = defaults.string(forKey: SettingsKey.defaultMusicApp) ?? ""
    }

    /// "Restore Defaults" for one settings page: forgets those keys and reloads.
    func restoreDefaults(_ keys: [String]) {
        for key in keys { defaults.removeObject(forKey: key) }
        reloadFromDefaults()
        for key in keys { defaults.removeObject(forKey: key) }   // keep them unset so future default changes apply
    }

    /// Every stored setting as JSON (keys "dn.*").
    func exportJSON() -> Data {
        var dict: [String: Any] = [:]
        for key in AppSettings.allKeys {
            if let value = defaults.object(forKey: key) { dict[key] = value }
        }
        return (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// Applies a file made by `exportJSON()`. Unknown keys are ignored. Returns false for invalid data.
    @discardableResult
    func importJSON(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else { return false }
        let known = Set(AppSettings.allKeys)
        for (key, value) in dict where known.contains(key) {
            defaults.set(value, forKey: key)
        }
        reloadFromDefaults()
        return true
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
        notchDisplayStyle = .notch
        panelTabs = AppSettings.defaultPanelTabs
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
        materialPreset = .carbon
        panelTranslucency = 1.0
        animationStyle = .calm
        animationSpeed = 1.0
        colorCodedLevels = false
        closedPillClock = false
        timeFormat = .system
        helloIntro = false
        defaultTab = "previous"
        openOnCurrentActivity = true
        idleTimeout = 0
        invisibleUntilHover = false
        notificationDuration = 4.5
        lyricsOffset = 0
        pomodoroAutoContinue = true
        breakLookAway = false
        breakStandUp = false
        standUpMinutes = 60
        breakDrinkWater = false
        drinkWaterMinutes = 45
        lowBatteryThreshold = 20
        fullChargeActivity = false
        accessoryAlerts = true
        clipboardIgnoredApps = AppSettings.defaultIgnoredApps
        clipboardAutoClearMinutes = 0
        pasteWithNumbers = true
        meetingAlert = false
        meetingAlertMinutes = 1
        screenTimeEnabled = true
        quickSearchEngine = "google"
        launcherApps = ""
        colorFormat = "hex"
        driveActivity = true
        screenshotToShelf = false
        headerButtons = "battery,output,keepAwake,actions,pin,lock"
        pillScale = 1.0
        pillHeightOffset = 0
        pillWidth = 185
        pillHeight = 36
        unlockActivity = true
        lockScreenWidgets = true
        lockScreenWeather = true
        lockScreenBatteries = true
        screenSharingPrivacy = false
        hideWhileMirroring = false
        fullscreenScope = .allApps
        autoCollapse = true
        quietDuringFocus = false
        peekOnHover = false
        mediaKeysControlPlayer = true
        preventMusicAutoLaunch = false
        meetingOnlyWithLink = true
        hiddenCalendars = ""
        calendarHotkeys = true
        timerHoverControls = true
        clipboardCaptureSound = false
        shelfRetention = .untilCleared
        screenshotFolder = ""
        unplugActivity = true
        fullChargeLevel = 100
        clockContent = .time
        clockWithActivities = false
        panelWidth = 640
        panelSizing = .fixed
        panelMaxHeight = 190
        panelFillHex = ""
        pillMatchesPanel = false
        trackInfoMode = .onChange
        desktopLyrics = false
        edgeGlow = false
        alertSounds = ""
        hotkeyBindings = ""
        knockEnabled = false
        knockKey = .control
        knockActions = "1=togglePanel,2=clipboard,3=commandPalette"
        copyTwiceToOpen = false
        offerCleanCopy = false
        customSearchEngines = ""
        homeCards = ""
        homeColumns = 3
        worldClocks = "America/New_York,Europe/London,Asia/Tokyo"
        savedLinks = ""
        repeatTimer = false
        repeatAlarm = false
        pomodoroOnly = false
        aiLimitWarnings = true
        aiLimitWarnPercent = 80
        aiMenuBarReadout = false
        aiHidePersonalInfo = false
        batteryInMenuBar = false
        drainWarnings = false
        dmgInstallOffer = true
        nextMeetingInMenuBar = false
        listeningHistory = true
        defaultMusicApp = ""
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        if value.isNaN { return lower }
        return min(max(value, lower), upper)
    }
}
