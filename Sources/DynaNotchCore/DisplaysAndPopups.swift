import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Show On → Every display: per-display choice (CONTRACTS §6.10)

/// Which displays get an island in `.allDisplays`. Displays are named by a stable key (vendor-model-serial), so the
/// choice survives reconnects and display-ID changes. Stored in `dn.hiddenDisplays` as a comma-separated key list.
public enum DisplaySelection {
    /// "vendor-model-serial"; two identical monitors without serial numbers share a key.
    public static func key(vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        "\(vendor)-\(model)-\(serial)"
    }

    public static func parse(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    public static func serialize(_ keys: Set<String>) -> String {
        keys.sorted().joined(separator: ",")
    }

    /// Turns one display on or off; refuses to hide the last display that still shows the island
    /// (`connected` = keys of the displays plugged in now).
    public static func toggled(_ stored: String, key: String, show: Bool, connected: [String]) -> String {
        var hidden = parse(stored)
        if show {
            hidden.remove(key)
        } else {
            let remaining = connected.filter { $0 != key && !hidden.contains($0) }
            guard !remaining.isEmpty else { return stored }
            hidden.insert(key)
        }
        return serialize(hidden)
    }

    /// Displays (in `preferred` order) that may show an island; if every connected display is hidden, all of them
    /// (a hidden-everything state left over from unplugging must never leave the user with no island).
    public static func allowed(_ displays: [(id: UInt32, key: String)], hidden: Set<String>) -> [UInt32] {
        let shown = displays.filter { !hidden.contains($0.key) }.map(\.id)
        return shown.isEmpty ? displays.map(\.id) : shown
    }
}

extension DisplayMode {
    /// `.allDisplays` with some displays switched off: the extra islands are the allowed displays minus the primary.
    public func extraDisplays(all: [(id: UInt32, key: String)], primary: UInt32?, hidden: Set<String>) -> [UInt32] {
        extraDisplays(all: DisplaySelection.allowed(all, hidden: hidden), primary: primary)
    }
}

// MARK: - Full-screen detection

/// Decides which displays show a full-screen app from the on-screen window list.
/// A window filling a display only counts when no *other* app has a window on that display: a real full-screen app
/// owns its own Space, while a window merely zoomed to fill the screen (menu bar set to auto-hide) still has other
/// apps' windows behind it.
public enum FullscreenHeuristic {
    public struct Window: Equatable {
        public var pid: Int32
        public var bounds: CGRect
        public init(pid: Int32, bounds: CGRect) {
            self.pid = pid
            self.bounds = bounds
        }
    }

    public static func fullscreenDisplays(windows: [Window], displays: [(id: UInt32, bounds: CGRect)],
                                          tolerance: CGFloat = 2) -> Set<UInt32> {
        var result = Set<UInt32>()
        for display in displays {
            let covering = windows.filter { matches($0.bounds, display.bounds, tolerance) }
            guard let owner = covering.first?.pid else { continue }
            let others = windows.contains { window in
                window.pid != owner && window.bounds.width > 1 && window.bounds.height > 1
                    && window.bounds.intersects(display.bounds.insetBy(dx: tolerance, dy: tolerance))
            }
            if !others { result.insert(display.id) }
        }
        return result
    }

    static func matches(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }
}

// MARK: - Bluetooth popups

/// Which Bluetooth connect / disconnect events become a popup. Unclassified devices (phones, Continuity / Handoff
/// links, unknown gadgets) are skipped, and a device that connects and drops again within `cooldown` only shows once.
public struct BluetoothAlertFilter: Equatable {
    public var cooldown: TimeInterval
    private var lastShown: [String: Date] = [:]

    public init(cooldown: TimeInterval = 60) {
        self.cooldown = cooldown
    }

