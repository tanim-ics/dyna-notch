import AppKit
import Foundation
import os

/// Fallback artwork via the public iTunes Search API, for players that do not report artwork.
/// Results (including misses) are cached per query. Completion is always called on the main queue.
final class ArtworkLookup {
    static let shared = ArtworkLookup()

    private let cache = NSCache<NSString, NSImage>()
    private var misses = Set<String>()                          // main queue only
    private var pending: [String: [(NSImage?) -> Void]] = [:]   // main queue only
    private let session: URLSession
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "artwork")

    private static let noisePattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\s*[\(\[][^\)\]]*\b(official|video|audio|lyric|lyrics|visuali[sz]er|mv|hd|4k|remaster(ed)?)\b[^\)\]]*[\)\]]"#,
        options: [.caseInsensitive]
    )

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
        cache.countLimit = 64
    }

    func lookup(title: String, artist: String, completion: @escaping (NSImage?) -> Void) {
        let query = ArtworkLookup.makeQuery(title: title, artist: artist)
        guard !query.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        DispatchQueue.main.async {
            self.lookupOnMain(query: query, completion: completion)
        }
    }

    // MARK: Private

    private func lookupOnMain(query: String, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: query as NSString) {
            completion(cached)
            return
        }
        if misses.contains(query) {
            completion(nil)
            return
        }
        if pending[query] != nil {
            pending[query]?.append(completion)
            return
        }
        pending[query] = [completion]

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else {
            finish(query: query, image: nil)
            return
        }

        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                self.logger.debug("iTunes search failed: \(error.localizedDescription, privacy: .public)")
            }
            guard let data = data, let artURL = ArtworkLookup.artworkURL(fromSearchResponse: data) else {
                DispatchQueue.main.async { self.finish(query: query, image: nil) }
                return
            }
            self.session.dataTask(with: artURL) { [weak self] imageData, _, _ in
                guard let self = self else { return }
                var image: NSImage?
                if let imageData = imageData {
                    image = NSImage(data: imageData)
                }
                DispatchQueue.main.async { self.finish(query: query, image: image) }
            }.resume()
        }.resume()
    }

    private func finish(query: String, image: NSImage?) {
        if let image = image {
            cache.setObject(image, forKey: query as NSString)
        } else {
            misses.insert(query)
        }
        let callbacks = pending.removeValue(forKey: query) ?? []
        for callback in callbacks { callback(image) }
    }

    private static func artworkURL(fromSearchResponse data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = object as? [String: Any],
              let results = root["results"] as? [[String: Any]],
              let first = results.first,
              let small = first["artworkUrl100"] as? String else { return nil }
        let large = small.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: large)
    }

    static func cleanTitle(_ title: String) -> String {
        var result = title
        if let regex = noisePattern {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeQuery(title: String, artist: String) -> String {
        let cleanArtist = artist
            .replacingOccurrences(of: " - Topic", with: "")
            .replacingOccurrences(of: "VEVO", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = cleanTitle(title)
        let parts = [cleanArtist, cleanedTitle].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}
