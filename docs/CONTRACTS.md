# DynaNotch — contracts (binding)

> Moved out of CLAUDE.md on 2026-10-26 (verbatim). CLAUDE.md links here; update this file when the facts change.

Public APIs other code builds against. To change one, change it here first, in the same commit.

## 6. Contracts (binding)

### 6.1 DynaNotchCore (module `DynaNotchCore`, everything `public`, Foundation only)

```swift
// Geometry.swift
public struct NotchMetrics: Equatable {
    public var width: CGFloat; public var height: CGFloat; public var hasPhysicalNotch: Bool
    public init(width: CGFloat, height: CGFloat, hasPhysicalNotch: Bool)
    public static let fallback: NotchMetrics            // 185 × 32, no physical notch
    /// physical notch if safeAreaTop > 0: height = safeAreaTop, width = screenWidth - leftAux - rightAux
    /// (when both aux widths given and result in 80...400) else 185.
    /// No notch: width 185, height = max(24, menuBarHeight).
    public static func compute(screenWidth: CGFloat, safeAreaTop: CGFloat, leftAuxWidth: CGFloat?,
                               rightAuxWidth: CGFloat?, menuBarHeight: CGFloat) -> NotchMetrics
}

// Activities.swift
public enum HUDKind: String, Equatable, Hashable, CaseIterable { case volume, brightness }
public enum BluetoothDeviceKind: String, Equatable, Hashable, CaseIterable {
    case airpods, airpodsPro, airpodsMax, headphones, speaker, keyboard, mouse, trackpad, gamepad, generic
    public var symbolName: String          // SF Symbols: "airpods", "airpodspro", "airpodsmax", "headphones", "hifispeaker.fill", "keyboard", "computermouse", "rectangle.and.hand.point.up.left", "gamecontroller.fill", "dot.radiowaves.left.and.right"
    public static func classify(name: String, majorClass: UInt32, minorClass: UInt32) -> BluetoothDeviceKind
}
public enum ActivityCategory: String, Equatable, Hashable { case hud, power, bluetooth, focus, calendar }
public enum ActivityKind: Equatable {
    case hud(HUDKind, level: Double, muted: Bool)
    case charging(level: Double, isCharging: Bool, pluggedIn: Bool)
    case lowBattery(level: Double)
    case bluetooth(name: String, device: BluetoothDeviceKind, battery: Int?, connected: Bool)
    case focus(name: String, symbol: String, enabled: Bool)
    case calendar(title: String, minutesUntil: Int)
    public var category: ActivityCategory   // charging & lowBattery → .power
    public var defaultDuration: TimeInterval // hud 1.6, charging 3.0, lowBattery 4.0, bluetooth 3.5, focus 2.5, calendar 6.0
    public var priority: Int                 // hud 100, lowBattery 90, charging 80, bluetooth 70, focus 60, calendar 50
}
public struct LiveActivity: Equatable, Identifiable {
    public let id: UUID; public var kind: ActivityKind; public var postedAt: Date; public var expiresAt: Date
    public init(id: UUID = UUID(), kind: ActivityKind, postedAt: Date, expiresAt: Date)
}

// IslandEngine.swift
public enum IslandPresentation: Equatable { case hidden, idle, nowPlaying, peek, activity(LiveActivity), expanded
    public var isCompactLike: Bool  // nowPlaying, peek, activity
}
public enum SwipeDirection: String, Equatable { case left, right, up, down }
public struct IslandEngine: Equatable {
    public init()
    public private(set) var activities: [LiveActivity]
    public var isExpanded: Bool                 // default false
    public var isNowPlayingActive: Bool         // default false
    public var isSuppressed: Bool               // full-screen hide, default false
    public private(set) var peekUntil: Date?
    /// Same category replaces the existing activity **keeping its id** (no re-transition for HUD updates).
    @discardableResult public mutating func post(_ kind: ActivityKind, now: Date, duration: TimeInterval? = nil) -> LiveActivity
    public mutating func dismissCurrent(now: Date)
    public mutating func dismissAll()
    public mutating func startPeek(now: Date, duration: TimeInterval)
    public mutating func cancelPeek()
    public mutating func prune(now: Date)       // drop expired activities and finished peek
    public func currentActivity(now: Date) -> LiveActivity?   // highest priority, ties → newest postedAt
    public func presentation(now: Date, showNowPlayingCompact: Bool) -> IslandPresentation
    public func nextDeadline(now: Date) -> Date?  // earliest future expiresAt / peekUntil
}

// IslandLayout.swift
public enum HUDStyle: String, Equatable, Hashable, CaseIterable { case compact, expanded }
public struct IslandRadii: Equatable { public var top: CGFloat; public var bottom: CGFloat; public init(top: CGFloat, bottom: CGFloat) }
public enum IslandLayout {
    public static let canvasSize: CGSize            // 720 × 320
    public static let expandedWidth: CGFloat        // 600
    public static let expandedContentHeight: CGFloat // 156 (added below notch height)
    public static func sideWidth(for p: IslandPresentation, hudStyle: HUDStyle) -> CGFloat
    public static func size(for p: IslandPresentation, notch: NotchMetrics, hudStyle: HUDStyle) -> CGSize
    public static func radii(for p: IslandPresentation, hudStyle: HUDStyle) -> IslandRadii
    /// Rect in canvas coordinates, origin top-left, island centred horizontally at y = 0.
    public static func canvasRect(for size: CGSize) -> CGRect
    /// AppKit screen coordinates (origin bottom-left): (midX - w/2, maxY - h, w, h).
    public static func screenRect(for size: CGSize, screenFrame: CGRect) -> CGRect
    /// Panel frame for the canvas pinned to top-centre of `screenFrame`.
    public static func panelFrame(screenFrame: CGRect) -> CGRect
}
```
Size rules (`top` = ear radius, included in width): `idle` = notch.w + 2·top × notch.h · `nowPlaying` side 44 · `peek` side 110, height notch.h + 36 · activity sides: hud compact 72, hud expanded-style: side 60 and height notch.h + 34 · charging/lowBattery 64 · bluetooth 84 · focus 72 · calendar 96 · compact height = notch.h · `expanded` = max(expandedWidth, notch.w + 2·top + 160) × (notch.h + expandedContentHeight) · `hidden` = .zero.
Compact width = notch.w + 2·top + 2·side. Radii: idle (6, 9), nowPlaying/activity compact (6, 11), peek & hud-expanded (8, 16), expanded (14, 28), hidden (6, 9).

```swift
// NowPlaying.swift
public struct NowPlayingSnapshot: Equatable {
    public var title: String; public var artist: String; public var album: String
    public var duration: Double; public var elapsed: Double; public var timestamp: Date
    public var playbackRate: Double; public var isPlaying: Bool
    public var bundleIdentifier: String?        // parentBundle if non-empty else bundle
    public var artworkIdentifier: String?; public var artworkData: Data?
    public init(title: String = "", artist: String = "", album: String = "", duration: Double = 0, elapsed: Double = 0,
                timestamp: Date = Date(), playbackRate: Double = 0, isPlaying: Bool = false,
                bundleIdentifier: String? = nil, artworkIdentifier: String? = nil, artworkData: Data? = nil)
    public static let empty: NowPlayingSnapshot
    public var isEmpty: Bool                    // title empty
    public var trackKey: String                 // title + "\u{1F}" + artist + "\u{1F}" + album
    public func elapsed(at now: Date) -> Double // playing: elapsed + Δt·(rate > 0 ? rate : 1), clamped to 0...duration (if duration > 0)
    public func progress(at now: Date) -> Double // 0...1, 0 if duration <= 0
}
public enum AdapterMessage: Equatable { case ready, nowPlaying(NowPlayingSnapshot), empty, error(String), unknown }
public enum AdapterParser {
    /// Parses one JSON line from the adapter. Keys: type ("ready"|"nowPlaying"|"error"), empty, title, artist, album,
    /// duration, elapsed, rate, timestamp (unix seconds), playing, bundle, parentBundle, artworkId, artwork (base64), message.
    /// Tolerates NSNull, numbers-as-strings, missing keys, garbage (→ .unknown).
    public static func parse(line: String) -> AdapterMessage
}

// Formatting.swift
public enum Format {
    public static func time(_ seconds: Double) -> String         // "0:00", "3:07", "1:02:03"; NaN/neg/inf → "0:00"
    public static func percent(_ level: Double) -> String        // clamps 0...1 → "0%"..."100%"
    public static func relativeMinutes(_ minutes: Int) -> String // <=0 "now", "in 5 min", "in 1 h", "in 1 h 20 min"
    public static func clockRange(start: Date, end: Date, calendar: Calendar = .current, locale: Locale = .current) -> String
}

// MediaKeys.swift
public enum MediaKey: Int, Equatable { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7,
    play = 16, next = 17, previous = 18, fast = 19, rewind = 20, illuminationUp = 21, illuminationDown = 22 }
public struct MediaKeyEvent: Equatable {
    public let rawKeyCode: Int; public let key: MediaKey?; public let isDown: Bool; public let isRepeat: Bool
    /// NSEvent.data1 of a systemDefined (subtype 8) event: code = (d >> 16) & 0xFFFF, flags = d & 0xFFFF,
    /// down = ((flags & 0xFF00) >> 8) == 0x0A, repeat = flags & 0x1 == 1
    public init(data1: Int)
}
public enum LevelStepper {
    public static let step: Double = 1.0 / 16.0; public static let fineStep: Double = 1.0 / 64.0
    /// moves to the next multiple of the step in the given direction, clamped 0...1
    public static func step(_ level: Double, up: Bool, fine: Bool) -> Double
}
public struct LevelReading: Equatable { public var level: Double; public var muted: Bool; public init(level: Double, muted: Bool) }

// Power.swift
public struct BatteryInfo: Equatable {
    public var level: Double; public var isCharging: Bool; public var isPluggedIn: Bool
    public var minutesToEmpty: Int?; public var minutesToFull: Int?
    public init(level: Double, isCharging: Bool, isPluggedIn: Bool, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil)
}
public enum PowerEvent: Equatable { case pluggedIn(BatteryInfo), unplugged(BatteryInfo), lowBattery(BatteryInfo, threshold: Int) }
public struct PowerEventDetector {
    public init(thresholds: [Int] = [20, 10])
    /// First call only records state (no events). Plug state change → plugged/unplugged.
    /// Crossing a threshold downward while not plugged in → lowBattery once; re-armed when plugged in or level > threshold + 5.
    public mutating func update(_ info: BatteryInfo) -> [PowerEvent]
}

// Bluetooth.swift
public struct BluetoothEvent: Equatable {
    public var address: String; public var name: String; public var kind: BluetoothDeviceKind
    public var battery: Int?; public var connected: Bool
    public init(address: String, name: String, kind: BluetoothDeviceKind, battery: Int?, connected: Bool)
}

// Focus.swift
public struct FocusState: Equatable { public var modeIdentifier: String?; public var name: String; public var symbol: String
    public var isActive: Bool { modeIdentifier != nil }
    public init(modeIdentifier: String?, name: String, symbol: String)
    public static let inactive: FocusState }
public enum FocusParser {
    /// Assertions.json → data[0].storeAssertionRecords[0].assertionDetails.assertionDetailsModeIdentifier (nil when no records)
    public static func activeModeIdentifier(assertionsJSON: Data) -> String?
    /// ModeConfigurations.json → data[0].modeConfigurations[id].mode.{name,symbolImageName}; falls back to known ids
    /// (default→"Do Not Disturb"/"moon.fill", sleep→"Sleep"/"bed.double.fill", driving→"Driving"/"car.fill",
    /// work→"Work"/"briefcase.fill", personal→"Personal"/"person.fill", reading→"Reading"/"book.fill",
    /// fitness→"Fitness"/"figure.run", gaming→"Gaming"/"gamecontroller.fill", mindfulness→"Mindfulness"/"brain.head.profile",
    /// otherwise "Focus"/"moon.fill") matched by substring of the lowercased identifier.
    public static func state(assertionsJSON: Data, configurationsJSON: Data?) -> FocusState
}

// Calendar.swift
public struct CalendarItem: Equatable, Identifiable {
    public var id: String; public var title: String; public var start: Date; public var end: Date
    public var isAllDay: Bool; public var location: String?; public var colorHex: String?
    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil, colorHex: String? = nil)
}
public struct CalendarAlertTracker {
    public init()
    /// Timed (non all-day) events with now < start <= now + lead·60 that were not returned before.
    public mutating func due(events: [CalendarItem], now: Date, leadMinutes: Int) -> [CalendarItem]
}
public enum CalendarFilter {
    /// Not ended, sorted by start (all-day first for today), max `limit`.
    public static func upcoming(_ items: [CalendarItem], now: Date, limit: Int) -> [CalendarItem]
}

// ColorMath.swift
public struct RGB: Equatable { public var r: Double; public var g: Double; public var b: Double; public init(r: Double, g: Double, b: Double) }
public enum ColorMath {
    /// Saturation-weighted average, then brightness lifted to >= 0.55 (HSB) so it reads on black. Empty → white.
    public static func accent(fromPixels pixels: [RGB]) -> RGB
    public static func hsb(_ c: RGB) -> (h: Double, s: Double, b: Double)
    public static func rgb(h: Double, s: Double, b: Double) -> RGB
}

// Settings.swift
public enum DisplayMode: String, Equatable, Hashable, CaseIterable { case notchOrMain, main, followMouse
    public var title: String }  // "Built-in (notch) display", "Main display", "Follow mouse"
public enum ArtworkStyle: String, Equatable, Hashable, CaseIterable { case rounded, circle; public var title: String }
public enum VisualizerStyle: String, Equatable, Hashable, CaseIterable { case bars, none; public var title: String }
public enum SettingsKey { public static let … }   // one String constant per AppSettings property, same name
```

