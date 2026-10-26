import XCTest
@testable import DynaNotchCore

final class CalendarTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func item(_ id: String, start: TimeInterval, end: TimeInterval, allDay: Bool = false) -> CalendarItem {
        CalendarItem(id: id, title: id, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), isAllDay: allDay)
    }

    func testAlertTrackerWindow() {
        var t = CalendarAlertTracker()
        let events = [
            item("past", start: -60, end: 600),
            item("now", start: 0, end: 600),
            item("soon", start: 120, end: 900),
            item("edge", start: 300, end: 900),
            item("later", start: 301, end: 900),
            item("allday", start: 60, end: 86_400, allDay: true),
        ]
        XCTAssertEqual(t.due(events: events, now: now, leadMinutes: 5).map(\.id), ["soon", "edge"])
    }

    func testAlertTrackerReturnsOnce() {
        var t = CalendarAlertTracker()
        let events = [item("soon", start: 120, end: 900)]
        XCTAssertEqual(t.due(events: events, now: now, leadMinutes: 5).count, 1)
        XCTAssertEqual(t.due(events: events, now: now.addingTimeInterval(30), leadMinutes: 5).count, 0)
    }

    func testAlertTrackerLaterEventBecomesDue() {
        var t = CalendarAlertTracker()
        let events = [item("a", start: 120, end: 900), item("b", start: 600, end: 900)]
        XCTAssertEqual(t.due(events: events, now: now, leadMinutes: 5).map(\.id), ["a"])
        XCTAssertEqual(t.due(events: events, now: now.addingTimeInterval(400), leadMinutes: 5).map(\.id), ["b"])
    }

    func testAlertTrackerRescheduledAlertsAgain() {
        var t = CalendarAlertTracker()
        XCTAssertEqual(t.due(events: [item("a", start: 120, end: 900)], now: now, leadMinutes: 5).count, 1)
        XCTAssertEqual(t.due(events: [item("a", start: 180, end: 900)], now: now, leadMinutes: 5).count, 1)
    }

    func testCalendarFilterUpcoming() {
        let items = [
            item("ended", start: -7200, end: -3600),
            item("later", start: 7200, end: 9000),
            item("ongoing", start: -600, end: 600),
            item("allday", start: -36_000, end: 50_400, allDay: true),
            item("next", start: 1800, end: 3600),
        ]
        XCTAssertEqual(CalendarFilter.upcoming(items, now: now, limit: 10).map(\.id), ["allday", "ongoing", "next", "later"])
        XCTAssertEqual(CalendarFilter.upcoming(items, now: now, limit: 2).map(\.id), ["allday", "ongoing"])
        XCTAssertEqual(CalendarFilter.upcoming(items, now: now, limit: 0), [])
    }

    func testFutureAllDayNotPromoted() {
        let items = [
            item("tomorrow", start: 86_400, end: 172_800, allDay: true),
            item("meeting", start: 3600, end: 7200),
        ]
        XCTAssertEqual(CalendarFilter.upcoming(items, now: now, limit: 5).map(\.id), ["meeting", "tomorrow"])
    }

    func testCalendarItemDefaults() {
        let i = item("x", start: 0, end: 1)
        XCTAssertNil(i.location)
        XCTAssertNil(i.colorHex)
        XCTAssertEqual(i.id, "x")
    }
}

