import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// v3.4 (§2e P2) — pure types shared by the app's hotkeys, knock, Home cards, alert sounds, links and history.

// MARK: - Hotkeys

/// What a global shortcut does.
public enum HotKeyAction: String, Equatable, Hashable, CaseIterable, Codable {
    case togglePanel, clipboard, hide, commandPalette, emergencyQuit, joinMeeting, openCalendar, pastePlainText
    case startPomodoro, toggleKeepAwake

    public var title: String {
        switch self {
        case .togglePanel: return "Open DynaNotch"
        case .clipboard: return "Open Clipboard"
        case .hide: return "Hide DynaNotch"
        case .commandPalette: return "Command Palette"
        case .emergencyQuit: return "Emergency Quit"
        case .joinMeeting: return "Join Next Meeting"
        case .openCalendar: return "Open Calendar App"
        case .pastePlainText: return "Paste as Plain Text"
        case .startPomodoro: return "Start Pomodoro"
        case .toggleKeepAwake: return "Toggle Keep Awake"
        }
    }
}

/// Carbon-style key binding: virtual key code + Carbon modifier mask (cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096).
public struct HotKeyBinding: Equatable, Hashable, Codable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096

    /// "⌃⌥N" — modifiers in macOS order ⌃⌥⇧⌘, then the key.
    public var display: String {
        var s = ""
        if modifiers & HotKeyBinding.control != 0 { s += "⌃" }
        if modifiers & HotKeyBinding.option != 0 { s += "⌥" }
        if modifiers & HotKeyBinding.shift != 0 { s += "⇧" }
        if modifiers & HotKeyBinding.command != 0 { s += "⌘" }
        return s + HotKeyBinding.keyName(keyCode)
    }

    /// ANSI US layout names for the virtual key codes a shortcut normally uses.
    public static func keyName(_ code: UInt32) -> String {
        let letters: [UInt32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
            45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
            42: "\\", 50: "`",
        ]
        return letters[code] ?? "Key \(code)"
    }
}

/// All shortcuts, stored in one settings string: "togglePanel=45:6144;clipboard=9:6144;tab.timer=17:6144".
/// Keys are `HotKeyAction` raw values or "tab.<PanelTab>". An action stored with no binding ("hide=") is cleared.
public struct HotKeyMap: Equatable {
    public var bindings: [String: HotKeyBinding]

    public init(bindings: [String: HotKeyBinding] = [:]) {
        self.bindings = bindings
    }

    private static let ctrlOpt = HotKeyBinding.control | HotKeyBinding.option

    /// Factory shortcuts (⌃⌥N, ⌃⌥V, ⌥Space, ⌃⌥K, ⌃⌥⌘Q, ⌃⌥J, ⌃⌥C); tabs have none.
    public static let defaults = HotKeyMap(bindings: [
        HotKeyAction.togglePanel.rawValue: HotKeyBinding(keyCode: 45, modifiers: ctrlOpt),
        HotKeyAction.clipboard.rawValue: HotKeyBinding(keyCode: 9, modifiers: ctrlOpt),
        HotKeyAction.hide.rawValue: HotKeyBinding(keyCode: 49, modifiers: HotKeyBinding.option),
        HotKeyAction.commandPalette.rawValue: HotKeyBinding(keyCode: 40, modifiers: ctrlOpt),
        HotKeyAction.emergencyQuit.rawValue: HotKeyBinding(keyCode: 12, modifiers: ctrlOpt | HotKeyBinding.command),
        HotKeyAction.joinMeeting.rawValue: HotKeyBinding(keyCode: 38, modifiers: ctrlOpt),
        HotKeyAction.openCalendar.rawValue: HotKeyBinding(keyCode: 8, modifiers: ctrlOpt),
    ])

    public static func tabKey(_ tab: PanelTab) -> String { "tab." + tab.rawValue }

    public func binding(for key: String) -> HotKeyBinding? { bindings[key] }
    public func binding(for action: HotKeyAction) -> HotKeyBinding? { bindings[action.rawValue] }

