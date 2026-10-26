import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct LyricLine: Equatable {
    public var time: TimeInterval
    public var text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public enum LRCParser {
    /// "[mm:ss.xx]text", several tags per line, [offset:+/-ms] honoured, metadata tags skipped, sorted by time.
    public static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        var offset: TimeInterval = 0
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let t = timestamp(tag) {
                    times.append(t)
                } else if tag.lowercased().hasPrefix("offset:") {
                    let value = tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)
                    if let ms = Double(value) { offset = ms / 1000 }
                }
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times {
                lines.append(LyricLine(time: t, text: text))
            }
        }
        // A positive offset means lyrics appear earlier.
        if offset != 0 {
            lines = lines.map { LyricLine(time: max(0, $0.time - offset), text: $0.text) }
        }
        return lines.enumerated()
            .sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }
            .map(\.element)
    }

    /// Last line with time <= t.
    public static func currentIndex(at time: TimeInterval, in lines: [LyricLine]) -> Int? {
        guard let first = lines.first, time >= first.time else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].time <= time { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// "mm:ss", "mm:ss.xx", "mm:ss:xx", "mm:ss.xxx".
    static func timestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        var secondsPart = String(parts[1])
        if parts.count == 3 { secondsPart += "." + parts[2] }
        guard let seconds = Double(secondsPart), seconds >= 0, seconds < 60 else { return nil }
        return Double(minutes) * 60 + seconds
    }
}

public enum LRCLibParser {
    /// LRCLIB `/api/get` JSON → (synced lines, plain text). nil on garbage; instrumental → ([], "").
    public static func parse(_ data: Data) -> (synced: [LyricLine], plain: String)? {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        if dict["instrumental"] as? Bool == true { return ([], "") }
        let synced = (dict["syncedLyrics"] as? String).map(LRCParser.parse) ?? []
        let plain = dict["plainLyrics"] as? String ?? ""
        if synced.isEmpty && plain.isEmpty && dict["id"] == nil { return nil }
        return (synced, plain)
    }
}