### 6.2 App (module `DynaNotch`) — classes, singletons and published API

**Concurrency rule (critical, we cannot compile on the owner's Mac before shipping):** no `async`/`await`, no `Task {}`, no `actor`, no explicit `@MainActor`/`@Sendable`/`nonisolated` in our code. Use GCD (`DispatchQueue.main.async`) and Combine (`Timer.publish`, `sink`). UI state is only mutated on the main thread. Prefer completion-handler APIs (e.g. `requestFullAccessToEvents(completion:)`).

```swift
// Model/AppSettings.swift — UserDefaults-backed, every property `@Published var x: T { didSet { persist } }`
final class AppSettings: ObservableObject { static let shared: AppSettings
  // General
  showMenuBarIcon: Bool = true; displayMode: DisplayMode = .notchOrMain; hideInFullscreen: Bool = true
  showOnNonNotchDisplays: Bool = true; hapticFeedback: Bool = true; hasCompletedOnboarding: Bool = false
  // Island
  expandOnHover: Bool = true; hoverDelay: Double = 0.15; collapseDelay: Double = 0.35; clickToExpand: Bool = true
  gesturesEnabled: Bool = true; expandedShowsCalendar: Bool = true; expandedShowsBattery: Bool = true
  // Now Playing
  nowPlayingEnabled: Bool = true; showCompactNowPlaying: Bool = true; showTrackPeek: Bool = true
  artworkStyle: ArtworkStyle = .rounded; visualizerStyle: VisualizerStyle = .bars; artworkGlow: Bool = true
  pausedLingerSeconds: Double = 15
  // HUD
  hudEnabled: Bool = true; replaceSystemHUD: Bool = true; hudStyle: HUDStyle = .compact
  volumeHUD: Bool = true; brightnessHUD: Bool = true
  // Live activities
  chargingActivity: Bool = true; lowBatteryActivity: Bool = true; bluetoothActivity: Bool = true
  focusActivity: Bool = true; calendarActivity: Bool = true; calendarLeadMinutes: Int = 5
  calendarEnabled: Bool = true
  func resetToDefaults()
}

// Model/IslandViewModel.swift
final class IslandViewModel: ObservableObject {
  init(settings: AppSettings = .shared)
  @Published private(set) var presentation: IslandPresentation   // .idle initially
  @Published private(set) var notch: NotchMetrics                // .fallback initially
  @Published private(set) var isHovering: Bool
  var islandSize: CGSize { get }      // IslandLayout.size(for: presentation, notch:, hudStyle: settings.hudStyle)
  var radii: IslandRadii { get }
  func start()                        // wires services, starts them
  func setNotch(_ metrics: NotchMetrics)
  func setHovering(_ hovering: Bool)  // hover → expand after hoverDelay (if expandOnHover); leave → collapse after collapseDelay
  func tap()                          // clickToExpand: toggles expanded
  func expand(); func collapse()
  func swipe(_ direction: SwipeDirection)  // left = next track, right = previous, up = collapse / dismiss activity
  func setSuppressed(_ suppressed: Bool)
  func post(_ kind: ActivityKind)     // respects settings toggles
  func openSettings()                 // NotificationCenter.default.post(name: .dynaNotchOpenSettings, object: nil)
  func simulate(_ demo: DemoActivity) // debug menu: volume, brightness, charging, lowBattery, airpods, focus, calendar, peek
}
enum DemoActivity: String, CaseIterable { case volume, brightness, charging, lowBattery, airpods, focus, calendar, peek }
extension Notification.Name { static let dynaNotchOpenSettings = Notification.Name("DynaNotch.openSettings") }

// Services — all `final class`, `static let shared`, idempotent `start()`; callbacks on main queue
NowPlayingService: ObservableObject
  @Published private(set) var snapshot: NowPlayingSnapshot   // .empty
  @Published private(set) var artwork: NSImage?
  @Published private(set) var accentColor: NSColor            // .white
  @Published private(set) var appIcon: NSImage?
  @Published private(set) var appName: String
  @Published private(set) var source: NowPlayingSource        // enum NowPlayingSource: String { case none, mediaRemote, appleScript }
  let trackChanged: PassthroughSubject<NowPlayingSnapshot, Never>   // new non-empty trackKey
  func start(); func stop()
  func togglePlayPause(); func next(); func previous(); func seek(to seconds: Double)
VolumeService      let changes: PassthroughSubject<LevelReading, Never>; func start(); func read() -> LevelReading?
                   @discardableResult func setLevel(_ v: Double) -> Bool; @discardableResult func setMuted(_ m: Bool) -> Bool
BrightnessService  let changes: PassthroughSubject<Double, Never>; var isAvailable: Bool; func start()
                   func read() -> Double?; @discardableResult func setLevel(_ v: Double) -> Bool
MediaKeyTap        var handler: ((MediaKeyEvent, NSEvent.ModifierFlags) -> Bool)?  // return true = consume
                   @Published private(set) var isActive: Bool (ObservableObject); func start(); func stop()
BatteryService: ObservableObject   @Published private(set) var info: BatteryInfo?; let events: PassthroughSubject<PowerEvent, Never>; func start()
BluetoothService   let events: PassthroughSubject<BluetoothEvent, Never>; func start()
FocusService: ObservableObject     @Published private(set) var state: FocusState; @Published private(set) var isReadable: Bool
                   let changes: PassthroughSubject<FocusState, Never>; func start()
CalendarService: ObservableObject  @Published private(set) var upcoming: [CalendarItem]; @Published private(set) var access: CalendarAccess
                   enum CalendarAccess { case notDetermined, denied, granted }
                   let dueSoon: PassthroughSubject<CalendarItem, Never>; func start(); func requestAccess()
                   func colorFor(_ item: CalendarItem) -> Color  (SwiftUI)  // from colorHex, default .blue
FullscreenDetector: ObservableObject  @Published private(set) var isFullscreen: Bool; func start(screenProvider: @escaping () -> NSScreen?)
ArtworkLookup      func lookup(title: String, artist: String, completion: @escaping (NSImage?) -> Void)  // iTunes Search API, cached
Permissions (enum) static var accessibilityGranted: Bool; static func requestAccessibility(); static func openAccessibilitySettings()
                   static func openFullDiskAccessSettings(); static func openCalendarSettings(); static func openBluetoothSettings()
LaunchAtLogin (enum) static var isEnabled: Bool; @discardableResult static func setEnabled(_ on: Bool) -> Bool
NSImage extension  func dominantAccentColor() -> NSColor   // samples 12×12 bitmap → ColorMath.accent
```

### 6.3 Window & Views
- `NotchPanel: NSPanel` (see §5). `NotchHostingView<Content: View>: NSHostingView<Content>` (`acceptsFirstMouse` true).
- `IslandWindowController` (plain `NSObject` subclass, not `NSWindowController`): `init(viewModel:)`, `show()`, owns panel, monitors, screen selection (`ScreenLocator.targetScreen(mode:)`), calls `vm.setNotch` on screen change, `vm.setHovering`, `vm.swipe`, `vm.collapse`, `vm.setSuppressed(FullscreenDetector)`.
- `IslandRootView`: `@EnvironmentObject` `IslandViewModel`, `AppSettings`, `NowPlayingService`, `BatteryService`, `CalendarService`, `FocusService`. Fills canvas, island at top-centre, `NotchShape(topRadius:bottomRadius:)` (Animatable), spring `.spring(response: 0.42, dampingFraction: 0.82)` keyed on presentation & size.
- Compact layout: `HStack(spacing: 0) { leading.frame(width: side); Spacer(minLength: notch.width); trailing.frame(width: side) }` inside the ears (`.padding(.horizontal, radii.top)`), height `notch.height`.
- Settings window: own `NSWindow` + `NSHostingController(SettingsRootView)` (not the SwiftUI `Settings` scene), 720×520, sidebar tabs: General, Island, Now Playing, HUD, Live Activities, Calendar, About.

### 6.4 v3 additions (Notchy parity) — supersede §6.1–6.3 where they overlap

#### Core changes to existing types
```swift
// Activities.swift — new cases (existing ones unchanged)
public enum ActivityCategory { …, timer, notification, download, privacy, toggle }
public enum SensorKind: String, Equatable, Hashable, CaseIterable { case camera, microphone
    public var symbolName: String }           // "video.fill", "mic.fill"
case timerFinished(label: String)                                  // .timer         dur 6.0  prio 95
case notification(title: String, body: String, symbol: String)    // .notification  dur 4.5  prio 85
case download(name: String, finished: Bool)                        // .download      dur 3.5  prio 65
case sensor(SensorKind, active: Bool)                              // .privacy       dur 3.0  prio 88
case toggle(symbol: String, label: String, on: Bool)               // .toggle        dur 1.5  prio 98 (caps lock, mic mute, keep awake)

// IslandEngine.swift
public enum IslandPresentation { …, timer, lyrics }   // isCompactLike also true for timer, lyrics
public var isTimerActive: Bool = false
public var hasLyricLine: Bool = false                  // only honoured while isNowPlayingActive && showNowPlayingCompact
public var prefersTimerOverMusic: Bool = true
// priority: expanded > activity > hidden > peek > timer(if prefers) > lyrics > nowPlaying > timer > idle

// IslandLayout.swift
expandedWidth = 640, expandedContentHeight = 190
sides: timer 64 · lyrics 44 · timerFinished 96 · notification 110 · download 84 · sensor 72 · toggle 64
heights: lyrics = notch.h + 26 · notification = notch.h + 40 (peek-like) · others compact = notch.h
radii: lyrics & notification (8, 16), timer / other new activities (6, 11)
public enum NonNotchStyle: String, CaseIterable { case notch, pill; var title }   // in Settings.swift
public static let pillTopInset: CGFloat = 6         // pill floats this far below the screen top
/// `screenRect(for:screenFrame:topInset:)` — same as screenRect, shifted down by topInset (default 0).
```

#### New Core files
```swift
// Panel.swift
public enum PanelTab: String, Equatable, Hashable, CaseIterable, Codable {
    case home, nowPlaying, timer, clipboard, shelf, notes, system, aiUsage
    public var title: String     // "Home","Now Playing","Timer","Clipboard","Shelf","Notes","System","AI Usage"
    public var symbolName: String // "house.fill","music.note","timer","doc.on.clipboard","tray.full.fill","note.text","cpu","sparkles"
    /// Parses "home,timer" (unknown ids dropped, duplicates removed, order kept); empty → allCases.
    public static func parseList(_ s: String) -> [PanelTab]
    public static func serialize(_ tabs: [PanelTab]) -> String
}

// Timer.swift
public enum TimerMode: String, Equatable, Codable { case countdown, pomodoro, stopwatch }
public enum PomodoroPhase: String, Equatable, Codable { case work, shortBreak, longBreak; public var title: String } // "Focus","Short Break","Long Break"
public struct PomodoroConfig: Equatable { public var work, shortBreak, longBreak: TimeInterval; public var cyclesBeforeLongBreak: Int
    public init(work: TimeInterval = 1500, shortBreak: TimeInterval = 300, longBreak: TimeInterval = 900, cyclesBeforeLongBreak: Int = 4) }
public struct TimerState: Equatable {
    public var mode: TimerMode; public var phase: PomodoroPhase?; public var label: String
    public var duration: TimeInterval          // target; 0 for stopwatch
    public var startedAt: Date?                // nil = paused
    public var accumulated: TimeInterval       // elapsed before the current run
    public var completedWorkSessions: Int
    public var isRunning: Bool
    public func elapsed(at: Date) -> TimeInterval
    public func remaining(at: Date) -> TimeInterval   // max(0, duration - elapsed); stopwatch → elapsed
    public func progress(at: Date) -> Double          // 0...1 (stopwatch → 0)
    public func displayTime(at: Date) -> String       // Format.time(remaining) ("0:00" floor; ceil seconds for countdowns)
}
public enum TimerEvent: Equatable { case countdownFinished(label: String); case phaseFinished(from: PomodoroPhase, to: PomodoroPhase) }
public struct TimerEngine: Equatable {
    public init(config: PomodoroConfig = PomodoroConfig())
    public var config: PomodoroConfig
    public private(set) var state: TimerState?          // nil = idle
    public var isActive: Bool                            // state != nil
    public mutating func startCountdown(seconds: TimeInterval, label: String, now: Date)
    public mutating func startPomodoro(now: Date)        // phase .work
    public mutating func startStopwatch(now: Date)
    public mutating func pause(now: Date); public mutating func resume(now: Date); public mutating func toggle(now: Date)
    public mutating func reset()
    public mutating func addTime(_ seconds: TimeInterval, now: Date)   // countdown/pomodoro only
    public mutating func skipPhase(now: Date) -> TimerEvent?           // pomodoro only, auto-starts next phase
    /// Countdown done → state nil + .countdownFinished. Pomodoro phase done → next phase starts at the finish time
    /// (work → short/long break by completedWorkSessions % cycles; break → work) + .phaseFinished. Else nil.
    public mutating func tick(now: Date) -> TimerEvent?
    public func nextDeadline(now: Date) -> Date?          // finish time of the running countdown/phase
}

// Clipboard.swift
public enum ClipKind: String, Equatable, Codable { case text, link, color, image, file }
public struct ClipItem: Equatable, Identifiable, Codable {
    public var id: UUID; public var kind: ClipKind; public var text: String; public var date: Date
    public var pinned: Bool; public var sourceApp: String?; public var imageFile: String?   // file name in the app's clip image dir
    // .image items: `text` = content hash (dedupe key); .file items: `text` = paths joined by "\n"
    public init(id: UUID = UUID(), kind: ClipKind, text: String, date: Date, pinned: Bool = false, sourceApp: String? = nil, imageFile: String? = nil)
}
public enum ClipClassifier {
    public static func kind(for text: String) -> ClipKind   // http(s)/www URL (single token) → link, #RGB/#RRGGBB(AA) → color, else text
    public static func preview(_ text: String, max: Int = 200) -> String  // trims, collapses whitespace runs to one space
}
public enum LinkCleaner {
    /// Removes utm_*, fbclid, gclid, dclid, gbraid, wbraid, msclkid, mc_cid, mc_eid, igshid, igsh, yclid, _hsenc, _hsmi,
    /// mkt_tok, ref_src, ref_url, si (only on youtu.be / youtube.com / open.spotify.com); keeps order of the rest;
    /// drops a trailing "?" when nothing remains. Non-URLs returned unchanged.
    public static func clean(_ text: String) -> String
}
public struct ClipboardHistory: Equatable, Codable {
    public init(limit: Int = 50)
    public var limit: Int
    public private(set) var items: [ClipItem]          // newest first, pinned items first
    /// Same text (or same image file) already present → moved to top (keeps pin). Whitespace-only text ignored.
    /// Evicts oldest unpinned beyond limit; returns evicted items (so the app can delete image files).
    @discardableResult public mutating func add(_ item: ClipItem) -> [ClipItem]
    public mutating func remove(id: UUID) -> ClipItem?
    public mutating func togglePin(id: UUID)
    @discardableResult public mutating func clear(keepPinned: Bool = true) -> [ClipItem]
    public func search(_ query: String) -> [ClipItem]  // case/diacritic-insensitive substring; empty → items
}

// Lyrics.swift
public struct LyricLine: Equatable { public var time: TimeInterval; public var text: String; public init(time:text:) }
public enum LRCParser {
    /// "[mm:ss.xx]text", several tags per line, [offset:+/-ms] honoured, metadata tags skipped, sorted by time.
    public static func parse(_ lrc: String) -> [LyricLine]
    public static func currentIndex(at time: TimeInterval, in lines: [LyricLine]) -> Int?   // last line with time <= t
}
public enum LRCLibParser {   // https://lrclib.net/api/get?track_name=&artist_name=&album_name=&duration=
    /// → (synced lines, plain text). nil on garbage. instrumental → ([], "")
    public static func parse(_ data: Data) -> (synced: [LyricLine], plain: String)?
}

// AIUsage.swift
public struct TokenUsage: Equatable { public var input, output, cacheCreation, cacheRead: Int
    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0)
    public var total: Int; public static func + (l, r) -> TokenUsage; public static let zero }
public struct UsageEntry: Equatable { public var timestamp: Date; public var model: String; public var usage: TokenUsage
    public var dedupeKey: String?   // message.id + ":" + requestId
    public init(timestamp:model:usage:dedupeKey:) }
public enum ClaudeUsageParser { public static func parse(line: String) -> UsageEntry? }  // type=="assistant" lines with message.usage
public enum ModelPricing {   // USD per million tokens (input, output, cache write, cache read)
    /// family by substring: "opus" 15/75/18.75/1.5, "sonnet" 3/15/3.75/0.3, "haiku" 1/5/1.25/0.1, "fable" 15/75/18.75/1.5, else sonnet
    public static func cost(model: String, usage: TokenUsage) -> Double
}
public struct UsageBlock: Equatable { public var start: Date; public var end: Date; public var lastActivity: Date
    public var usage: TokenUsage; public var cost: Double; public var entryCount: Int
    public func isActive(now: Date) -> Bool }      // now < end && now - lastActivity < 5h
public enum UsageAggregator {
    /// ccusage-style: dedupe by key, sort, block starts at the UTC hour floor of its first entry, lasts `duration`;
    /// a new block starts when an entry is >= end or > duration after the previous entry.
    public static func blocks(_ entries: [UsageEntry], duration: TimeInterval = 18000) -> [UsageBlock]
    public static func activeBlock(_ entries: [UsageEntry], now: Date) -> UsageBlock?
    public static func summary(_ entries: [UsageEntry], from: Date, to: Date) -> (usage: TokenUsage, cost: Double, count: Int)
}
public struct RateWindow: Equatable { public var usedPercent: Double; public var windowMinutes: Int?; public var resetsAt: Date?
    public init(usedPercent:windowMinutes:resetsAt:) }
public struct CodexRateLimits: Equatable { public var primary: RateWindow?; public var secondary: RateWindow?; public var observedAt: Date }
public enum CodexUsageParser {
    /// event_msg / token_count lines with payload.rate_limits.{primary,secondary}.{used_percent, window_minutes,
    /// resets_at (unix s) | resets_in_seconds (relative to the line's timestamp)}.
    public static func parse(line: String) -> CodexRateLimits?
}

// Weather.swift
public enum TemperatureUnit: String, Equatable, Hashable, CaseIterable { case celsius, fahrenheit; public var title: String; public var symbol: String } // "°C","°F"
public struct WeatherSnapshot: Equatable { public var temperature: Double; public var high: Double; public var low: Double
    public var code: Int; public var isDay: Bool; public var locationName: String; public var fetchedAt: Date
    public var symbolName: String { WeatherCode.symbol(code:isDay:) }; public var summary: String { WeatherCode.summary(code:) } }
public enum WeatherCode { public static func symbol(code: Int, isDay: Bool) -> String; public static func summary(code: Int) -> String } // WMO codes
public enum OpenMeteoParser {
    /// forecast?current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto
    public static func parse(_ data: Data, locationName: String, now: Date) -> WeatherSnapshot?
    /// geocoding-api.open-meteo.com/v1/search?name=…&count=1 → (lat, lon, name)
    public static func parseGeocoding(_ data: Data) -> (latitude: Double, longitude: Double, name: String)?
}

// SystemStats.swift
public struct CPUTicks: Equatable { public var user, system, idle, nice: UInt64; public init(user:system:idle:nice:) }
public enum SystemMath {
    public static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double   // 0...1, 0 when no delta
    public static func rate(previous: UInt64, current: UInt64, interval: TimeInterval) -> Double  // bytes/s, counter wrap → 0
}
extension Format {
    public static func bytes(_ count: Double) -> String       // "0 B","512 B","1.5 KB","12 MB","1.2 GB" (1000-based, 1 decimal < 10)
    public static func rate(_ bytesPerSecond: Double) -> String // bytes + "/s"
    public static func tokens(_ n: Int) -> String              // "950", "12.3K", "4.5M"
    public static func countdown(_ seconds: TimeInterval) -> String   // "2h 05m", "14m", "<1m"
    public static func currency(_ usd: Double) -> String       // "$0.00" two decimals
}

// Downloads.swift
public enum DownloadNames {
    public static func isPartial(_ name: String) -> Bool        // .download .crdownload .part .partial .opdownload
    public static func finalName(_ partial: String) -> String   // strips the partial extension (Safari "x.zip.download")
}
public struct DownloadTracker { public init()
    /// First call seeds only. Returns partial files that appeared and final names whose partial vanished while the final exists.
    public mutating func update(_ names: Set<String>) -> (started: [String], finished: [String]) }

// Notify.swift
public struct NotchNotification: Equatable { public var title: String; public var body: String; public var symbol: String; public var duration: TimeInterval?; public var openURL: URL? }
public enum NotifyURL {
    /// dynanotch://notify?title=&body=&symbol=&duration=&open= (title or body required; symbol default "bell.fill"; duration 1...30; open = http/https/file URL, §6.10a)
    public static func parse(_ url: URL) -> NotchNotification?
}

// Notes.swift
public struct TodoItem: Equatable, Identifiable, Codable { public var id: UUID; public var text: String; public var done: Bool; public var createdAt: Date
    public init(id: UUID = UUID(), text: String, done: Bool = false, createdAt: Date) }
public struct ShelfItem: Equatable, Identifiable, Codable { public var id: UUID; public var path: String; public var addedAt: Date
    public var name: String { (path as NSString).lastPathComponent }; public init(id: UUID = UUID(), path: String, addedAt: Date) }
public enum ShelfList { public static func adding(_ paths: [String], to items: [ShelfItem], now: Date) -> [ShelfItem] } // dedupe by path, new first
```

#### App additions (module `DynaNotch`)
```swift
// AppSettings — new @Published persisted properties (key "dn." + name, listed in SettingsKey.all)
nonNotchStyle: NonNotchStyle = .pill
panelTabs: String = "home,nowPlaying,timer,clipboard,shelf,notes,system,aiUsage"   // PanelTab.parseList
rememberLastTab: Bool = true; lastTab: String = "home"; hotkeysEnabled: Bool = true
lyricsEnabled: Bool = true; lyricsInCompact: Bool = true
pomodoroWorkMinutes: Int = 25; pomodoroShortBreakMinutes: Int = 5; pomodoroLongBreakMinutes: Int = 15; pomodoroCycles: Int = 4
timerSound: Bool = true; timerOverNowPlaying: Bool = true; showCompactTimer: Bool = true
clipboardEnabled: Bool = true; clipboardLimit: Int = 50; cleanLinks: Bool = true; pasteOnClick: Bool = true
shelfEnabled: Bool = true; shelfRemoveOnDragOut: Bool = false
weatherEnabled: Bool = true; weatherCity: String = ""; temperatureUnit: TemperatureUnit = .celsius
aiUsageEnabled: Bool = true
downloadActivity: Bool = true; privacyActivity: Bool = true; capsLockActivity: Bool = true; notifyActivity: Bool = true
var enabledTabs: [PanelTab]   // computed from panelTabs, filtered by the feature toggles (clipboard/shelf/aiUsage)

// IslandViewModel — additions
@Published var selectedTab: PanelTab                 // persisted to lastTab when rememberLastTab
@Published private(set) var isPinned: Bool           // pinned panel ignores mouse-leave collapse
func select(_ tab: PanelTab); func togglePin(); func open(tab: PanelTab)   // expand + select
func beginFileDrag()                                 // window controller: files dragged near the island → expand on Shelf
func notify(_ n: NotchNotification)
enum DemoActivity: …, timer, lyrics, notification, download, camera, capsLock

// New services — `final class`, `static let shared`, idempotent `start()`, main-queue publishing
TimerService: ObservableObject     @Published private(set) var engine: TimerEngine; var state: TimerState? { engine.state }
                                   let events: PassthroughSubject<TimerEvent, Never>; let tick: PassthroughSubject<Date, Never> (1 Hz while active)
                                   func startCountdown(minutes: Double, label: String); func startPomodoro(); func startStopwatch()
                                   func toggle(); func reset(); func addMinute(); func skipPhase(); func applyConfig(_ c: PomodoroConfig)
ClipboardService: ObservableObject @Published private(set) var history: ClipboardHistory; func start(); func stop()
                                   func copy(_ item: ClipItem); func paste(_ item: ClipItem, plainText: Bool)  // copy, then ⌘V if Accessibility
                                   func remove(_ item: ClipItem); func togglePin(_ item: ClipItem); func clear()
                                   func image(for item: ClipItem) -> NSImage?
ShelfService: ObservableObject     @Published private(set) var items: [ShelfItem]; func add(urls: [URL]); func remove(_ i: ShelfItem)
                                   func clear(); func url(for i: ShelfItem) -> URL; func airDrop(_ items: [ShelfItem]); func reveal(_ i: ShelfItem)
NotesService: ObservableObject     @Published var text: String (persisted, debounced); @Published private(set) var todos: [TodoItem]
                                   func addTodo(_ text: String); func toggle(_ t: TodoItem); func remove(_ t: TodoItem); func clearDone()
LyricsService: ObservableObject    @Published private(set) var lines: [LyricLine]; @Published private(set) var plain: String
                                   @Published private(set) var isLoading: Bool; func start()   // follows NowPlayingService.trackChanged, caches by trackKey
                                   func currentIndex(at elapsed: Double) -> Int?
WeatherService: ObservableObject   @Published private(set) var snapshot: WeatherSnapshot?; @Published private(set) var status: String
                                   func start(); func refresh()     // every 30 min; city → geocode, empty city → CoreLocation (one-shot)
SystemMonitorService: ObservableObject  @Published private(set) var cpu: Double; memoryUsed: UInt64; memoryTotal: UInt64
                                   netIn: Double; netOut: Double; diskFree: Int64; diskTotal: Int64; batteryCycles: Int?; batteryHealth: Double?
                                   func setActive(_ on: Bool)       // samples every 2 s only while the System/Home tab is visible
AIUsageService: ObservableObject   @Published private(set) var claudeBlock: UsageBlock?; claudeToday: (TokenUsage, Double)?
                                   claudeWeek: (usage: TokenUsage, cost: Double, count: Int)?; claudeMaxBlockTokens: Int; codex: CodexRateLimits?
                                   @Published private(set) var lastUpdated: Date?; func start(); func refresh()  // background queue, 60 s
AudioDeviceService: ObservableObject  struct AudioDevice: Identifiable, Equatable { id: UInt32; name: String; isOutput: Bool }
                                   @Published private(set) var outputs: [AudioDevice]; @Published private(set) var currentOutputID: UInt32?
                                   @Published private(set) var isMicMuted: Bool; func start(); func select(_ d: AudioDevice); func toggleMicMute()
KeepAwakeService: ObservableObject @Published private(set) var isOn: Bool; func toggle(); func set(_ on: Bool)
PrivacyMonitor                     let changes: PassthroughSubject<(SensorKind, Bool), Never>; func start()   // 1.5 s poll
CapsLockMonitor                    let changes: PassthroughSubject<Bool, Never>; func start()                // 0.25 s poll of NSEvent.modifierFlags
DownloadsMonitor                   let events: PassthroughSubject<(name: String, finished: Bool), Never>; func start()  // ~/Downloads, 1 s poll
HotKeyService                      func start(); var onTogglePanel: (() -> Void)?; var onClipboard: (() -> Void)?  // ⌃⌥N, ⌃⌥V
ScreenLock (enum)                  static func lock()
```

#### Views (v3)
- `ExpandedView` = `PanelHeader` (tab icons left of the notch gap, toggles right: Keep Awake `cup.and.saucer.fill`, mic, pin, lock, gear) + tab body.
  Notch gap only when `notch.hasPhysicalNotch`. Each tab view lives in `Views/Tabs/<Name>Tab.swift`: `HomeTab`, `NowPlayingTab`,
  `TimerTab`, `ClipboardTab`, `ShelfTab`, `NotesTab`, `SystemTab`, `AIUsageTab`.
- Compact views: `CompactTimerView` (ring + "12:34"), `LyricsCompactView` (artwork/visualiser row + current line, 12 pt, centred, 1 line),
  plus activity views for every new `ActivityKind` in `ActivityView`.
- The panel's text fields (clipboard search, notes, to-do) make the panel key on focus (`NSApp`-free: `panel.makeKey()` via
  `NotificationCenter` `.dynaNotchWantsKey`); Esc collapses.