final class ColorMathTests: XCTestCase {
    func assertRGB(_ a: RGB, _ b: RGB, accuracy: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.r, b.r, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.g, b.g, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.b, b.b, accuracy: accuracy, file: file, line: line)
    }

    func testHSBPrimaries() {
        let red = ColorMath.hsb(RGB(r: 1, g: 0, b: 0))
        XCTAssertEqual(red.h, 0, accuracy: 1e-9); XCTAssertEqual(red.s, 1); XCTAssertEqual(red.b, 1)
        XCTAssertEqual(ColorMath.hsb(RGB(r: 0, g: 1, b: 0)).h, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(ColorMath.hsb(RGB(r: 0, g: 0, b: 1)).h, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(ColorMath.hsb(RGB(r: 1, g: 0, b: 1)).h, 5.0 / 6.0, accuracy: 1e-9)
        let grey = ColorMath.hsb(RGB(r: 0.5, g: 0.5, b: 0.5))
        XCTAssertEqual(grey.s, 0); XCTAssertEqual(grey.b, 0.5); XCTAssertEqual(grey.h, 0)
        XCTAssertEqual(ColorMath.hsb(RGB(r: 0, g: 0, b: 0)).s, 0)
    }

    func testRGBFromHSB() {
        assertRGB(ColorMath.rgb(h: 0, s: 1, b: 1), RGB(r: 1, g: 0, b: 0))
        assertRGB(ColorMath.rgb(h: 1.0 / 3.0, s: 1, b: 1), RGB(r: 0, g: 1, b: 0))
        assertRGB(ColorMath.rgb(h: 2.0 / 3.0, s: 1, b: 1), RGB(r: 0, g: 0, b: 1))
        assertRGB(ColorMath.rgb(h: 1.0, s: 1, b: 1), RGB(r: 1, g: 0, b: 0))
        assertRGB(ColorMath.rgb(h: 0.3, s: 0, b: 0.4), RGB(r: 0.4, g: 0.4, b: 0.4))
    }

    func testRoundTrip() {
        let samples = [RGB(r: 0.2, g: 0.4, b: 0.6), RGB(r: 0.9, g: 0.1, b: 0.3), RGB(r: 0.33, g: 0.8, b: 0.12),
                       RGB(r: 0.7, g: 0.7, b: 0.2), RGB(r: 0.05, g: 0.6, b: 0.6)]
        for c in samples {
            let hsb = ColorMath.hsb(c)
            assertRGB(ColorMath.rgb(h: hsb.h, s: hsb.s, b: hsb.b), c)
        }
    }

    func testAccentEmptyIsWhite() {
        XCTAssertEqual(ColorMath.accent(fromPixels: []), RGB(r: 1, g: 1, b: 1))
    }

    func testAccentPrefersSaturatedPixels() {
        var pixels = Array(repeating: RGB(r: 0.5, g: 0.5, b: 0.5), count: 20)
        pixels.append(RGB(r: 0.9, g: 0.1, b: 0.1))
        pixels.append(RGB(r: 0.9, g: 0.1, b: 0.1))
        let accent = ColorMath.accent(fromPixels: pixels)
        XCTAssertGreaterThan(accent.r, accent.g + 0.2)
        XCTAssertGreaterThan(accent.r, accent.b + 0.2)
    }

    func testAccentLiftsBrightness() {
        let dark = ColorMath.accent(fromPixels: [RGB(r: 0.2, g: 0.0, b: 0.0)])
        let hsb = ColorMath.hsb(dark)
        XCTAssertEqual(hsb.b, 0.55, accuracy: 1e-9)
        XCTAssertEqual(hsb.h, 0, accuracy: 1e-9)
    }

    func testAccentCapsSaturation() {
        let accent = ColorMath.accent(fromPixels: [RGB(r: 0, g: 0, b: 1)])
        let hsb = ColorMath.hsb(accent)
        XCTAssertEqual(hsb.s, 0.9, accuracy: 1e-9)
        XCTAssertEqual(hsb.b, 1, accuracy: 1e-9)
        XCTAssertEqual(hsb.h, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testAccentGreysStillCount() {
        let accent = ColorMath.accent(fromPixels: [RGB(r: 0.8, g: 0.8, b: 0.8)])
        assertRGB(accent, RGB(r: 0.8, g: 0.8, b: 0.8))
        let black = ColorMath.accent(fromPixels: [RGB(r: 0, g: 0, b: 0)])
        assertRGB(black, RGB(r: 0.55, g: 0.55, b: 0.55))
    }
}

final class SettingsTests: XCTestCase {
    func testDisplayModeTitles() {
        XCTAssertEqual(DisplayMode.notchOrMain.title, "Built-in (notch) display")
        XCTAssertEqual(DisplayMode.main.title, "Main display")
        XCTAssertEqual(DisplayMode.followMouse.title, "Follow mouse")
        XCTAssertEqual(DisplayMode.external.title, "External display")
        XCTAssertEqual(DisplayMode.allCases.count, 4)
    }

    func testArtworkAndVisualizerTitles() {
        XCTAssertEqual(ArtworkStyle.rounded.title, "Rounded")
        XCTAssertEqual(ArtworkStyle.circle.title, "Vinyl")
        XCTAssertEqual(VisualizerStyle.bars.title, "Bars")
        XCTAssertEqual(VisualizerStyle.none.title, "Off")
    }

    func testRawValuesRoundTrip() {
        for m in DisplayMode.allCases { XCTAssertEqual(DisplayMode(rawValue: m.rawValue), m) }
        XCTAssertEqual(HUDStyle(rawValue: "expanded"), .expanded)
        XCTAssertEqual(ArtworkStyle(rawValue: "circle"), .circle)
        XCTAssertEqual(VisualizerStyle(rawValue: "none"), VisualizerStyle.none)
        XCTAssertNil(DisplayMode(rawValue: "bogus"))
    }

    func testSettingsKeys() {
        XCTAssertEqual(SettingsKey.showMenuBarIcon, "dn.showMenuBarIcon")
        XCTAssertEqual(SettingsKey.calendarLeadMinutes, "dn.calendarLeadMinutes")
        XCTAssertEqual(SettingsKey.hudStyle, "dn.hudStyle")
        XCTAssertEqual(SettingsKey.all.count, 152)
        XCTAssertEqual(Set(SettingsKey.all).count, SettingsKey.all.count)
        XCTAssertTrue(SettingsKey.all.allSatisfy { $0.hasPrefix("dn.") && $0.count > 3 })
    }

    func testSettingsKeyNamesMatchProperties() {
        let names = ["showMenuBarIcon", "displayMode", "hideInFullscreen", "showOnNonNotchDisplays", "hapticFeedback",
                     "hasCompletedOnboarding", "expandOnHover", "hoverDelay", "collapseDelay", "clickToExpand",
                     "gesturesEnabled", "expandedShowsCalendar", "expandedShowsBattery", "nowPlayingEnabled",
                     "showCompactNowPlaying", "showTrackPeek", "artworkStyle", "visualizerStyle", "artworkGlow",
                     "pausedLingerSeconds", "hudEnabled", "replaceSystemHUD", "hudStyle", "volumeHUD", "brightnessHUD",
                     "chargingActivity", "lowBatteryActivity", "bluetoothActivity", "focusActivity", "calendarActivity",
                     "calendarLeadMinutes", "calendarEnabled",
                     "nonNotchStyle", "panelTabs", "rememberLastTab", "lastTab", "hotkeysEnabled",
                     "lyricsEnabled", "lyricsInCompact", "pomodoroWorkMinutes", "pomodoroShortBreakMinutes",
                     "pomodoroLongBreakMinutes", "pomodoroCycles", "timerSound", "timerOverNowPlaying", "showCompactTimer",
                     "clipboardEnabled", "clipboardLimit", "cleanLinks", "pasteOnClick", "shelfEnabled",
                     "shelfRemoveOnDragOut", "weatherEnabled", "weatherCity", "temperatureUnit", "aiUsageEnabled",
                     "downloadActivity", "privacyActivity", "capsLockActivity", "notifyActivity",
                     "islandMaterial", "hasSeenWelcome",
                     "materialPreset", "panelTranslucency", "animationStyle", "animationSpeed", "colorCodedLevels", "closedPillClock", "timeFormat", "helloIntro", "defaultTab", "openOnCurrentActivity", "idleTimeout", "invisibleUntilHover", "notificationDuration", "lyricsOffset", "pomodoroAutoContinue", "breakLookAway", "breakStandUp", "standUpMinutes", "breakDrinkWater", "drinkWaterMinutes", "lowBatteryThreshold", "fullChargeActivity", "accessoryAlerts", "clipboardIgnoredApps", "clipboardAutoClearMinutes", "pasteWithNumbers", "meetingAlert", "meetingAlertMinutes", "screenTimeEnabled", "quickSearchEngine", "launcherApps", "colorFormat", "driveActivity", "screenshotToShelf", "headerButtons", "notchDisplayStyle", "pillScale", "pillHeightOffset", "screenSharingPrivacy", "hideWhileMirroring", "fullscreenScope", "autoCollapse", "quietDuringFocus", "peekOnHover", "mediaKeysControlPlayer", "preventMusicAutoLaunch", "meetingOnlyWithLink", "hiddenCalendars", "calendarHotkeys", "timerHoverControls", "clipboardCaptureSound", "shelfRetention", "screenshotFolder", "unplugActivity", "fullChargeLevel", "clockContent", "clockWithActivities", "panelWidth", "panelSizing", "panelMaxHeight", "panelFillHex", "pillMatchesPanel", "trackInfoMode", "desktopLyrics", "edgeGlow", "alertSounds", "hotkeyBindings", "knockEnabled", "knockKey", "knockActions", "copyTwiceToOpen", "offerCleanCopy", "customSearchEngines", "homeCards", "homeColumns", "worldClocks", "savedLinks", "repeatTimer", "repeatAlarm", "pomodoroOnly", "aiLimitWarnings", "aiLimitWarnPercent", "aiMenuBarReadout", "aiHidePersonalInfo", "batteryInMenuBar", "drainWarnings", "dmgInstallOffer", "nextMeetingInMenuBar", "listeningHistory", "defaultMusicApp"]
        XCTAssertEqual(SettingsKey.all, names.map { "dn." + $0 })
    }
}