    /// Parses the settings string on top of `defaults`; "action=" clears a default; unknown keys are kept as-is.
    public static func parse(_ s: String) -> HotKeyMap {
        var map = HotKeyMap.defaults
        for part in s.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let value = pair[1].split(separator: ":")
            if value.count == 2, let code = UInt32(value[0]), let mods = UInt32(value[1]) {
                map.bindings[key] = HotKeyBinding(keyCode: code, modifiers: mods)
            } else {
                map.bindings[key] = nil
            }
        }
        return map
    }

    /// Only differences from `defaults` are written (cleared defaults as "key="), sorted for stable output.
    public func serialize() -> String {
        var parts: [String] = []
        let keys = Set(bindings.keys).union(HotKeyMap.defaults.bindings.keys).sorted()
        for key in keys {
            let mine = bindings[key]
            if mine == HotKeyMap.defaults.bindings[key] { continue }
            if let b = mine {
                parts.append("\(key)=\(b.keyCode):\(b.modifiers)")
            } else {
                parts.append("\(key)=")
            }
        }
        return parts.joined(separator: ";")
    }

    /// Another key already using `binding`, if any (the recorder warns about duplicates).
    public func conflict(for binding: HotKeyBinding, excluding key: String) -> String? {
        bindings.first(where: { $0.key != key && $0.value == binding })?.key
    }
}

// MARK: - Knock (tap a modifier key 1–3 times)

public enum KnockKey: String, Equatable, Hashable, CaseIterable {
    case control, option, command, shift

    public var title: String {
        switch self {
        case .control: return "Control ⌃"
        case .option: return "Option ⌥"
        case .command: return "Command ⌘"
        case .shift: return "Shift ⇧"
        }
    }
}

public enum KnockAction: String, Equatable, Hashable, CaseIterable {
    case none, togglePanel, clipboard, commandPalette, playPause, lockScreen, toggleKeepAwake, screenshot, timer

    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .togglePanel: return "Open DynaNotch"
        case .clipboard: return "Clipboard"
        case .commandPalette: return "Command Palette"
        case .playPause: return "Play / Pause"
        case .lockScreen: return "Lock Screen"
        case .toggleKeepAwake: return "Keep Awake"
        case .screenshot: return "Screenshot"
        case .timer: return "Timer"
        }
    }

    /// "1=togglePanel,2=clipboard,3=commandPalette" → [1: …]; unknown entries dropped.
    public static func parseMap(_ s: String) -> [Int: KnockAction] {
        var map: [Int: KnockAction] = [:]
        for part in s.split(separator: ",") {
            let pair = part.split(separator: "=")
            guard pair.count == 2, let n = Int(pair[0].trimmingCharacters(in: .whitespaces)), (1...3).contains(n),
                  let action = KnockAction(rawValue: pair[1].trimmingCharacters(in: .whitespaces)) else { continue }
            map[n] = action
        }
        return map
    }

    public static func serializeMap(_ map: [Int: KnockAction]) -> String {
        map.keys.sorted().compactMap { n in map[n].map { "\(n)=\($0.rawValue)" } }.joined(separator: ",")
    }
}

/// Counts quick taps of a lone modifier key. Feed every press/release of the chosen modifier (and `interrupt()` on any
/// other key or modifier); after the last tap, `settle(now:)` returns the count once `window` has passed.
public struct KnockDetector: Equatable {
    public var window: TimeInterval
    public var maxHold: TimeInterval
    public private(set) var count = 0
    private var downAt: Date?
    private var lastTapAt: Date?

    public init(window: TimeInterval = 0.35, maxHold: TimeInterval = 0.3) {
        self.window = window
        self.maxHold = maxHold
    }

    public mutating func press(at date: Date) {
        if let last = lastTapAt, date.timeIntervalSince(last) > window { count = 0 }
        downAt = date
    }

    public mutating func release(at date: Date) {
        guard let down = downAt else { return }
        downAt = nil
        if date.timeIntervalSince(down) <= maxHold {
            count = min(count + 1, 3)
            lastTapAt = date
        } else {
            reset()
        }
    }

    /// Another key was used together with the modifier: not a knock.
    public mutating func interrupt() { reset() }

    /// Number of taps once the sequence is over (no new tap within `window`), else nil.
    public mutating func settle(now: Date) -> Int? {
        guard count > 0, downAt == nil, let last = lastTapAt, now.timeIntervalSince(last) > window else { return nil }
        let n = count
        reset()
        return n
    }

