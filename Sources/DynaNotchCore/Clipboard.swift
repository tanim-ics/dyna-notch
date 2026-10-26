import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum ClipKind: String, Equatable, Codable {
    case text, link, color, image, file
}

public struct ClipItem: Equatable, Identifiable, Codable {
    public var id: UUID
    public var kind: ClipKind
    public var text: String
    public var date: Date
    public var pinned: Bool
    public var sourceApp: String?
    /// File name inside the app's clipboard image directory.
    public var imageFile: String?

    public init(id: UUID = UUID(), kind: ClipKind, text: String, date: Date, pinned: Bool = false,
                sourceApp: String? = nil, imageFile: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.date = date
        self.pinned = pinned
        self.sourceApp = sourceApp
        self.imageFile = imageFile
    }
}

public enum ClipClassifier {
    /// http(s)/www URL (single token) → link, #RGB / #RRGGBB / #RRGGBBAA → color, else text.
    public static func kind(for text: String) -> ClipKind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .text }
        if isHexColor(t) { return .color }
        if !t.contains(where: { $0.isWhitespace }) {
            let lower = t.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") {
                if t.count > 8 { return .link }
            }
        }
        return .text
    }

    public static func preview(_ text: String, max: Int = 200) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if ch.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
            if out.count >= max { break }
        }
        return out
    }

    static func isHexColor(_ t: String) -> Bool {
        guard t.hasPrefix("#") else { return false }
        let hex = t.dropFirst()
        guard [3, 6, 8].contains(hex.count) else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }
}

public enum LinkCleaner {
    static let trackingParams: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "igshid", "igsh",
        "yclid", "_hsenc", "_hsmi", "mkt_tok", "ref_src", "ref_url",
    ]
    static let siHosts = ["youtu.be", "youtube.com", "open.spotify.com"]

    public static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ClipClassifier.kind(for: trimmed) == .link,
              let queryStart = trimmed.firstIndex(of: "?") else { return text }

        let base = String(trimmed[..<queryStart])
        var rest = String(trimmed[trimmed.index(after: queryStart)...])
        var fragment = ""
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[hash...])
            rest = String(rest[..<hash])
        }
        let host = hostOf(base)
        let stripSI = siHosts.contains { host == $0 || host.hasSuffix("." + $0) }

        let kept = rest.split(separator: "&", omittingEmptySubsequences: true).filter { pair in
            let name = pair.split(separator: "=", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
            if name.hasPrefix("utm_") { return false }
            if trackingParams.contains(name) { return false }
            if stripSI && name == "si" { return false }
            return true
        }
        if kept.isEmpty { return base + fragment }
        return base + "?" + kept.joined(separator: "&") + fragment
    }

    private static func hostOf(_ base: String) -> String {
        var s = base.lowercased()
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        return s
    }
}

public struct ClipboardHistory: Equatable, Codable {
    public var limit: Int
    public private(set) var items: [ClipItem] = []

    public init(limit: Int = 50) {
        self.limit = limit
    }

    @discardableResult
    public mutating func add(_ item: ClipItem) -> [ClipItem] {
        var item = item
        if item.kind != .image && item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        var evicted: [ClipItem] = []
        if let index = items.firstIndex(where: { isSameContent($0, item) }) {
            let old = items.remove(at: index)
            item.pinned = old.pinned
            item.id = old.id
            if item.kind == .image, let oldFile = old.imageFile, oldFile != item.imageFile {
                // Same image twice: keep the old file, report the new duplicate for deletion.
                evicted.append(item)
                item.imageFile = oldFile
            }
        }
        items.insert(item, at: 0)
        sortPinnedFirst()
        let cap = max(1, limit)
        while items.count > cap, let victim = items.lastIndex(where: { !$0.pinned }) {
            evicted.append(items.remove(at: victim))
        }
        return evicted
    }

    @discardableResult
    public mutating func remove(id: UUID) -> ClipItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    public mutating func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        sortPinnedFirst()
    }

    @discardableResult
    public mutating func clear(keepPinned: Bool = true) -> [ClipItem] {
        let removed = items.filter { !keepPinned || !$0.pinned }
        items = keepPinned ? items.filter(\.pinned) : []
        return removed
    }

    public func search(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || ($0.sourceApp?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
    }

    private func isSameContent(_ a: ClipItem, _ b: ClipItem) -> Bool {
        if a.kind == .image || b.kind == .image {
            return a.kind == b.kind && !a.text.isEmpty && a.text == b.text   // text holds the image hash
        }
        return a.text == b.text
    }

    /// Stable: pinned first, otherwise keep the current (newest-first) order.
    private mutating func sortPinnedFirst() {
        let pinned = items.filter(\.pinned)
        let rest = items.filter { !$0.pinned }
        items = pinned + rest
    }
}
