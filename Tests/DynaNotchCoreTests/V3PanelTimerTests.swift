import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import DynaNotchCore

final class V3PanelTimerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let notch = NotchMetrics(width: 200, height: 32, hasPhysicalNotch: true)

    // MARK: Panel tabs

    func testPanelTabParseList() {
        XCTAssertEqual(PanelTab.parseList("home, timer,bogus,home"), [.home, .timer])
        XCTAssertEqual(PanelTab.parseList(""), PanelTab.allCases)
        XCTAssertEqual(PanelTab.parseList("nope"), PanelTab.allCases)
        XCTAssertEqual(PanelTab.serialize([.clipboard, .aiUsage]), "clipboard,aiUsage")
        XCTAssertEqual(PanelTab.parseList(PanelTab.serialize(PanelTab.allCases)), PanelTab.allCases)
    }

    func testPanelTabMetadata() {
        for tab in PanelTab.allCases {
            XCTAssertFalse(tab.title.isEmpty)
            XCTAssertFalse(tab.symbolName.isEmpty)
        }
        XCTAssertEqual(PanelTab.aiUsage.title, "AI Usage")
    }

    // MARK: Engine (v3)

    func testTimerPresentationPriority() {
        var e = IslandEngine()
        e.isTimerActive = true
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .timer)
        e.isNowPlayingActive = true
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .timer)
        e.prefersTimerOverMusic = false
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .nowPlaying)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: false), .timer)
        e.post(.toggle(symbol: "capslock.fill", label: "Caps Lock", on: true), now: t0)
        if case .activity = e.presentation(now: t0, showNowPlayingCompact: true) {} else { XCTFail("activity wins") }
    }

    func testLyricsPresentation() {
        var e = IslandEngine()
        e.isNowPlayingActive = true
        e.hasLyricLine = true
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .lyrics)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: false), .idle)
        e.startPeek(now: t0, duration: 2)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .peek)
        XCTAssertTrue(IslandPresentation.lyrics.isCompactLike)
        XCTAssertTrue(IslandPresentation.timer.isCompactLike)
    }

    func testNewActivityMetadata() {
        let kinds: [ActivityKind] = [
            .timerFinished(label: "Tea"), .notification(title: "Build", body: "done", symbol: "hammer"),
            .download(name: "a.zip", finished: true), .sensor(.camera, active: true),
            .toggle(symbol: "mic.slash.fill", label: "Mic", on: false),
        ]
        XCTAssertEqual(kinds.map(\.category), [.timer, .notification, .download, .privacy, .toggle])
        XCTAssertEqual(kinds.map(\.priority), [95, 85, 65, 88, 98])
        XCTAssertEqual(kinds.map(\.defaultDuration), [6.0, 4.5, 3.5, 3.0, 1.5])
        XCTAssertEqual(SensorKind.microphone.symbolName, "mic.fill")
    }

    func testV3LayoutSizes() {
        XCTAssertEqual(IslandLayout.size(for: .timer, notch: notch, hudStyle: .compact),
                       CGSize(width: 200 + 12 + 128, height: 32))
        XCTAssertEqual(IslandLayout.size(for: .lyrics, notch: notch, hudStyle: .compact),
                       CGSize(width: 200 + 16 + 88, height: 58))
        let n = LiveActivity(kind: .notification(title: "a", body: "b", symbol: "bell"), postedAt: t0, expiresAt: t0 + 5)
        XCTAssertEqual(IslandLayout.size(for: .activity(n), notch: notch, hudStyle: .compact),
                       CGSize(width: 200 + 16 + 220, height: 72))
        XCTAssertEqual(IslandLayout.radii(for: .activity(n), hudStyle: .compact), IslandRadii(top: 8, bottom: 16))
        let d = LiveActivity(kind: .download(name: "x", finished: false), postedAt: t0, expiresAt: t0 + 5)
        XCTAssertEqual(IslandLayout.sideWidth(for: .activity(d), hudStyle: .compact), 84)
        XCTAssertEqual(IslandLayout.radii(for: .timer, hudStyle: .compact), IslandRadii(top: 6, bottom: 11))
    }

    func testScreenRectTopInset() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let r = IslandLayout.screenRect(for: CGSize(width: 200, height: 32), screenFrame: screen, topInset: 6)
        XCTAssertEqual(r, CGRect(x: 400, y: 762, width: 200, height: 32))
        XCTAssertEqual(NonNotchStyle.allCases.count, 2)
    }

    // MARK: Timer

    func testCountdownLifecycle() {
        var t = TimerEngine()
        t.startCountdown(seconds: 60, label: "Tea", now: t0)
        XCTAssertTrue(t.isActive)
        XCTAssertEqual(t.state?.remaining(at: t0 + 15), 45)
        XCTAssertEqual(t.state?.displayTime(at: t0 + 14.2), "0:46")
        XCTAssertEqual(t.nextDeadline(now: t0), t0 + 60)
        XCTAssertNil(t.tick(now: t0 + 59))
        XCTAssertEqual(t.tick(now: t0 + 60), .countdownFinished(label: "Tea"))
        XCTAssertFalse(t.isActive)
    }

    func testPauseResume() {
        var t = TimerEngine()
        t.startCountdown(seconds: 100, label: "", now: t0)
        t.pause(now: t0 + 30)
        XCTAssertEqual(t.state?.isRunning, false)
        XCTAssertEqual(t.state?.remaining(at: t0 + 500), 70)
        XCTAssertNil(t.tick(now: t0 + 500))
        XCTAssertNil(t.nextDeadline(now: t0 + 500))
        t.resume(now: t0 + 1000)
        XCTAssertEqual(t.nextDeadline(now: t0 + 1000), t0 + 1070)
        t.toggle(now: t0 + 1010)
        XCTAssertEqual(t.state?.remaining(at: t0 + 2000), 60)
    }

    func testAddTimeAndZeroCountdown() {
        var t = TimerEngine()
        t.startCountdown(seconds: 0, label: "", now: t0)
        XCTAssertFalse(t.isActive)
        t.startCountdown(seconds: 60, label: "", now: t0)
        t.addTime(60, now: t0)
        XCTAssertEqual(t.state?.remaining(at: t0), 120)
        XCTAssertEqual(t.state?.progress(at: t0 + 60), 0.5)
    }

    func testPomodoroCycle() {
        var t = TimerEngine(config: PomodoroConfig(work: 10, shortBreak: 2, longBreak: 5, cyclesBeforeLongBreak: 2))
        t.startPomodoro(now: t0)
        XCTAssertEqual(t.state?.phase, .work)
        XCTAssertEqual(t.tick(now: t0 + 10), .phaseFinished(from: .work, to: .shortBreak))
        XCTAssertEqual(t.state?.startedAt, t0 + 10)
        XCTAssertEqual(t.tick(now: t0 + 12), .phaseFinished(from: .shortBreak, to: .work))
        XCTAssertEqual(t.tick(now: t0 + 22), .phaseFinished(from: .work, to: .longBreak))
        XCTAssertEqual(t.state?.completedWorkSessions, 2)
        XCTAssertEqual(t.state?.duration, 5)
        XCTAssertEqual(t.state?.label, "Long Break")
    }

    func testPomodoroLateTickStartsAtFinishTime() {
        var t = TimerEngine(config: PomodoroConfig(work: 10, shortBreak: 5))
        t.startPomodoro(now: t0)
        _ = t.tick(now: t0 + 12)
        XCTAssertEqual(t.state?.startedAt, t0 + 10)
        XCTAssertEqual(t.state?.remaining(at: t0 + 12), 3)
    }

    func testSkipPhase() {
        var t = TimerEngine()
        XCTAssertNil(t.skipPhase(now: t0))
        t.startPomodoro(now: t0)
        XCTAssertEqual(t.skipPhase(now: t0 + 1), .phaseFinished(from: .work, to: .shortBreak))
        XCTAssertEqual(t.state?.startedAt, t0 + 1)
    }

    func testStopwatch() {
        var t = TimerEngine()
        t.startStopwatch(now: t0)
        XCTAssertEqual(t.state?.remaining(at: t0 + 75), 75)
        XCTAssertEqual(t.state?.displayTime(at: t0 + 75), "1:15")
        XCTAssertEqual(t.state?.progress(at: t0 + 75), 0)
        XCTAssertNil(t.tick(now: t0 + 1_000_000))
        XCTAssertNil(t.nextDeadline(now: t0))
        t.addTime(60, now: t0)
        XCTAssertEqual(t.state?.duration, 0)
        t.reset()
        XCTAssertNil(t.state)
    }

    // MARK: Notify / downloads / shelf

    func testNotifyURL() {
        let n = NotifyURL.parse(URL(string: "dynanotch://notify?title=Build%20done&body=42%20tests&symbol=hammer.fill&duration=99")!)
        XCTAssertEqual(n, NotchNotification(title: "Build done", body: "42 tests", symbol: "hammer.fill", duration: 30))
        let bodyOnly = NotifyURL.parse(URL(string: "dynanotch://notify?body=hi")!)
        XCTAssertEqual(bodyOnly?.title, "hi")
        XCTAssertEqual(bodyOnly?.body, "")
        XCTAssertEqual(bodyOnly?.symbol, "bell.fill")
        XCTAssertNil(NotifyURL.parse(URL(string: "dynanotch://notify")!))
        XCTAssertNil(NotifyURL.parse(URL(string: "dynanotch://expand?title=x")!))
        XCTAssertNil(NotifyURL.parse(URL(string: "https://notify?title=x")!))
    }

    func testDownloadNames() {
        XCTAssertTrue(DownloadNames.isPartial("a.zip.download"))
        XCTAssertTrue(DownloadNames.isPartial("Unconfirmed 1.crdownload"))
        XCTAssertTrue(DownloadNames.isPartial("x.PART"))
        XCTAssertFalse(DownloadNames.isPartial("a.zip"))
        XCTAssertFalse(DownloadNames.isPartial(".download"))
        XCTAssertEqual(DownloadNames.finalName("a.zip.download"), "a.zip")
        XCTAssertEqual(DownloadNames.finalName("a.zip"), "a.zip")
    }

    func testDownloadTracker() {
        var d = DownloadTracker()
        XCTAssertTrue(d.update(["old.zip", "x.crdownload"]).started.isEmpty)
        let s = d.update(["old.zip", "x.crdownload", "big.dmg.download"])
        XCTAssertEqual(s.started, ["big.dmg.download"])
        XCTAssertEqual(s.finished, [])
        let f = d.update(["old.zip", "x.crdownload", "big.dmg"])
        XCTAssertEqual(f.finished, ["big.dmg"])
        let cancelled = d.update(["old.zip", "big.dmg"])
        XCTAssertEqual(cancelled.finished, [])
    }

    func testShelfAdding() {
        let a = ShelfItem(path: "/a.txt", addedAt: t0)
        let items = ShelfList.adding(["/b.png", "/a.txt", "/b.png", ""], to: [a], now: t0 + 1)
        XCTAssertEqual(items.map(\.path), ["/b.png", "/a.txt"])
        XCTAssertEqual(items[1].id, a.id)
        XCTAssertEqual(items[0].name, "b.png")
    }
}
