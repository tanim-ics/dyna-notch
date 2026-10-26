import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Tabs of the expanded notch panel (Notchy-style).
public enum PanelTab: String, Equatable, Hashable, CaseIterable, Codable {
    case home, nowPlaying, timer, clipboard, shelf, notes, system, aiUsage

    public var title: String {
        switch self {
        case .home: return "Home"
        case .nowPlaying: return "Now Playing"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .shelf: return "Shelf"
        case .notes: return "Notes"
        case .system: return "System"
        case .aiUsage: return "AI Usage"
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
        case .system: return "cpu"
        case .aiUsage: return "sparkles"
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
}