- Settings panes added: **Panel** (tabs on/off & order, hotkeys, non-notch style), **Productivity** (timer, clipboard, shelf, notes),
  **Weather & AI** (city, unit, AI usage). Live Activities pane gains download / privacy / caps lock / notify toggles.

### 6.5 v3.1 additions (glass, header, device batteries, welcome)

```swift
// Core — DeviceBattery.swift
public enum DeviceKind: String, Equatable, Hashable, CaseIterable { case mac, mouse, keyboard, trackpad, headphones, airpods, gamepad, other
    public var symbolName: String }   // "laptopcomputer","computermouse.fill","keyboard.fill","rectangle.and.hand.point.up.left.fill",
                                      // "headphones","airpods.pro","gamecontroller.fill","dot.radiowaves.left.and.right"
public struct DeviceBattery: Equatable, Identifiable {
    public var id: String                 // bluetooth address, or "mac"
    public var name: String; public var kind: DeviceKind
    public var level: Int?                // 0...100 main/combined level
    public var left: Int?; public var right: Int?; public var caseLevel: Int?   // AirPods-style
    public var isCharging: Bool; public var detail: String?   // e.g. "Health 100% · 10 cycles · 34°C"
    public var displayLevel: Int?         // level ?? min(left, right) ?? caseLevel
}
public enum BluetoothProfilerParser {
    /// `system_profiler -json SPBluetoothDataType` → connected devices (device_connected), battery keys
    /// device_batteryLevelMain|Left|Right|Case ("86 %", NBSP tolerated), kind from device_minorType + name.
    public static func parse(_ data: Data) -> [DeviceBattery]
    public static func percent(_ s: String) -> Int?
}
public enum DeviceBatteryMerge {
    /// Merges sources by id (falls back to case-insensitive name); later sources fill nil levels only.
    public static func merge(_ sources: [[DeviceBattery]]) -> [DeviceBattery]   // sorted: mac first, then by name
}
public enum IslandMaterial: String, Equatable, Hashable, CaseIterable { case glass, black; public var title: String }

// App
DeviceBatteryService: ObservableObject  @Published private(set) var devices: [DeviceBattery]   // mac first
    func start(); func refresh()   // 60 s: system_profiler (background), Apple HID BatteryPercent (IOKit),
                                   // CoreBluetooth GATT 0x180F/0x2A19 for connected BLE peripherals; Mac from IOPS + AppleSmartBattery
QuickActions (enum)  static func captureScreenshot(); static func pickColor()   // colour hex → pasteboard
AppSettings: islandMaterial: IslandMaterial = .glass; hasSeenWelcome: Bool = false (key dn.hasSeenWelcome)
WelcomeController  show()   // borderless full-screen-ish window: animated handwritten "hello" → "Welcome to DynaNotch" → Get Started,
                            // then tip cards anchored under the notch. Menu "Show Welcome…", URL dynanotch://welcome.
Views: `HelloShape` (single-stroke cursive path, animated with .trim), `GlassBackground` (NSVisualEffectView .hudWindow,
behind-window, dark), `PanelHeader` = TabPill + TabMenu (⋯) | BatteryPill · timer · output · keep awake · ActionsMenu (⋯) · pin · lock.
```