    private mutating func reset() {
        count = 0
        downAt = nil
        lastTapAt = nil
    }
}

// MARK: - Home cards

public enum HomeCard: String, Equatable, Hashable, CaseIterable, Codable {
    case music, calendar, upNext, weather, timer, worldClock, network, batteries, sun, links, colors, agents, bluetooth

    public var title: String {
        switch self {
        case .music: return "Now Playing"
        case .calendar: return "Calendar"
        case .upNext: return "Up Next"
        case .weather: return "Weather"
        case .timer: return "Timer"
        case .worldClock: return "World Clock"
        case .network: return "Network"
        case .batteries: return "Device Batteries"
        case .sun: return "Sunrise & Sunset"
        case .links: return "Saved Links"
        case .colors: return "Colors"
        case .agents: return "Coding Agents"
        case .bluetooth: return "Bluetooth"
        }
    }

    public var symbolName: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .upNext: return "list.bullet.rectangle"
        case .weather: return "cloud.sun.fill"
        case .timer: return "timer"
        case .worldClock: return "globe"
        case .network: return "network"
        case .batteries: return "battery.75percent"
        case .sun: return "sunrise.fill"
        case .links: return "link"
        case .colors: return "paintpalette.fill"
        case .agents: return "terminal.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        }
    }

    /// Grid slots the card takes (wide cards span two columns).
    public var span: Int {
        switch self {
        case .music, .calendar: return 2
        default: return 1
        }
    }

    public static let defaultList: [HomeCard] = [.music, .calendar, .weather, .timer, .upNext]

    /// "music,weather" → cards (unknown dropped, duplicates removed); empty string → `defaultList`.
    public static func parseList(_ s: String) -> [HomeCard] {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return defaultList }
        var seen = Set<HomeCard>()
        var out: [HomeCard] = []
        for part in s.split(separator: ",") {
            guard let card = HomeCard(rawValue: part.trimmingCharacters(in: .whitespaces)), !seen.contains(card) else { continue }
            seen.insert(card)
            out.append(card)
        }
        return out
    }

    public static func serialize(_ cards: [HomeCard]) -> String { cards.map(\.rawValue).joined(separator: ",") }

    /// Slots used by `cards` (for the settings preview "6 of 8 slots").
    public static func slotsUsed(_ cards: [HomeCard]) -> Int { cards.reduce(0) { $0 + $1.span } }
}

// MARK: - Look, popups, sounds

public enum ClockContent: String, Equatable, Hashable, CaseIterable {
    case time, date, timeAndDate

    public var title: String {
        switch self {
        case .time: return "Time"
        case .date: return "Date"
        case .timeAndDate: return "Time and Date"
        }
    }
}

public enum PanelSizing: String, Equatable, Hashable, CaseIterable {
    case fixed, fitContent

    public var title: String {
        switch self {
        case .fixed: return "Fixed Size"
        case .fitContent: return "Fit Content"
        }
    }
}

/// Title / artist on the compact Now Playing island.
public enum TrackInfoMode: String, Equatable, Hashable, CaseIterable {
    case onChange, always, never

