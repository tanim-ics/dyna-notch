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

    /// Wall-clock moments when the visible line changes: `now`, then the start of every later line (at most `limit`),
    /// given the song position `elapsed` at `now` and the playback `rate` (0 = paused → only `now`).
    public static func changeDates(lines: [LyricLine], elapsed: TimeInterval, rate: Double, now: Date,
                                   limit: Int = 200) -> [Date] {
        guard rate > 0 else { return [now] }
        let upcoming = lines.lazy.filter { $0.time > elapsed }.prefix(limit)
        return [now] + upcoming.map { now.addingTimeInterval(($0.time - elapsed) / rate) }
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

/// Turns what a player reports (often a browser / YouTube title) into an LRCLIB query, and picks the best search hit.
public enum LyricsQuery {
    public struct Candidate: Equatable {
        public var artist: String
        public var duration: Double
        public var hasSynced: Bool
        public var hasPlain: Bool

        public init(artist: String, duration: Double, hasSynced: Bool, hasPlain: Bool) {
            self.artist = artist
            self.duration = duration
            self.hasSynced = hasSynced
            self.hasPlain = hasPlain
        }
    }

    private static let noise = ["official", "video", "audio", "lyric", "visualizer", "visualiser", "remaster",
                                "hd", "4k", "mv", "live", "explicit", "clean", "music"]

    /// "Kings of Leon - Topic" → "Kings of Leon"; "A, B & C" / "A • Album" / "A feat. B" → "A".
    public static func cleanArtist(_ artist: String) -> String {
        var s = artist.trimmingCharacters(in: .whitespaces)
        for suffix in [" - Topic", "VEVO", " Official"] where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        for separator in [" • ", " · ", ", ", " & ", " feat. ", " feat ", " ft. ", " x ", " X ", " and "] {
            if let range = s.range(of: separator), range.lowerBound > s.startIndex {
                s = String(s[..<range.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Drops "(Official Video)", "[Lyrics]", "(feat. X)", "| Topic" tails and an "Artist - " prefix.
    /// Returns (title, artist); the artist is taken from "Artist - Title" when the player sent none.
    public static func clean(title: String, artist: String) -> (title: String, artist: String) {
        var t = title
        // Bracketed tails with noise words or features.
        var changed = true
        while changed {
            changed = false
            for (open, close) in [("(", ")"), ("[", "]"), ("【", "】")] {
                guard let o = t.range(of: open, options: .backwards),
                      let c = t.range(of: close, range: o.upperBound..<t.endIndex) else { continue }
                let inner = t[o.upperBound..<c.lowerBound].lowercased()
                let words = inner.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                if inner.hasPrefix("feat") || inner.hasPrefix("ft.") || inner.hasPrefix("with ")
                    || words.contains(where: { noise.contains($0) || $0 == "lyrics" || $0 == "remastered" }) {
                    t.removeSubrange(o.lowerBound..<c.upperBound)
                    t = t.trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
        }
        if let bar = t.range(of: " | ") { t = String(t[..<bar.lowerBound]) }
        for marker in [" feat. ", " ft. "] {
            if let r = t.range(of: marker, options: .caseInsensitive) { t = String(t[..<r.lowerBound]) }
        }
        var a = cleanArtist(artist)
        if let dash = t.range(of: " - ") {
            let left = t[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = t[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            if a.isEmpty {
                a = cleanArtist(left)
                t = right
            } else if left.lowercased() == a.lowercased() || left.lowercased() == artist.lowercased() {
                t = right
            }
        }
        return (t.trimmingCharacters(in: .whitespaces), a)
    }

    /// Index of the best hit: synced before plain; with a known duration only hits within 3 s count (closest first),
    /// otherwise the first hit whose artist matches (or, with `requireArtist == false`, the first one).
    public static func best(_ candidates: [Candidate], artist: String, duration: Double,
                            requireArtist: Bool = false) -> Int? {
        let wanted = cleanArtist(artist).lowercased()
        func artistMatches(_ c: Candidate) -> Bool {
            guard !wanted.isEmpty else { return true }
            let have = c.artist.lowercased()
            return have.contains(wanted) || wanted.contains(cleanArtist(c.artist).lowercased())
        }
        func pick(_ ok: (Candidate) -> Bool) -> Int? {
            let usable = candidates.indices.filter { ok(candidates[$0]) }
                .filter { !requireArtist || artistMatches(candidates[$0]) }
            if duration > 0 {
                let timed = usable.filter { candidates[$0].duration <= 0 || abs(candidates[$0].duration - duration) <= 3 }
                return timed.min { abs(candidates[$0].duration - duration) < abs(candidates[$1].duration - duration) }
            }
            return usable.first(where: { artistMatches(candidates[$0]) }) ?? (requireArtist ? nil : usable.first)
        }
        return pick { $0.hasSynced } ?? pick { $0.hasPlain }
    }
}