### 6.6 v3.2 additions (Notchy settings audit, §2d)

```swift
// Core (all tested in V32Tests.swift)
Calculator.evaluate(_:) -> Double?; Calculator.format(_:) -> String          // safe recursive-descent parser
SearchEngine { id, name, shortcut, template("%@"), symbol; url(for:) }; QuickSearch.builtIn; QuickSearch.resolve(_:engines:defaultEngineID:)
EmojiEntry { character, name, group }; EmojiGroup (8); EmojiCatalog.all / search(_:)
BreakKind (lookAway, standUp, drinkWater); BreakScheduler.due(now:start:intervals:isQuiet:) / reset(now:)
PomodoroStats.recordSession(at:) / today(now:) / streak(now:) / total     (Codable)
BatterySample, BatteryHistory.append(_:) / samples(since:)                 (Codable, 5-min spacing, 30-day retention)
ScreenTimeLedger.record(app:name:from:to:) / top(on:limit:) / total(on:) / prune(keepDays:now:)   (Codable)
MeetingLink.detect(in: [String?]) -> URL?                                  // Zoom, Meet, Teams, Webex, Whereby, Slack, Discord
AccessoryAlert (.low / .full), AccessoryAlertDetector(lowThreshold:).update(_:)
MaterialPreset (graphite, onyx, carbon, frost, satin, mist, clear; tintWhite, tintOpacity, opacity(translucency:))
AnimationStyle (calm, snappy, bouncy; spring, response(speed:)); TimeFormat (system, h12, h24; template)
PanelTab += calculator, emoji, quickSearch, launcher, shortcuts, reminders, mirror

// AppSettings (+ SettingsKey "dn."+name)
materialPreset = .carbon; panelTranslucency = 1.0 (0…1); animationStyle = .calm; animationSpeed = 1.0 (0.5…2)
colorCodedLevels = false; closedPillClock = false; timeFormat = .system; helloIntro = false
defaultTab = "previous" ("previous" | PanelTab raw); openOnCurrentActivity = true; idleTimeout = 0 (s, 0 = never)
invisibleUntilHover = false; notificationDuration = 4.5 (1…15); lyricsOffset = 0 (s, −5…5)
pomodoroAutoContinue = true; breakLookAway = false; breakStandUp = false; standUpMinutes = 60; breakDrinkWater = false
drinkWaterMinutes = 45; lowBatteryThreshold = 20 (5…50); fullChargeActivity = false; accessoryAlerts = true
clipboardIgnoredApps = "<password-manager bundle ids>"; clipboardAutoClearMinutes = 0; pasteWithNumbers = true
meetingAlert = false; meetingAlertMinutes = 1; screenTimeEnabled = true; quickSearchEngine = "google"
launcherApps = "" (bundle ids, comma); colorFormat = "hex" (hex|rgb|hsl); driveActivity = true; screenshotToShelf = false
headerButtons = "battery,output,keepAwake,actions,pin,lock" (+ timer, screenshot, colorPicker, mic)
func restoreDefaults(_ keys: [String]); func exportJSON() -> Data; func importJSON(_ data: Data) -> Bool

// New services (skeleton → systems agent)
BreakReminderService.start(); PomodoroStatsService (@Published stats); BatteryHistoryService (@Published history)
ScreenTimeService (@Published ledger; func today(limit:) -> [(app, name, seconds)]); MeetingAlertController.start()
DriveMonitor.start(); ColorHistory (@Published colors: [String])
// New tab services (→ tabs agent)
LauncherService (pinned + running apps, search installed apps, launch); ShortcutsService (`shortcuts list|run`)
RemindersService (EventKit reminders: access, list, add, complete); CameraService (AVCaptureSession for Mirror)
```
v3.2 integration notes (2026-10-26):
- `HeaderButtonID` (Core, Panel.swift: battery, timer, output, keepAwake, mic, screenshot, colorPicker, actions, pin, lock;
  `parseList` / `serialize(Set)` in canonical order) drives `PanelHeader` from `settings.headerButtons`.