    public var title: String {
        switch self {
        case .onChange: return "When the Track Changes"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

public enum AlertCategory: String, Equatable, Hashable, CaseIterable {
    case timers, calendar, battery, devices, downloads, notifications, aiUsage

    public var title: String {
        switch self {
        case .timers: return "Timers"
        case .calendar: return "Calendar"
        case .battery: return "Battery"
        case .devices: return "Devices"
        case .downloads: return "Downloads & Files"
        case .notifications: return "Notifications"
        case .aiUsage: return "AI Usage"
        }
    }
}

/// Per-category alert sound, stored as "timers=Glass,battery=None". Missing → default for the category.
public enum AlertSounds {
    public static let none = "None"
    /// macOS system sounds in /System/Library/Sounds.
    public static let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop",
                                      "Purr", "Sosumi", "Submarine", "Tink"]

    public static func defaultSound(for category: AlertCategory) -> String {
        switch category {
        case .timers: return "Glass"
        case .calendar: return "Ping"
        default: return none
        }
    }

    public static func parse(_ s: String) -> [AlertCategory: String] {
        var map: [AlertCategory: String] = [:]
        for part in s.split(separator: ",") {
            let pair = part.split(separator: "=")
            guard pair.count == 2, let category = AlertCategory(rawValue: String(pair[0]).trimmingCharacters(in: .whitespaces))
            else { continue }
            map[category] = String(pair[1]).trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    public static func sound(for category: AlertCategory, in s: String) -> String {
        parse(s)[category] ?? defaultSound(for: category)
    }

    public static func setting(_ sound: String, for category: AlertCategory, in s: String) -> String {
        var map = parse(s)
        map[category] = sound
        return AlertCategory.allCases.compactMap { c in map[c].map { "\(c.rawValue)=\($0)" } }.joined(separator: ",")
    }
}

// MARK: - Links, engines, history

public struct SavedLink: Equatable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var url: String

    public init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

/// JSON helpers for list-valued settings (saved links, custom search engines …).
public enum JSONList {
    public static func decode<T: Decodable>(_ s: String, as type: T.Type) -> [T] {
        guard let data = s.data(using: .utf8), !s.isEmpty else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    public static func encode<T: Encodable>(_ items: [T]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Played tracks (Now Playing → listening history) with optional bookmark.
public struct ListenEntry: Equatable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var app: String?
    public var playedAt: Date
    public var bookmarked: Bool

    public init(id: UUID = UUID(), title: String, artist: String, album: String = "", app: String? = nil,
                playedAt: Date, bookmarked: Bool = false) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.app = app
        self.playedAt = playedAt
        self.bookmarked = bookmarked
    }
}

public struct ListeningHistory: Equatable, Codable {
    public var limit: Int
    public private(set) var entries: [ListenEntry] = []   // newest first

    public init(limit: Int = 500) {
        self.limit = limit
    }

    /// Adds a play unless the same title+artist is already the newest entry. Bookmarked entries are never evicted.
    public mutating func record(_ entry: ListenEntry) {
        if let first = entries.first, first.title == entry.title, first.artist == entry.artist { return }
        entries.insert(entry, at: 0)
        while entries.count > limit, let index = entries.lastIndex(where: { !$0.bookmarked }) {
            entries.remove(at: index)
        }
    }

    public mutating func toggleBookmark(id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].bookmarked.toggle()
    }

    public mutating func clear(keepBookmarks: Bool = true) {
        entries = keepBookmarks ? entries.filter(\.bookmarked) : []
    }

    public var bookmarks: [ListenEntry] { entries.filter(\.bookmarked) }
}

/// Bytes moved per day (Connectivity → network traffic history).
public struct TrafficLedger: Equatable, Codable {
    public struct Day: Equatable, Codable {
        public var day: String          // "yyyy-MM-dd" in the user's calendar
        public var received: UInt64
        public var sent: UInt64
    }

    public private(set) var days: [Day] = []   // oldest first

    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func add(received: UInt64, sent: UInt64, at date: Date, calendar: Calendar = .current) {
        let key = TrafficLedger.dayKey(date, calendar: calendar)
        if let i = days.lastIndex(where: { $0.day == key }) {
            days[i].received &+= received
            days[i].sent &+= sent
        } else {
            days.append(Day(day: key, received: received, sent: sent))
        }
    }

    /// Totals over the last `count` days including today.
    public func total(lastDays count: Int, now: Date, calendar: Calendar = .current) -> (received: UInt64, sent: UInt64) {
        var keys = Set<String>()
        for offset in 0..<max(1, count) {
            if let d = calendar.date(byAdding: .day, value: -offset, to: now) { keys.insert(TrafficLedger.dayKey(d, calendar: calendar)) }
        }
        return days.filter { keys.contains($0.day) }.reduce((UInt64(0), UInt64(0))) { ($0.0 &+ $1.received, $0.1 &+ $1.sent) }
    }

    public mutating func prune(keepDays: Int, now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) else { return }
        let key = TrafficLedger.dayKey(cutoff, calendar: calendar)
        days.removeAll { $0.day < key }
    }

    public mutating func clear() { days = [] }
}
