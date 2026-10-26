import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum DownloadNames {
    static let partialExtensions = ["download", "crdownload", "part", "partial", "opdownload"]

    public static func isPartial(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let ext = name[name.index(after: dot)...].lowercased()
        return partialExtensions.contains(ext)
    }

    /// Strips the partial extension ("x.zip.download" → "x.zip").
    public static func finalName(_ partial: String) -> String {
        guard isPartial(partial), let dot = partial.lastIndex(of: ".") else { return partial }
        return String(partial[..<dot])
    }
}

/// Diffs successive listings of the Downloads folder.
public struct DownloadTracker {
    private var known: Set<String>?

    public init() {}

    public mutating func update(_ names: Set<String>) -> (started: [String], finished: [String]) {
        defer { known = names }
        guard let previous = known else { return ([], []) }
        let started = names.subtracting(previous).filter(DownloadNames.isPartial).sorted()
        let finished = previous.subtracting(names)
            .filter(DownloadNames.isPartial)
            .map(DownloadNames.finalName)
            .filter { names.contains($0) }
            .sorted()
        return (started, finished)
    }
}