- `PanelTab.migrate(stored:known:)` + UserDefaults `dn.knownTabs` (not in `SettingsKey.all`): tabs added by an update are
  inserted once into an existing tab list (before System / AI Usage); tabs the user removed stay removed.
- Two-finger swipes act only on the compact island; while expanded, scrolling belongs to the tab lists.
- `CameraService.isOwnUse` suppresses the camera privacy activity while (and 4 s after) the Mirror tab uses the camera.
- `BatteryService.fullyCharged` → "Fully Charged" notification island (settings.fullChargeActivity).
- `notchDisplayStyle: NonNotchStyle = .notch` (key `dn.notchDisplayStyle`): `.pill` on a notch display makes the view model
  lay out with non-notch metrics (`notch` = effective, `screenNotch` = measured) and `topInset = notch height + pillTopInset`;
  `vm.isOnNotchDisplay` is the hardware fact. Settings → Appearance shows visual `ShapeChoiceRow` cards per display kind.
- v3.3 (P1 of §2e): settings `pillScale`, `pillHeightOffset`, `screenSharingPrivacy`, `hideWhileMirroring`, `fullscreenScope`
  (Core `FullscreenScope`), `autoCollapse`, `quietDuringFocus`, `peekOnHover`, `mediaKeysControlPlayer`,
  `preventMusicAutoLaunch`, `meetingOnlyWithLink`, `hiddenCalendars`, `calendarHotkeys`, `timerHoverControls`,
  `clipboardCaptureSound`, `shelfRetention` (Core `ShelfRetention`), `screenshotFolder`, `unplugActivity`, `fullChargeLevel`.
  Core `IslandLayout`: `timerControlsSize/Radii`, `unpluggedSide`, `pillScaleRange`, `scaled(_:by:)`;
  `ActivityKind.isQuietedDuringFocus`. App: `CalendarService.calendars` / `CalendarInfo` / `nextMeetingURL()`,
  `KeepAwakeService.keepAwake(for:)` + `until`, `ScreenRecorder`, `MusicLaunchGuard`, `PermissionDiagnostics`,
  `Permissions.screenRecordingGranted`, `.dynaNotchAppNotification` (services → island message, not gated by the notify
  toggle), `DemoActivity.unplug`. Test hooks: `dynanotch://ui/override?fullscreen=1&front=<bundle>&mirror=1&focus=1`,
  `dynanotch://ui/mediakey?code=16[&up=1]`. Never wait for builds with `pgrep -f "./build.sh"` inside a shell loop (it
  matches itself); use `pgrep -fl "^/bin/bash ./build.sh"`.
- Welcome (supersedes §6.5; owner request 2026-10-26: no buttons, slides, ends in the app):
  `WelcomeController.show(greetingOnly:)` opens one window pinned to the top centre (level `.mainMenu + 4`);
  `WelcomeView(notch:greetingOnly:handOffSize:closer:onHandOff:)` is a black island that springs out of the notch →
  hello draws (~3.3 s) → "Welcome to DynaNotch" (2.2 s, no button) → first launch only: `WelcomeSlidesView`, the tips as
  self-advancing slides (3.4 s each, push-from-right transition, Stories-style progress bar; click / → / space = next,
  ← = back, Skip) → **hand-off**: the island morphs to the real panel's size (`vm.expandedSize`), the controller opens
  the panel on Home underneath and fades the pop-up out; the panel collapses 3 s later unless hovered or pinned.
  Every ending (last slide, Skip, Esc) hands off. Test: `dynanotch://ui/click?window=welcome&id=welcome.slides|welcome.skip`.
- Shared helpers: `Services/WellbeingSupport.swift` (`AppDataStore` JSON in App Support / UserDefaults, `UserPresence`
  lock/sleep/idle), `Views/Tabs/QuickSearchTab.swift` (`PanelInputField`, `PanelPasteboard`, `CopiedBadge`),
  `Views/Alerts/MeetingAlertView.swift`. Settings window is 820×600 with grouped sidebar + search.

Ownership this round: tech lead = Core, Model, Window, App, PanelHeader/IslandRootView/ActivityView; **tabs agent** =
`Views/Tabs/{Calculator,Emoji,QuickSearch,Launcher,Shortcuts,Reminders,Mirror}Tab.swift`, SystemTab, and the four tab
services; **settings agent** = `Views/Settings/**`; **systems agent** = the remaining `Services/**` + `Views/Tabs/ClipboardTab.swift`
+ `Views/Alerts/**`.

### 6.7 v3.4 additions (§2e P2) — contract

Core `Workspace.swift` (tested in `V34Tests.swift`): `HotKeyAction` (togglePanel, clipboard, hide, commandPalette,
emergencyQuit, joinMeeting, openCalendar, pastePlainText, startPomodoro, toggleKeepAwake), `HotKeyBinding` (Carbon key code +
modifier mask, `display` "⌃⌥N"), `HotKeyMap` (settings string "action=code:mods;tab.timer=…", only diffs from `defaults`
stored, "key=" clears), `KnockKey`, `KnockAction` (+ "1=…,2=…" map), `KnockDetector` (press/release/interrupt/settle),
`HomeCard` (13 cards, `span`, `defaultList`, parse/serialize), `ClockContent`, `PanelSizing`, `TrackInfoMode`,
`AlertCategory` + `AlertSounds` ("timers=Glass,battery=None"), `SavedLink`, `JSONList`, `ListenEntry`/`ListeningHistory`,
`TrafficLedger`. `TimerEngine.repeatCountdown`. `WeatherSnapshot.sunrise/sunset`. `DisplayMode.external`.
`PanelTab` += `calendar`, `quickSettings`; `HeaderButtonID` += stopwatch, pomodoro, volume, scanQR, ports, systemStats.

