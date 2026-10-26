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
public struct NotchNotification: Equatable { public var title: String; public var body: String; public var symbol: String; public var duration: TimeInterval? }
public enum NotifyURL {
    /// dynanotch://notify?title=&body=&symbol=&duration= (title or body required; symbol default "bell.fill"; duration 1...30)
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
