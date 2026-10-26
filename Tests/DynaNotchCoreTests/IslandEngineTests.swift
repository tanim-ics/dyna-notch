import XCTest
@testable import DynaNotchCore

final class ActivityKindTests: XCTestCase {
    let all: [ActivityKind] = [
        .hud(.volume, level: 0.5, muted: false),
        .lowBattery(level: 0.1),
        .charging(level: 0.5, isCharging: true, pluggedIn: true),
        .bluetooth(name: "AirPods", device: .airpods, battery: nil, connected: true),
        .focus(name: "Work", symbol: "briefcase.fill", enabled: true),
        .calendar(title: "Standup", minutesUntil: 5),
    ]

    func testCategories() {
        XCTAssertEqual(all.map(\.category), [.hud, .power, .power, .bluetooth, .focus, .calendar])
    }

    func testDurations() {
        XCTAssertEqual(all.map(\.defaultDuration), [1.6, 4.0, 3.0, 3.5, 2.5, 6.0])
    }

    func testPriorities() {
        XCTAssertEqual(all.map(\.priority), [100, 90, 80, 70, 60, 50])
    }

    func testLiveActivityEquality() {
        let id = UUID()
        let t = Date(timeIntervalSince1970: 0)
        let a = LiveActivity(id: id, kind: .lowBattery(level: 0.1), postedAt: t, expiresAt: t)
        var b = a
        XCTAssertEqual(a, b)
        b.kind = .lowBattery(level: 0.2)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(IslandPresentation.activity(a), .activity(b))
    }

    func testIsCompactLike() {
        let t = Date()
        let a = LiveActivity(kind: .lowBattery(level: 0.1), postedAt: t, expiresAt: t)
        XCTAssertTrue(IslandPresentation.nowPlaying.isCompactLike)
        XCTAssertTrue(IslandPresentation.peek.isCompactLike)
        XCTAssertTrue(IslandPresentation.activity(a).isCompactLike)
        XCTAssertFalse(IslandPresentation.idle.isCompactLike)
        XCTAssertFalse(IslandPresentation.hidden.isCompactLike)
        XCTAssertFalse(IslandPresentation.expanded.isCompactLike)
    }
}