Settings (AppSettings "MARK: v3.4"): clockContent, clockWithActivities, panelWidth (520–820), panelSizing, panelMaxHeight
(150–320), panelFillHex, pillMatchesPanel, trackInfoMode, desktopLyrics, edgeGlow, alertSounds, hotkeyBindings, knockEnabled,
knockKey, knockActions, copyTwiceToOpen, offerCleanCopy, customSearchEngines (JSON [SearchEngine]), homeCards, homeColumns
(2–4), worldClocks (TZ ids), savedLinks (JSON [SavedLink]), repeatTimer, repeatAlarm, pomodoroOnly, aiLimitWarnings,
aiLimitWarnPercent (50–95), aiMenuBarReadout, aiHidePersonalInfo, batteryInMenuBar, drainWarnings, dmgInstallOffer,
nextMeetingInMenuBar, listeningHistory, defaultMusicApp.

App: `AppActions.shared` (App/AppActions.swift) performs HotKeyAction / KnockAction / `toggleTab(_:)` for shortcuts, knocks,
the palette and Quick Settings; the view model registers itself and offers `togglePanelFromKeyboard()`, `openFocused(_:)`,
`toggleUserHidden()`/`isUserHidden`. `CommandPaletteController`, `KnockMonitor`, `HotKeyService.reload/suspend/resume`,
`ClipboardService.pasteCurrentAsPlainText()`, `TimerService.isAlarmRinging/stopAlarm()`, `KeepAwakeService.keepAwake(until:)`,
`AlertSoundPlayer.play(_:)/preview(_:)`, and in `Services/WorkspaceServices.swift`: `NetworkInfoService`, `TrafficService`,
`ListeningHistoryService`, `AppMaintenance`, `ShellHookInstaller`, `CodingAgentsService` (+`CodingAgentSession`),
`BluetoothConnectService` (+`PairedDevice`).

