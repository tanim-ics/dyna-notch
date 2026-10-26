import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Tabs of the expanded notch panel (Notchy-style).
public enum PanelTab: String, Equatable, Hashable, CaseIterable, Codable {
    case home, nowPlaying, timer, clipboard, shelf, notes, calculator, emoji, quickSearch, launcher, shortcuts, reminders,
         mirror, system, aiUsage, calendar, quickSettings

    public var title: String {
        switch self {
        case .home: return "Home"
        case .nowPlaying: return "Now Playing"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .shelf: return "Shelf"
        case .notes: return "Notes"
        case .calculator: return "Calculator"
        case .emoji: return "Emoji"
        case .quickSearch: return "Quick Search"
        case .launcher: return "Launcher"
        case .shortcuts: return "Shortcuts"
        case .reminders: return "Reminders"
        case .mirror: return "Mirror"
        case .system: return "System"
        case .aiUsage: return "AI Usage"
        case .calendar: return "Calendar"
        case .quickSettings: return "Quick Settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .home: return "house.fill"
        case .nowPlaying: return "music.note"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "tray.full.fill"
        case .notes: return "note.text"
        case .calculator: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .quickSearch: return "magnifyingglass"
        case .launcher: return "square.grid.3x3.fill"
        case .shortcuts: return "square.2.layers.3d.fill"
        case .reminders: return "checklist"
        case .mirror: return "web.camera.fill"
        case .system: return "cpu"
        case .aiUsage: return "sparkles"
        case .calendar: return "calendar"
        case .quickSettings: return "switch.2"
        }
    }

    /// Parses "home,timer" (unknown ids dropped, duplicates removed, order kept); empty → allCases.
    public static func parseList(_ s: String) -> [PanelTab] {
        var seen = Set<PanelTab>()
        var result: [PanelTab] = []
        for part in s.split(separator: ",") {
            let id = part.trimmingCharacters(in: .whitespaces)
            guard let tab = PanelTab(rawValue: id), !seen.contains(tab) else { continue }
            seen.insert(tab)
            result.append(tab)
        }
        return result.isEmpty ? PanelTab.allCases : result
    }

    public static func serialize(_ tabs: [PanelTab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }

    /// Tabs that existed in v3 / v3.1, before the app started recording which tabs it knows about.
    public static let v3Tabs: [PanelTab] = [.home, .nowPlaying, .timer, .clipboard, .shelf, .notes, .system, .aiUsage]

    /// Appends tabs the stored list has never seen (added in a newer version) so they show up after an
    /// update; tabs the user removed stay removed. `known` = tabs present when the list was last migrated
    /// (nil → `v3Tabs`). New tabs go before System / AI Usage when those are at the end.
    public static func migrate(stored: String, known: String?) -> String {
        let current = parseList(stored)
        let knownTabs = known.map { parseList($0) } ?? v3Tabs
        let added = allCases.filter { !knownTabs.contains($0) && !current.contains($0) }
        guard !added.isEmpty else { return serialize(current) }
        var result = current
        var insertAt = result.count
        while insertAt > 0, [.system, .aiUsage].contains(result[insertAt - 1]) { insertAt -= 1 }
        result.insert(contentsOf: added, at: insertAt)
        return serialize(result)
    }
}

/// Optional controls on the right of the panel header (Settings → Tabs → Header Buttons).
public enum HeaderButtonID: String, Equatable, Hashable, CaseIterable, Codable {
    case battery, timer, stopwatch, pomodoro, output, volume, keepAwake, mic, screenshot, scanQR, colorPicker, ports,
         systemStats, actions, pin, lock

    public static let defaultList: [HeaderButtonID] = [.battery, .output, .keepAwake, .actions, .pin, .lock]

    public var title: String {
        switch self {
        case .battery: return "Battery"
        case .timer: return "Timer"
        case .stopwatch: return "Stopwatch"
        case .pomodoro: return "Pomodoro"
        case .output: return "Sound Output"
        case .volume: return "Volume"
        case .scanQR: return "Scan QR Code"
        case .ports: return "Ports"
        case .systemStats: return "System Stats"
        case .keepAwake: return "Keep Awake"
        case .mic: return "Microphone"
        case .screenshot: return "Screenshot"
        case .colorPicker: return "Color Picker"
        case .actions: return "Actions Menu"
        case .pin: return "Pin"
        case .lock: return "Lock Screen"
        }
    }

    public var symbolName: String {
        switch self {
        case .battery: return "battery.75percent"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        case .pomodoro: return "brain.head.profile"
        case .output: return "speaker.wave.2.fill"
        case .volume: return "speaker.wave.3.fill"
        case .scanQR: return "qrcode.viewfinder"
        case .ports: return "point.3.connected.trianglepath.dotted"
        case .systemStats: return "gauge.with.dots.needle.50percent"
        case .keepAwake: return "cup.and.saucer.fill"
        case .mic: return "mic.fill"
        case .screenshot: return "camera.viewfinder"
        case .colorPicker: return "eyedropper"
        case .actions: return "ellipsis.circle"
        case .pin: return "pin.fill"
        case .lock: return "lock.fill"
        }
    }

    /// Parses "battery,pin" (unknown ids dropped, duplicates removed). Unlike tabs, an empty list stays empty.
    public static func parseList(_ s: String) -> [HeaderButtonID] {
        var seen = Set<HeaderButtonID>()
        var result: [HeaderButtonID] = []
        for part in s.split(separator: ",") {
            let id = part.trimmingCharacters(in: .whitespaces)
            guard let button = HeaderButtonID(rawValue: id), !seen.contains(button) else { continue }
            seen.insert(button)
            result.append(button)
        }
        return result
    }

    /// Serialised in canonical display order (allCases), so toggling keeps a stable header layout.
    public static func serialize(_ buttons: Set<HeaderButtonID>) -> String {
        allCases.filter { buttons.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}