final class IslandEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 10_000)

    func testDefaults() {
        let e = IslandEngine()
        XCTAssertTrue(e.activities.isEmpty)
        XCTAssertFalse(e.isExpanded)
        XCTAssertFalse(e.isNowPlayingActive)
        XCTAssertFalse(e.isSuppressed)
        XCTAssertNil(e.peekUntil)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .idle)
        XCTAssertNil(e.nextDeadline(now: t0))
    }

    func testPostUsesDefaultDuration() {
        var e = IslandEngine()
        let a = e.post(.focus(name: "Work", symbol: "briefcase.fill", enabled: true), now: t0)
        XCTAssertEqual(a.postedAt, t0)
        XCTAssertEqual(a.expiresAt, t0.addingTimeInterval(2.5))
        XCTAssertEqual(e.activities, [a])
    }

    func testPostCustomDuration() {
        var e = IslandEngine()
        let a = e.post(.calendar(title: "x", minutesUntil: 1), now: t0, duration: 10)
        XCTAssertEqual(a.expiresAt, t0.addingTimeInterval(10))
    }

    func testSameCategoryReplacementKeepsId() {
        var e = IslandEngine()
        let first = e.post(.hud(.volume, level: 0.2, muted: false), now: t0)
        let later = t0.addingTimeInterval(0.5)
        let second = e.post(.hud(.brightness, level: 0.8, muted: false), now: later)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(e.activities.count, 1)
        XCTAssertEqual(e.activities[0].kind, .hud(.brightness, level: 0.8, muted: false))
        XCTAssertEqual(e.activities[0].postedAt, later)
        XCTAssertEqual(e.activities[0].expiresAt, later.addingTimeInterval(1.6))
    }

    func testPowerCategoryReplacesAcrossKinds() {
        var e = IslandEngine()
        let a = e.post(.charging(level: 0.3, isCharging: true, pluggedIn: true), now: t0)
        let b = e.post(.lowBattery(level: 0.1), now: t0.addingTimeInterval(1))
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(e.activities.count, 1)
        XCTAssertEqual(e.activities[0].kind, .lowBattery(level: 0.1))
    }

    func testPostAfterExpiryCreatesNewId() {
        var e = IslandEngine()
        let a = e.post(.hud(.volume, level: 0.2, muted: false), now: t0)
        let b = e.post(.hud(.volume, level: 0.3, muted: false), now: t0.addingTimeInterval(5))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(e.activities.count, 1)
    }

    func testDifferentCategoriesCoexist() {
        var e = IslandEngine()
        e.post(.calendar(title: "a", minutesUntil: 3), now: t0)
        e.post(.focus(name: "Work", symbol: "s", enabled: true), now: t0)
        XCTAssertEqual(e.activities.count, 2)
    }

    func testPriorityOrdering() {
        var e = IslandEngine()
        e.post(.calendar(title: "a", minutesUntil: 3), now: t0)
        let hud = e.post(.hud(.volume, level: 0.5, muted: false), now: t0)
        e.post(.bluetooth(name: "AirPods", device: .airpods, battery: 50, connected: true), now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(e.currentActivity(now: t0.addingTimeInterval(0.2))?.id, hud.id)
    }

    func testNewerLowerPriorityDoesNotWin() {
        // Priorities are unique per category and categories replace, so ties cannot arise via the public API.
        var e = IslandEngine()
        let focus = e.post(.focus(name: "a", symbol: "s", enabled: true), now: t0, duration: 100)
        let cal = e.post(.calendar(title: "c", minutesUntil: 2), now: t0.addingTimeInterval(1), duration: 100)
        XCTAssertEqual(e.currentActivity(now: t0.addingTimeInterval(2))?.id, focus.id)
        XCTAssertNotEqual(focus.id, cal.id)
    }

    func testCurrentActivityIgnoresExpiredUnpruned() {
        var e = IslandEngine()
        e.post(.hud(.volume, level: 0.5, muted: false), now: t0)
        let cal = e.post(.calendar(title: "a", minutesUntil: 3), now: t0)
        let later = t0.addingTimeInterval(2)
        XCTAssertEqual(e.activities.count, 2)
        XCTAssertEqual(e.currentActivity(now: later)?.id, cal.id)
        XCTAssertNil(e.currentActivity(now: t0.addingTimeInterval(7)))
    }

    func testPrune() {
        var e = IslandEngine()
        e.post(.hud(.volume, level: 0.5, muted: false), now: t0)
        e.post(.calendar(title: "a", minutesUntil: 3), now: t0)
        e.startPeek(now: t0, duration: 1)
        e.prune(now: t0.addingTimeInterval(2))
        XCTAssertEqual(e.activities.count, 1)
        XCTAssertNil(e.peekUntil)
        e.prune(now: t0.addingTimeInterval(6))
        XCTAssertTrue(e.activities.isEmpty)
    }

    func testPruneKeepsActivePeek() {
        var e = IslandEngine()
        e.startPeek(now: t0, duration: 3)
        e.prune(now: t0.addingTimeInterval(1))
        XCTAssertEqual(e.peekUntil, t0.addingTimeInterval(3))
    }

    func testDismissCurrent() {
        var e = IslandEngine()
        let cal = e.post(.calendar(title: "a", minutesUntil: 3), now: t0)
        e.post(.hud(.volume, level: 0.5, muted: false), now: t0)
        e.dismissCurrent(now: t0)
        XCTAssertEqual(e.activities.map(\.id), [cal.id])
        e.dismissCurrent(now: t0)
        XCTAssertTrue(e.activities.isEmpty)
        e.dismissCurrent(now: t0) // no-op
        XCTAssertTrue(e.activities.isEmpty)
    }

    func testDismissAll() {
        var e = IslandEngine()
        e.post(.calendar(title: "a", minutesUntil: 3), now: t0)
        e.post(.hud(.volume, level: 0.5, muted: false), now: t0)
        e.dismissAll()
        XCTAssertTrue(e.activities.isEmpty)
    }

    func testPeekLifecycle() {
        var e = IslandEngine()
        e.isNowPlayingActive = true
        e.startPeek(now: t0, duration: 2.8)
        XCTAssertEqual(e.peekUntil, t0.addingTimeInterval(2.8))
        XCTAssertEqual(e.presentation(now: t0.addingTimeInterval(1), showNowPlayingCompact: true), .peek)
        XCTAssertEqual(e.presentation(now: t0.addingTimeInterval(3), showNowPlayingCompact: true), .nowPlaying)
        e.cancelPeek()
        XCTAssertNil(e.peekUntil)
        XCTAssertEqual(e.presentation(now: t0.addingTimeInterval(1), showNowPlayingCompact: true), .nowPlaying)
    }

    func testPeekRequiresNowPlaying() {
        var e = IslandEngine()
        e.startPeek(now: t0, duration: 2.8)
        XCTAssertEqual(e.presentation(now: t0.addingTimeInterval(1), showNowPlayingCompact: true), .idle)
    }

    func testPeekShowsEvenWhenCompactNowPlayingDisabled() {
        var e = IslandEngine()
        e.isNowPlayingActive = true
        e.startPeek(now: t0, duration: 2)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: false), .peek)
        XCTAssertEqual(e.presentation(now: t0.addingTimeInterval(3), showNowPlayingCompact: false), .idle)
    }

    func testExpandedWinsOverEverything() {
        var e = IslandEngine()
        e.isNowPlayingActive = true
        e.isSuppressed = true
        e.post(.hud(.volume, level: 0.5, muted: false), now: t0)
        e.isExpanded = true
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .expanded)
    }

    func testActivityShowsWhenSuppressed() {
        var e = IslandEngine()
        e.isSuppressed = true
        let a = e.post(.hud(.volume, level: 0.5, muted: false), now: t0)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .activity(a))
        XCTAssertEqual(e.presentation(now: t0.addingTimeInterval(2), showNowPlayingCompact: true), .hidden)
    }

    func testSuppressionHidesPeekAndNowPlaying() {
        var e = IslandEngine()
        e.isNowPlayingActive = true
        e.startPeek(now: t0, duration: 2)
        e.isSuppressed = true
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .hidden)
    }

    func testActivityBeatsPeek() {
        var e = IslandEngine()
        e.isNowPlayingActive = true
        e.startPeek(now: t0, duration: 2)
        let a = e.post(.focus(name: "f", symbol: "s", enabled: false), now: t0)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .activity(a))
    }

    func testNowPlayingCompactToggle() {
        var e = IslandEngine()
        e.isNowPlayingActive = true
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: true), .nowPlaying)
        XCTAssertEqual(e.presentation(now: t0, showNowPlayingCompact: false), .idle)
    }

    func testNextDeadline() {
        var e = IslandEngine()
        e.post(.calendar(title: "a", minutesUntil: 3), now: t0)        // +6
        e.post(.hud(.volume, level: 0.5, muted: false), now: t0)       // +1.6
        e.startPeek(now: t0, duration: 2.8)                            // +2.8
        XCTAssertEqual(e.nextDeadline(now: t0), t0.addingTimeInterval(1.6))
        XCTAssertEqual(e.nextDeadline(now: t0.addingTimeInterval(2)), t0.addingTimeInterval(2.8))
        XCTAssertEqual(e.nextDeadline(now: t0.addingTimeInterval(3)), t0.addingTimeInterval(6))
        XCTAssertNil(e.nextDeadline(now: t0.addingTimeInterval(7)))
    }

    func testNextDeadlinePeekOnly() {
        var e = IslandEngine()
        e.startPeek(now: t0, duration: 1)
        XCTAssertEqual(e.nextDeadline(now: t0), t0.addingTimeInterval(1))
        XCTAssertNil(e.nextDeadline(now: t0.addingTimeInterval(1)))
    }

    func testEngineEquatable() {
        var a = IslandEngine()
        let b = IslandEngine()
        XCTAssertEqual(a, b)
        a.isExpanded = true
        XCTAssertNotEqual(a, b)
    }
}