Ownership (v3.4 wave): **island agent** = Model/IslandViewModel.swift, Window/**, top-level Views/*.swift (not PanelHeader),
Core IslandLayout/IslandEngine · **input agent** = HotKeyService, KnockMonitor, ClipboardService, App/AppActions.swift,
App/CommandPalette*.swift, Views/Tabs/ClipboardTab.swift · **tabs agent** = Views/Tabs/** (not Clipboard), PanelHeader.swift,
CalendarService, CodingAgentsService, BluetoothConnectService (+ new tab helpers) · **services agent** = the rest of
Services/**, App/StatusItemController.swift, Views/Alerts/** · **settings agent** = Views/Settings/**. The tech lead owns
Core (except IslandLayout/Engine), AppSettings, AppDelegate, UITestDriver, CLAUDE.md. Installing + UI-testing the app is
serialised with the scratchpad `applock.sh` lock.

### 6.8 Header cards + Settings scene (2026-10-26, owner bug reports)
- `vm.headerCard: HeaderCard?` (`.battery`, `.sound`; `showsBatteries` kept as a computed alias). Header buttons open
  their card on **hover** (rest 0.18 s) or click; a hover-opened card closes 0.35 s after the pointer leaves button and
  card, a click-opened one stays until clicked again / elsewhere. Hit-testing: `Window/HoverRegions.swift`
  (`.hoverRegion("hover.battery" | "hover.sound" | "hover.card")`), queried by `IslandWindowController.updateHeaderHover`
  on every pointer move (so the scripted test pointer works too).
- Sound: `SoundButton` (glyph follows the volume) + `SoundCard` (live `VolumeSlider`, mute, output devices). Header
  buttons `.output` and `.volume` both show it, once. `OutputMenu` / `VolumeMenu` removed.
- The SwiftUI `Settings` scene is only a placeholder; macOS opens it by itself (⌘,, "Settings…", window restoration)
  as an empty "DynaNotch Settings" window. `SettingsSceneRedirect` closes it and opens `SettingsWindowController`
  (not during the first 3 s after launch, when it can only be a restored window); the app menu's "Settings… ⌘," is
  replaced to open the real window; the real window has `isRestorable = false`.
- Test hooks: state.json `headerCard`; `dynanotch://ui/appMenuSettings`, `dynanotch://ui/systemSettingsAction`.

### 6.9 Pill width / height (2026-10-26, owner request)
- Settings (AppSettings "MARK: Pill size", keys in `SettingsKey.all`): `pillWidth: Double = 185` (`dn.pillWidth`, stored
  150–420) and `pillHeight: Double = 36` (`dn.pillHeight`, 28–44). Both apply live and are covered by Appearance → Restore
  Defaults. They act only where the island is a floating pill (`notchDisplayStyle == .pill` on a notch display,
  `nonNotchStyle == .pill` elsewhere); the merged notch shape keeps the measured notch.
- Core `IslandLayout`: `pillHeightRange` (28…44), `defaultPillHeight` (36), `pillMaxWidth` (420),
  `pillWidthRange(notchWidth:)` (notch width … 420), `pillMetrics(width:height:notchWidth:scale:) -> NotchMetrics` — layout
  metrics of a pill whose **on-screen resting (idle) size** is `width` × `height` (clamped) at Closed Pill Size `scale`:
  `metrics.width = width / scale − 2 × idle top radius`, `height / scale`. So `pillScale` (relabelled "Pill Content Size")
  now only resizes the content inside; compact presentations add their side columns, so no pill is narrower than the notch.
- App: `ScreenLocator.physicalNotchWidth()` — measured width of the first screen with a camera notch, else
  `NotchMetrics.fallback.width` (185). `vm.pillMinWidth` exposes it; the open panel's header row follows the pill height.
- state.json: `pillWidth`, `pillHeight`, `pillMinWidth`. Settings controls: `setting-pillWidth`, `setting-pillHeight`.

### 6.10 Every display + Follow mouse (2026-10-27, owner request)
- Core `DisplayMode` += `.allDisplays` ("Every display", raw `allDisplays`). `DisplayMode.extraDisplays(all:primary:)`
  → the display IDs (order kept, duplicates dropped) that get an extra island: every display but the primary in
  `.allDisplays`, none otherwise. Behavior → Show On becomes a menu picker (5 options).
- `.allDisplays`: the **primary** island (`AppDelegate.viewModel`, `isPrimary == true`) sits where `.notchOrMain` puts it;
  `IslandScreensCoordinator` (Window/) creates one `IslandViewModel(isPrimary: false)` + `IslandWindowController(viewModel:
  pinnedDisplay:)` per extra display and rebuilds them on screen changes and when the mode changes. Extra islands show the
  same activities, hover / expand on their own, and keep each display's own shape setting. Only the primary island plays
  alert sounds, flashes the edge glow, owns the media-key handler, desktop lyrics and the state/test hooks.
  `AppActions.viewModel` follows the pointer (the island on the display under the mouse); Hide applies to every island.
- `FullscreenDetector.fullscreenDisplays: Set<CGDirectDisplayID>` (all displays in one window-list pass); a pinned
  island hides when its own display is full screen.
- `.followMouse` (existing): the single island moves to the display under the pointer.
- state.json: `islands` = [{screen, presentation, isPill, visible}] for the extra islands; hook
  `dynanotch://snapshot-extra/<name>` renders the first extra island.
- **Per-display choice (2026-11-07, owner request):** setting `hiddenDisplays: String` (`dn.hiddenDisplays`, default "")
  = comma-separated `DisplaySelection` keys ("vendor-model-serial", stable across reconnects) of displays without an
  island; `displayMode` default is now `.allDisplays`. Core `DisplaySelection.key/parse/serialize/toggled/allowed`
  (`toggled` refuses to switch off the last display that still shows one; `allowed` falls back to every display when all
  are hidden) and `DisplayMode.extraDisplays(all:[(id,key)], primary:, hidden:)`. In `.allDisplays` the primary island
  goes to the notch display, else the menu-bar display, else the first allowed one. Behavior → Show On lists each
  connected display as a switch (`setting-display-<name>`, dimmed unless Every Display). state.json `displayKeys`.
- **Full screen (2026-11-07):** Core `FullscreenHeuristic.fullscreenDisplays(windows:displays:)`: a window filling a
  display only counts when no other app has a window on that display (a window zoomed to fill a display whose menu bar
  auto-hides is not full screen).

### 6.10a Popups under the pointer (2026-11-07, owner request)
- `ActivityKind.holdsOnHover` (notification, vitals, bluetooth, calendar, timerFinished, download, lowBattery): hovering
  such a popup no longer opens the panel. `IslandViewModel.holdsPopup` keeps it (re-posted with a long life), the island
  grows to `IslandLayout.popupDetailSize` and `PopupDetailView` shows `ActivityKind.popupText` in full with **Dismiss**
  and **Open** buttons (`popup-dismiss` / `popup-open`; clicks routed by `PopupButton.button(at:cardWidth:cardHeight:
  hasTarget:)`). Leaving releases it after 1.5 s. A click elsewhere on it opens the target.
- Core `PopupTarget` (`.tab(PanelTab)` / `.url(URL)`, `buttonTitle`, `forCategory(AlertCategory)`, `openURL(String?)`
  http/https/file only) and `ActivityKind.defaultPopupTarget`. `postNotification(…, target:)`; drives open their volume.
- `NotchNotification.openURL`; `dynanotch://notify?…&open=<http|https|file URL>` sets what Open does.
- Bluetooth: Core `BluetoothAlertFilter` (in `BluetoothService`) skips `.generic` / nameless devices (phones, Continuity
  links — they showed a "radio waves" icon and "Connected") and repeats for the same device within 20 s.
- state.json `holdsPopup`, `canvasWidth`.

### 6.11 Lock screen: sounds, unlock island, widgets (2026-10-27, owner request — DECISIONS §14)
- Core `AlertCategory` += `.screenLock` ("Lock", default sound "Pop") and `.screenUnlock` ("Unlock", default "Purr");
  they appear in Popups → Alert Sounds like every category (None silences them).
- Core `LockTransitionTracker` (pure): `mutating func update(locked: Bool) -> LockTransition?` → `.locked` / `.unlocked`
  only on a change (the system can post the same notification twice). Core `LockScreenSummary.make(weather:devices:
  maxDevices:) -> LockScreenSummary` → `weather: (symbol, temperature, detail, place)?` and up to `maxDevices` device items
  (`name`, `symbol`, `level`, `isCharging`), the Mac last; devices without a level are dropped.
- Settings (Settings → Lock Screen page, keys in `SettingsKey.all`): `unlockActivity: Bool = true` (`dn.unlockActivity`,
  the "Unlocked" island when you come back), `lockScreenWidgets: Bool = true` (`dn.lockScreenWidgets`, master switch for
  the lock-screen widgets), `lockScreenWeather: Bool = true`, `lockScreenBatteries: Bool = true`.
- App: `UserPresence.lockChanges: PassthroughSubject<Bool, Never>` (main queue, on change only) and
  `UserPresence.simulateLock(_:)` for the test hook. `LockScreenController.shared` (Window/) — started by AppDelegate:
  on lock plays `.screenLock` and shows the widget strip (if enabled); on unlock hides it, plays `.screenUnlock` and posts
  `.toggle(symbol: "lock.open.fill", label: "Unlocked", on: true)` to the primary island (if `unlockActivity`).
- `SkyLightSpace.shared` (Window/): lazily `dlopen`s SkyLight on the first lock with widgets on; `isAvailable`,
  `delegate(_ window: NSWindow) -> Bool`. No private call is made while the feature is off.
- Hooks: `dynanotch://lockscreen/lock` · `lockscreen/unlock` (same path as the system notifications, never locks the Mac),
  `snapshot-lockscreen/<name>` (renders the widgets). Core `LockScreenLayout.widgetsRect(size:screenFrame:)`: centred
  on the main display (`NSScreen.screens.first`, the one showing the lock clock), top at `topFraction` (34 %) of its height. state.json `lockScreen` = {locked, shown, skyLight, delegated,
  weather, weatherStatus, devices, lastLock, result, space, onScreen, windowNumber}. `lastLock` survives the unlock so a real
  lock can be diagnosed afterwards. macOS 27: every SkyLight space call returns 3 even when it works and
  `SLSCopySpacesForWindows` doesn't list custom spaces, so the window server's on-screen list is the check. The space
  sits at absolute level 400 (`…NotificationCenterAtScreenLock`; 100 stays under the lock screen) and the window at
  `Int32.max − 2`.

### 6.12 Smart Copy · part 1: copy progress pill (2026-11-01, owner request)
- Core `ActivityKind` += `.fileCopy(name: String, fraction: Double, secondsLeft: Int?)` (category `.fileCopy`, priority 40
  so other popups show over it and it comes back, default duration 8 s, renewed on every update; not quieted by Focus;
  silent). `fraction` 1 = finished ("Done", posted for 1.5 s).
- Core `CopyProgressTracker` (pure): `update(id:name:fraction:now:)`, `remove(id:)`, `summary(now:) -> CopySummary?`
  (`label`: the item's name or "N items", `fraction`: mean of the copies, `secondsLeft`: from the overall rate once
  ≥ 3 % and ≥ 2 s in), `shouldPublish(fraction:now:)` (≥ 0.5 % change or ≥ 1 s since the last post, always at 0 / 1).
  `CopyFormat.remaining(_ seconds:) -> String` ("12 s", "3 min", "1 h 5 min").
- Setting `copyProgress: Bool = true` (`dn.copyProgress`, Popups → Privacy & Files → File Copies).
- App `FileCopyMonitor.shared` (Services/): while the setting is on, `Progress.addSubscriber(forFileURL:)` on the volume
  roots and the home folders (home, Desktop, Documents, Downloads, Movies, Music, Pictures), plus folders added on the
  fly from an FSEvents stream over home and every volume root (streams don't cross volumes; restarted on mount;
  latency 1 s, ~/Library excluded, at most 48, oldest dropped).
  Only file operation kind copying / duplicating counts (read from `userInfo`: Finder's proxies leave
  `fileOperationKind` nil). A subscription only sees copies **into that folder** (checked
  on macOS 27: `/` and parent folders see nothing). Publishes `events: PassthroughSubject<CopySummary?, Never>` on main.
- View: the pill fills green from the left by `fraction`; the text (doc icon + name left, "42 % · 1 min" right) is
  drawn white on black and dark on green, split at the fill edge.
- Hooks: `dynanotch://copy?name=&fraction=&left=` (simulated progress), `copy?done=1`. state.json `copy` = {active,
  label, fraction, subscriptions}.

### 6.13 Smart Copy · part 2: conversions (2026-11-01)
- Core `SmartConvert.convert(_ text: String, context: ConvertContext) -> SmartConversion?` for one-line text ≤ 32
  characters: currency ("€42", "42 EUR", "$1,299.99", "CHF 20" → home currency, or USD when it already is the home
  currency; EUR when home is USD), units (mi↔km, ft↔m, in↔cm, yd→m, lb↔kg, oz↔g, °F↔°C, gal↔L, fl oz↔ml, mph↔km/h),
  time ("3pm PST", "15:00 UTC" → local time, "+1 day" when it crosses midnight), numbers ("0x1F", "0b1010" → decimal;
  a 10- or 13-digit Unix timestamp → local date). `SmartConversion` = {kind, source, result, symbol}.
  `ConvertContext` = {homeCurrency, rates: CurrencyRates?, timeZone, now, locale}. Numbers accept "1,299.99" and
  "1.299,99"; a single separator followed by exactly three digits is grouping.
- Core `CurrencyRates` {base, date, rates} + `parse(_ data:)` for Frankfurter's `/v1/latest` JSON;
  `convert(_ amount:from:to:) -> Double?`.
- Core `ActivityKind` += `.conversion(source: String, result: String, symbol: String)` (category `.conversion`,
  priority 45, 4 s, quieted during Focus, silent, 110 pt sides).
- Settings (Clipboard page → Smart Copy; needs clipboard history): `smartCopy: Bool = true` (`dn.smartCopy`),
  `homeCurrency: String = "EUR"` (`dn.homeCurrency`).
- App: `ClipboardService.copiedText: PassthroughSubject<String, Never>` (main; external text copies only, never our
  own writes). `SmartCopyService.shared`: converts, fetches rates only when an amount is copied and the cache
  (`dn.data.fxRates`) is older than 12 h; `conversions: PassthroughSubject<SmartConversion, Never>`;
  `copyResult(_:)` writes the result to the clipboard as our own change. Clicking the island while a conversion
  shows copies the result ("Copied", 1.2 s) instead of expanding.
- Hooks: `dynanotch://convert?text=` (same path, clipboard untouched). state.json `smartCopy` = {last, ratesDate}.

### 6.14 Agent Island (2026-11-01)
- **Hook script** `agent-hook.pl` (App Support/DynaNotch/hooks/, perl + core JSON::PP), installed by
  `ShellHookInstaller.installAgentHooks()` into ~/.claude/settings.json (one-time backup, reversible, path override
  `DYNANOTCH_CLAUDE_SETTINGS` / `claudeSettingsOverride`): `PermissionRequest` → `agent-hook.pl permission` (hook
  timeout = Agent timeout + 30 s); `UserPromptSubmit`, `PreToolUse`, `Stop`, `Notification` → `agent-hook.pl status`; `agent-hook.pl check` prints `ok` (sanity check).
- **Handshake** in App Support/DynaNotch/agent/: the app writes `app.pid` (its pid) and `timeout` (seconds) while the
  feature is on. `permission`: if the pid is alive, writes `requests/<id>.json` {id, session, cwd, tool, input,
  createdAt} and waits up to the timeout for `answers/<id>` = `allow` | `deny` | `terminal`; prints
  `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` (deny adds
  `"message":"Denied from DynaNotch"`); `terminal`, a timeout or no app → no output (Claude asks in the terminal).
  `status`: writes `status/<session>.json` {session, cwd, event, tool, input, at}. Never blocks except `permission`.
- Core `AgentRequest` (Codable) + `AgentSummary.detail(tool:input:)` ("npm test", "Sources/App.swift", "github.com"),
  `AgentSummary.project(cwd:)`, `AgentSummary.statusDetail(event:tool:input:)` ("Thinking…", "Running npm test",
  "Editing App.swift", "Done", "Waiting for you"); `AgentDecision` (allow, deny, terminal).
- Core `ActivityKind` += `.agentRequest(id: String, project: String, tool: String, detail: String)` (category `.agent`,
  priority 97, lasts the timeout, not quieted by Focus; 150 pt sides, +66 pt below the notch row) and
  `.agentStatus(project: String, detail: String, done: Bool)` (category `.agent`, priority 35, 6 s renewed while
  working, 2.5 s when done; 110 pt sides). An answer replaces the request with a short status in the same category.
- Settings (AI Usage page → Agent Island): `agentIsland: Bool = true` (`dn.agentIsland`), `agentStatus: Bool = true`
  (`dn.agentStatus`), `agentTimeout: Double = 60` (`dn.agentTimeout`, 15–300 s); Install / Remove hooks buttons.
- App `AgentIslandService.shared`: watches `requests/` and `status/` with directory vnode sources; while requests wait,
  a 2 s check drops those whose hook process died (the id ends in its pid);
  `requests: [AgentRequest]` (oldest first), `answer(id:_:) -> Bool` (ignores requests that are gone). Hovering an
  agent request doesn't open the panel. Clicks on the card go to the island's own tap (`SpatialTapGesture`): below the title row, the
  card's thirds are Deny · Terminal · Allow (`AgentDecision.button(at:cardWidth:titleRowHeight:)`); the title row does
  nothing.
- Hooks: `dynanotch://agent/answer?id=&decision=`, `agent/install-test?settings=<copy>` (install → check → remove on
  that file, leaves `<copy>.installed`). state.json `agent` = {enabled, pending, lastAnswer, sessions, hooksInstalled, installTest}.
  Button test IDs: `agent-allow`, `agent-deny`, `agent-terminal`.

### 6.15 Drop Alchemy (2026-11-01)
- Core `AlchemyAction` (cutout, text, shrink, png, jpeg): `title`, `symbol`, `accepts(fileExtension:)` (images for
  all; PDF for text and shrink), `outputName(for:existing:)` ("Photo (cutout).png", "Photo (small).jpg",
  "Report (small).pdf", "Photo.png"; " 2", " 3" … when taken; nil for text, which goes to the clipboard).
- App `AlchemyService.shared.run(_ action:, on url:)` on a utility queue, all on this Mac: cutout = Vision
  `VNGenerateForegroundInstanceMaskRequest` → PNG; text = `VNRecognizeTextRequest` (accurate) for images, PDFKit text
  for PDFs → clipboard; shrink = longest side ≤ 2048 px, JPEG 0.75 (PNG only when it has transparency) / PDF re-saved with
  JPEG images; png / jpeg = ImageIO. Output next to the original, added to the shelf, a notification island when done
  (or why it failed). `state` = {running, last}.
- UI: Shelf tab — a row of drop zones under the toolbar (Cutout · Text · Shrink · PNG), each its own drop target
  (`alchemy-<action>` test IDs), plus the same actions in each shelf file's context menu ("Alchemy" submenu).
  Setting `alchemyZones: Bool = true` (`dn.alchemyZones`, Files & Utilities → Shelf).
- Hooks: `dynanotch://alchemy?action=<raw>&path=<file>`; `shelf/remove?path=<file>` (test cleanup).

### 6.16 Camera Guard+ and Meeting Meter (2026-11-01)
- Core `ActivityKind.sensor(SensorKind, active: Bool, app: String)` (app = who records; "" when unknown — the
  camera never says). `.call(app: String, startedAt: Date, talkShare: Int?)` (category `.call`, priority 30, 20 s
  renewed while the call lasts, 110 pt sides, not quieted by Focus).
- Core `SensorUsageLog` (Codable): `begin(_:app:at:)`, `end(_:at:)`, `sessions` newest first (sensor, app, start,
  end?), at most 50. Core `TalkMeter`: `add(level dBFS:, seconds:)` counts speech above −42 dBFS with a 0.3 s hangover;
  `share` (0…100, nil before 10 s). `CallFormat.duration(_:)` ("4:05", "1:02:09").
- App `PrivacyMonitor`: `@Published inUse: Set<SensorKind>`, `microphoneApps() -> [String]` (CoreAudio process list,
  macOS 14.2+; [] before). Changes carry the recording app. `SensorUsageLogStore` keeps the log in App Support
  (`sensor-log.json`); Settings → Popups → Camera & Microphone shows the last 8 with Clear.
- App `MeetingMeter.shared`: mic on ≥ 15 s → a call (pill: app + live timer + talk share); mic off → recap
  notification "Call 42 min · you spoke 61%". Talk share is opt-in: it listens to the mic *level* with AVAudioEngine
  (nothing recorded or stored; asks for Microphone permission the first time; `NSMicrophoneUsageDescription`).
- Settings: `sensorDot: Bool = true` (dot in the pill while the camera / mic is on), `meetingMeter: Bool = true`,
  `meetingTalkShare: Bool = false`.
- Hooks: `dynanotch://sensor?kind=camera|microphone&active=1|0&app=` (same path as the system change; a simulated
  sensor stays on until the test turns it off), `sensor/forget?app=` (test cleanup),
  state.json `privacy` = {inUse, micApps, log, call}.

### 6.17 Focus Guard and Focus Soundscapes (2026-11-01)
- Core `FocusGuard`: `isFocusing(_ state: TimerState?)` (Pomodoro, work phase, running); `apps(from:)` parses the
  comma / newline list (lower-cased bundle IDs); `defaultApps`. `DistractionTracker`: `enter(app:at:)`, `leave(at:)`,
  `seconds`, `reset()`.
- Core `Soundscape` (none, rain, brown, pink, fire): `title`, `symbol`.
- Settings (Timer page): `focusGuard: Bool = true`, `focusGuardApps: String = FocusGuard.defaultApps`,
  `soundscape: String = "none"`, `soundscapeVolume: Double = 0.4` (0…1), `soundscapeWithPomodoro: Bool = true`.
- App `FocusGuardService.shared`: `NSWorkspace.didActivateApplication`; a listed app during focus → the island shakes
  (`vm.shake()`) + notification "Back to focus · <App> · 12 min left"; when the focus phase ends with distraction time,
  "Focus done · 3 min in distractions". Hook `dynanotch://focusguard?app=<bundle id>` (same path).
- App `SoundscapeService.shared`: generated noise with `AVAudioEngine` + `AVAudioSourceNode` (no files, nothing
  network); `play(_:)`, `stop()`, `isPlaying`; with Pomodoro: starts on a focus phase, fades out on breaks / stop.
  Timer tab: a sound menu at the top right. Hooks `dynanotch://soundscape/<raw|stop>`. state.json `focus` =
  {focusing, distraction, soundscape, playing}.

### 6.18 Mac Vitals (2026-11-01)
- Core `Vitals`: `cpuPercent(previous:current:elapsed:)` (CPU ns → % of one core), `RunawayTracker.update(
  [pid: percent], now:) -> [pid]` (≥ 90 % in 2 samples in a row, each app reported once until it calms down),
  `diskLow(free:total:)` (< 10 GB or < 5 %), `thermalTitle(_ raw: Int) -> String?` (serious / critical only).
- Core `ActivityKind.vitals(title: String, detail: String, symbol: String)` (category `.vitals`, priority 92, 8 s,
  not quieted by Focus; 110 pt sides, notification height). A click opens Activity Monitor.
- Setting `macVitals: Bool = true` (`dn.macVitals`, Settings → Popups → Privacy & Files).
- App `MacVitalsService.shared`: `ProcessInfo.thermalStateDidChangeNotification`, `DispatchSource` memory pressure
  (warning / critical), disk every 10 min, app CPU every 60 s (GUI apps only, `proc_pid_rusage`; paused while away
  or off). Each alert at most once per 30 min per kind. Hook `dynanotch://vitals/<thermal|memory|disk|runaway>`
  (shows that alert with real numbers where possible). state.json `vitals`.

### 6.19 Daily Wrap (2026-11-01)
- Core `DailyWrap`: `Input` {screenSeconds, topApps [(name, seconds)], pomodoros, songs [(title, artist)], claudeCost?,
  commits?}; `lines(_:) -> [WrapLine]` (symbol + text, empty facts skipped, at most 5); `nextDate(after:minutes:
  weekdaysOnly:calendar:)`; `DurationText.hm(_:)` ("6 h 12 min", "45 min").
- Core `ActivityKind.wrap(lines: [WrapLine])` (category `.wrap`, priority 60, 20 s, quieted by Focus; 150 pt sides,
  + 30 pt + 22 pt per line). A click closes it.
- Settings (Your Mac → Activity page): `dailyWrap: Bool = true`, `dailyWrapMinutes: Double = 1080` (18:00),
  `dailyWrapWeekdays: Bool = true`.
- App `DailyWrapService.shared`: one scheduled work item for the next wrap (rescheduled on setting changes and after
  each wrap); away at that moment → shown when you're back. Commits: `git rev-list --count --since=midnight --all
  --author=<git user.email>` in up to 30 repos found 2 levels under ~/Desktop, ~/Developer, ~/Projects, ~/Code, ~/src.
  Hook `dynanotch://wrap` (now). state.json `wrap` = {next, lastLines}.

### 6.20 Voice Notes (2026-11-01)
- Core `VoiceCommand.parse(_:) -> VoiceCommand`: `.reminder(String)` ("remind me to call mum", "reminder buy milk"),
  `.timer(minutes: Double)` ("timer 10", "set a timer for 5 minutes", "10 minute timer", "timer 90 seconds",
  "timer 1 hour"), otherwise `.note(String)`. Leading "note" / "take a note" is dropped.
- Core `HotKeyAction.voiceNote` ("Voice Note", no default shortcut) and `KnockAction.voiceNote`.
- Core `ActivityKind.voice(text: String, result: String?)` (category `.voice`, priority 96, not quieted by Focus,
  150 pt sides; `result` nil = listening, renewed while listening; then 2.5 s with "Note saved" / "Reminder added" /
  "Timer 10 min").
- App `VoiceNoteService.shared.toggle()`: first use asks for Speech Recognition and Microphone access;
  `SFSpeechRecognizer` with `requiresOnDeviceRecognition` (audio never leaves the Mac; refused with a message when the
  language has no on-device model); stops on a second toggle, after 1.6 s without new words or at 30 s. Notes go to the
  Notes tab (appended line), reminders to Apple Reminders (Notes tab to-do when Reminders access is missing), timers
  to the Timer. `NSSpeechRecognitionUsageDescription` in Info.plist.
- Hooks: `dynanotch://voice?text=` (runs the command path on that transcript, no listening). state.json `voice` =
  {listening, last}.

### 6.21 Updates and What's New stories (2026-11-02, owner request — DECISIONS §16)
- Release notes live in `Packaging/WhatsNew.json` (copied into `Contents/Resources` by build.sh, uploaded as a release
  asset by `scripts/release.sh`): `[{version, date?, headline?, features: [{symbol, color, title, text}]}]`, newest
  first. `color` is a name: blue, purple, pink, red, orange, yellow, green, teal, indigo, gray. The newest entry's
  version must equal `CFBundleShortVersionString` (a Core test checks it).
- Core `AppVersion` (`init?("v3.2.0")`, `Comparable`, missing parts are 0, a `-suffix` is ignored).
- Core `FeatureNote`, `ReleaseNote` (Codable), `ReleaseNotes.decode(_:) -> [ReleaseNote]` (newest first, bad
  entries dropped), `ReleaseNotes.between(_:after:upTo:)` (versions in (after, upTo], newest first; `after` nil = only
  `upTo`), `ReleaseNotes.fromMarkdown(_:version:)` (fallback: one feature per `-`/`*` bullet of a release body).
- Core `GitHubRelease` (Decodable: tag_name, html_url, body, draft, prerelease, assets [name,
  browser_download_url, digest?]), `AvailableUpdate` {version, zipURL, sha256?, notesURL?, pageURL},
  `UpdateCheck.evaluate(_:current:) -> AvailableUpdate?` (newer, not draft / prerelease, has
  `DynaNotch-<version>.zip`), `UpdateCheck.shouldShowWhatsNew(lastSeen:current:hasSeenWelcome:) -> Bool`
  (fresh install: no; same version: no; older lastSeen or nil after the welcome: yes),
  `UpdateCheck.isDue(lastCheck:now:interval:)`.
- Setting `checkForUpdates: Bool = true` (`dn.checkForUpdates`, Settings → About). App data
  `dn.data.lastSeenVersion`, `dn.data.lastUpdateCheck`, `dn.data.notifiedUpdateVersion`.
- App `UpdateService.shared` (ObservableObject): `@Published status` (idle, checking, upToDate, available(update,
  notes), downloading(fraction), installing, failed(message)); `checkNow()`, `install()`. Asks
  `api.github.com/repos/tanim-ics/dyna-notch/releases/latest` 20 s after launch and then when a day has passed
  (timer with 1 h tolerance, off while the setting is off); no cookies, no data about the user. A newly found version
  posts one notification island. `install()`: download the zip, check the release's sha256 digest when GitHub gives
  one, `ditto -x -k`, check bundle id, version and `codesign --verify --strict` + requirement
  `identifier "com.tanim.dynanotch"`, then a detached shell helper waits for the app to quit, swaps the bundle (old one
  restored if the move fails), clears quarantine and relaunches. Not writable → opens the release page.
- App `WhatsNewController.shared`: a pop-up that grows out of the notch (like the welcome) and plays the features as
  Stories: segmented progress bars, 5 s per slide, click right → next / left third → back, hold to pause, ← → Esc.
  Modes: `.whatsNew` (after an update; ends with "Got it") and `.update` (before; ends with "Update to x.y.z" /
  "Later" and shows download progress). Shown once per new version at launch (after the hello, if any).
- UI: panel header "Update" pill (`header.update`) while an update is available; menu bar "Update to x.y.z…" /
  "Check for Updates…" and "What's New…"; Settings → About: Software Update section (auto-check toggle, status, Check
  Now / Update) and What's New (Watch the Story + list from the bundled notes).
- Hooks: `dynanotch://whatsnew` (story of the current version), `update/check`, `update/show`, `update/install`,
  `update/feed?url=` (test feed instead of GitHub, in memory), `snapshot-whatsnew/<name>`, `ui/click?window=whatsnew`.
  state.json `update` = {status, latest, lastChecked, lastSeen, story: {shown, mode, index, count, paused}}.
