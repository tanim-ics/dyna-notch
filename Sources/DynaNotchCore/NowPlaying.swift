import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct NowPlayingSnapshot: Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var elapsed: Double
    public var timestamp: Date
    public var playbackRate: Double
    public var isPlaying: Bool
    /// parentBundle if non-empty else bundle.
    public var bundleIdentifier: String?
    public var artworkIdentifier: String?
    public var artworkData: Data?

    public init(title: String = "", artist: String = "", album: String = "", duration: Double = 0, elapsed: Double = 0,
                timestamp: Date = Date(), playbackRate: Double = 0, isPlaying: Bool = false,
                bundleIdentifier: String? = nil, artworkIdentifier: String? = nil, artworkData: Data? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.bundleIdentifier = bundleIdentifier
        self.artworkIdentifier = artworkIdentifier
        self.artworkData = artworkData
    }

    public static let empty = NowPlayingSnapshot(timestamp: Date(timeIntervalSince1970: 0))

    /// Title empty.
    public var isEmpty: Bool { title.isEmpty }

    public var trackKey: String { title + "\u{1F}" + artist + "\u{1F}" + album }

    /// Playing: elapsed + Δt·(rate > 0 ? rate : 1), clamped to 0...duration (if duration > 0).
    public func elapsed(at now: Date) -> Double {
        var value = elapsed.isFinite ? elapsed : 0
        if isPlaying {
            let rate = playbackRate > 0 && playbackRate.isFinite ? playbackRate : 1
            value += now.timeIntervalSince(timestamp) * rate
        }
        value = max(0, value)
        if duration > 0 && duration.isFinite {
            value = min(value, duration)
        }
        return value
    }

    /// 0...1, 0 if duration <= 0.
    public func progress(at now: Date) -> Double {
        guard duration > 0, duration.isFinite else { return 0 }
        return min(1, max(0, elapsed(at: now) / duration))
    }
}

public enum AdapterMessage: Equatable {
    case ready, nowPlaying(NowPlayingSnapshot), empty, error(String), unknown
}

public enum AdapterParser {
    /// Parses one JSON line from the adapter. Keys: type ("ready"|"nowPlaying"|"error"), empty, title, artist, album,
    /// duration, elapsed, rate, timestamp (unix seconds), playing, bundle, parentBundle, artworkId, artwork (base64), message.
    /// Tolerates NSNull, numbers-as-strings, missing keys, garbage (→ .unknown).
    public static func parse(line: String) -> AdapterMessage {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any] else {
            return .unknown
        }
        guard let type = string(dict["type"]) else { return .unknown }
        switch type {
        case "ready":
            return .ready
        case "error":
            return .error(string(dict["message"]) ?? "")
        case "nowPlaying":
            if bool(dict["empty"]) == true { return .empty }
            guard let title = string(dict["title"]), !title.isEmpty else { return .empty }
            let rate = double(dict["rate"]) ?? 0
            let timestamp = double(dict["timestamp"]).map { Date(timeIntervalSince1970: $0) } ?? Date()
            var artwork: Data?
            if let encoded = string(dict["artwork"]) {
                let cleaned = encoded.components(separatedBy: .whitespacesAndNewlines).joined()
                if let decoded = Data(base64Encoded: cleaned), !decoded.isEmpty {
                    artwork = decoded
                }
            }
            let snapshot = NowPlayingSnapshot(
                title: title,
                artist: string(dict["artist"]) ?? "",
                album: string(dict["album"]) ?? "",
                duration: nonNegative(double(dict["duration"])),
                elapsed: nonNegative(double(dict["elapsed"])),
                timestamp: timestamp,
                playbackRate: rate.isFinite ? rate : 0,
                isPlaying: bool(dict["playing"]) ?? (rate > 0),
                bundleIdentifier: nonEmpty(string(dict["parentBundle"])) ?? nonEmpty(string(dict["bundle"])),
                artworkIdentifier: nonEmpty(string(dict["artworkId"])),
                artworkData: artwork
            )
            return .nowPlaying(snapshot)
        default:
            return .unknown
        }
    }

    // MARK: - Tolerant value extraction

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        return s
    }

    private static func nonNegative(_ d: Double?) -> Double {
        guard let d = d, d.isFinite, d > 0 else { return 0 }
        return d
    }

    static func string(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let s = value as? String {
            return Double(s.trimmingCharacters(in: .whitespaces))
        }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let b = value as? Bool { return b ? 1 : 0 }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let b = value as? Bool { return b }
        if let s = value as? String {
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return Double(s).map { $0 != 0 }
            }
        }
        if let n = value as? NSNumber { return n.doubleValue != 0 }
        return nil
    }
}
