import Foundation

// MARK: - Versions

/// A dotted version such as "3.2.0" or "v3.3" (CONTRACTS §6.21). Missing parts count as 0 and a "-beta" style suffix
/// is ignored, so "3.3" == "3.3.0" and "v3.3.0-rc1" == "3.3.0".
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[..<dash]) }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        var parts: [Int] = []
        for piece in pieces {
            guard let value = Int(piece), value >= 0 else { return nil }
            parts.append(value)
        }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func part(_ index: Int) -> Int { index < parts.count ? parts[index] : 0 }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) where lhs.part(index) != rhs.part(index) {
            return lhs.part(index) < rhs.part(index)
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

// MARK: - Release notes

/// One slide of the What's New story.
public struct FeatureNote: Codable, Equatable {
    public var symbol: String
    /// Colour name: blue, purple, pink, red, orange, yellow, green, teal, indigo, gray.
    public var color: String
    public var title: String
    public var text: String

    public init(symbol: String = "sparkles", color: String = "purple", title: String, text: String = "") {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.text = text
    }

    private enum CodingKeys: String, CodingKey { case symbol, color, title, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "sparkles"
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "purple"
    }
}

/// The features one version brought (`Packaging/WhatsNew.json`).
public struct ReleaseNote: Codable, Equatable {
    public var version: String
    public var date: String?
    public var headline: String?
    public var features: [FeatureNote]

    public init(version: String, date: String? = nil, headline: String? = nil, features: [FeatureNote]) {
        self.version = version
        self.date = date
        self.headline = headline
        self.features = features
    }
}

public enum ReleaseNotes {
    /// Decodes the notes file; entries with an unreadable version or no features are dropped. Newest first.
    public static func decode(_ data: Data) -> [ReleaseNote] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        let decoder = JSONDecoder()
        let notes: [ReleaseNote] = raw.compactMap { entry in
            guard JSONSerialization.isValidJSONObject(entry),
                  let entryData = try? JSONSerialization.data(withJSONObject: entry),
                  let note = try? decoder.decode(ReleaseNote.self, from: entryData),
                  AppVersion(note.version) != nil, !note.features.isEmpty else { return nil }
            return note
        }
        return sorted(notes)
    }

    /// Notes for versions in (after, upTo], newest first. `after` nil: just `upTo`'s own notes.
    public static func between(_ notes: [ReleaseNote], after: String?, upTo: String) -> [ReleaseNote] {
        guard let top = AppVersion(upTo) else { return [] }
        let floor = after.flatMap(AppVersion.init)
        return sorted(notes.filter { note in
            guard let version = AppVersion(note.version) else { return false }
            if let floor = floor { return floor < version && version <= top }
            return version == top
        })
    }

    /// Fallback when a release has no notes file: one feature per "-" / "*" bullet of the release body.
    public static func fromMarkdown(_ body: String, version: String) -> ReleaseNote? {
        let features: [FeatureNote] = body.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { return nil }
            let text = String(trimmed.dropFirst(2)).replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            // "Title: explanation" → title + text; otherwise the whole line is the title.
            if let colon = text.range(of: ": "), text.distance(from: text.startIndex, to: colon.lowerBound) <= 40 {
                return FeatureNote(title: String(text[..<colon.lowerBound]), text: String(text[colon.upperBound...]))
            }
            return FeatureNote(title: text)
        }
        return features.isEmpty ? nil : ReleaseNote(version: version, features: features)
    }

    private static func sorted(_ notes: [ReleaseNote]) -> [ReleaseNote] {
        notes.sorted { lhs, rhs in
            guard let left = AppVersion(lhs.version), let right = AppVersion(rhs.version) else { return false }
            return left > right
        }
    }
}

// MARK: - Update check

/// The parts of GitHub's `releases/latest` answer that the update check reads.
public struct GitHubRelease: Decodable, Equatable {
    public struct Asset: Decodable, Equatable {
        public var name: String
        public var downloadURL: URL
        /// "sha256:<hex>" on newer GitHub releases.
        public var digest: String?

        public init(name: String, downloadURL: URL, digest: String? = nil) {
            self.name = name
            self.downloadURL = downloadURL
            self.digest = digest
        }

        private enum CodingKeys: String, CodingKey {
            case name, digest
            case downloadURL = "browser_download_url"
        }
    }

    public var tagName: String
    public var pageURL: URL
    public var body: String?
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [Asset]

    public init(tagName: String, pageURL: URL, body: String? = nil, draft: Bool = false, prerelease: Bool = false,
                assets: [Asset]) {
        self.tagName = tagName
        self.pageURL = pageURL
        self.body = body
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case body, draft, prerelease, assets
        case tagName = "tag_name"
        case pageURL = "html_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        pageURL = try container.decode(URL.self, forKey: .pageURL)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }
}

public struct AvailableUpdate: Equatable {
    public var version: String
    public var zipURL: URL
    /// Lowercase hex, when GitHub published a digest for the zip.
    public var sha256: String?
    public var notesURL: URL?
    public var pageURL: URL
    public var body: String?

    public init(version: String, zipURL: URL, sha256: String? = nil, notesURL: URL? = nil, pageURL: URL,
                body: String? = nil) {
        self.version = version
        self.zipURL = zipURL
        self.sha256 = sha256
        self.notesURL = notesURL
        self.pageURL = pageURL
        self.body = body
    }
}

public enum UpdateCheck {
    public static let notesAssetName = "WhatsNew.json"

    public static func zipName(version: String) -> String { "DynaNotch-\(version).zip" }

    /// The release as an update, when it is newer than `current`, published, and carries the app zip.
    public static func evaluate(_ release: GitHubRelease, current: String) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let latest = AppVersion(release.tagName), let installed = AppVersion(current), installed < latest else {
            return nil
        }
        let version = latest.description
        let tagVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let names = Set([zipName(version: version), zipName(version: tagVersion)])
        guard let zip = release.assets.first(where: { names.contains($0.name) }) else { return nil }
        var sha: String?
        if let digest = zip.digest?.lowercased(), digest.hasPrefix("sha256:") {
            let hex = String(digest.dropFirst("sha256:".count))
            if hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) { sha = hex }
        }
        let notes = release.assets.first { $0.name == notesAssetName }?.downloadURL
        return AvailableUpdate(version: version, zipURL: zip.downloadURL, sha256: sha, notesURL: notes,
                               pageURL: release.pageURL, body: release.body)
    }

    /// Play the What's New story at launch? Not on a fresh install (the welcome runs), not twice for one version.
    public static func shouldShowWhatsNew(lastSeen: String?, current: String, hasSeenWelcome: Bool) -> Bool {
        guard let installed = AppVersion(current) else { return false }
        guard let seen = lastSeen.flatMap(AppVersion.init) else { return hasSeenWelcome }
        return seen < installed
    }

    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = 86_400) -> Bool {
        guard let last = lastCheck else { return true }
        return now.timeIntervalSince(last) >= interval || now < last
    }
}