    public mutating func shouldShow(address: String, kind: BluetoothDeviceKind, name: String, now: Date) -> Bool {
        guard kind != .generic, !name.isEmpty else { return false }
        if let last = lastShown[address], now.timeIntervalSince(last) < cooldown { return false }
        lastShown[address] = now
        return true
    }
}

// MARK: - Popups the pointer can act on

/// What a click on a popup opens.
public enum PopupTarget: Equatable {
    case tab(PanelTab)
    case url(URL)

    /// Default target for an app-originated popup of this alert category (nil = nothing to open).
    public static func forCategory(_ category: AlertCategory) -> PopupTarget? {
        switch category {
        case .timers: return .tab(.timer)
        case .calendar: return .tab(.calendar)
        case .battery, .devices: return .tab(.system)
        case .aiUsage: return .tab(.aiUsage)
        case .downloads:
            return .url(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
        case .notifications, .screenLock, .screenUnlock: return nil
        }
    }

    /// Label of the Open button.
    public var buttonTitle: String {
        switch self {
        case .tab(let tab): return "Open \(tab.title)"
        case .url(let url):
            if url.isFileURL { return url.pathExtension == "app" ? "Open \(url.deletingPathExtension().lastPathComponent)" : "Show in Finder" }
            return "Open Link"
        }
    }

    /// `dynanotch://notify?open=` — web links only. Anyone can post a notification, so it must never open a local
    /// file or app (a `file://` link to a script or .app would run it on click).
    public static func openURL(_ string: String?) -> URL? {
        guard let string = string, let url = URL(string: string), let host = url.host, !host.isEmpty,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }
}

extension ActivityKind {
    /// Popups that stay while the pointer is on them (instead of opening the panel) and act on a click.
    public var holdsOnHover: Bool {
        switch self {
        case .notification, .vitals, .bluetooth, .calendar, .timerFinished, .download, .lowBattery: return true
        default: return false
        }
    }

    /// Title, message and symbol of a held popup (nil for kinds that don't hold).
    public var popupText: (title: String, body: String, symbol: String)? {
        switch self {
        case let .notification(title, body, symbol):
            return (title, body, symbol.isEmpty ? "bell.fill" : symbol)
        case let .vitals(title, detail, symbol):
            return (title, detail, symbol)
        case let .bluetooth(name, device, battery, connected):
            let status = connected ? (battery.map { "Connected · \($0) %" } ?? "Connected") : "Disconnected"
            return (name, status, device.symbolName)
        case let .calendar(title, minutesUntil):
            return (title, minutesUntil <= 0 ? "Starting now" : "Starts in \(minutesUntil) min", "calendar")
        case let .timerFinished(label):
            return ("Timer finished", label, "timer")
        case let .download(name, finished):
            return (name, finished ? "Downloaded" : "Downloading", "arrow.down.circle.fill")
        case let .lowBattery(level):
            return ("Low Battery", "\(Format.percent(level)) left", "battery.25percent")
        default:
            return nil
        }
    }

    /// Where a click on this popup goes when its sender named no target.
    public var defaultPopupTarget: PopupTarget? {
        switch self {
        case .calendar: return .tab(.calendar)
        case .timerFinished: return .tab(.timer)
        case .bluetooth, .lowBattery: return .tab(.system)
        case .download:
            return .url(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
        case .vitals: return .url(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        default: return nil
        }
    }
}

/// The two buttons under a hovered notification: Dismiss on the left half, Open on the right
/// (Dismiss fills the row when there is nothing to open). Points are card-local, origin top-left.
public enum PopupButton: Equatable {
    case dismiss, open

    public static let rowHeight: CGFloat = 30

    public static func button(at point: CGPoint, cardWidth: CGFloat, cardHeight: CGFloat, hasTarget: Bool) -> PopupButton? {
        guard point.y >= cardHeight - rowHeight - 6, point.y <= cardHeight, point.x >= 0, point.x <= cardWidth else {
            return nil
        }
        guard hasTarget else { return .dismiss }
        return point.x < cardWidth / 2 ? .dismiss : .open
    }
}
