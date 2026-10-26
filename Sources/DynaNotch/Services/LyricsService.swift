import Combine
import Foundation
import os
import DynaNotchCore

/// Synced lyrics for the current track from LRCLIB, cached by track key.
final class LyricsService: ObservableObject {
    static let shared = LyricsService()

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plain: String = ""
    @Published private(set) var isLoading = false

    private struct Result {
        var lines: [LyricLine]
        var plain: String
    }

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "lyrics")
    private let session: URLSession
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var currentKey = ""
    private var cache: [String: Result] = [:]   // main queue only; misses cached as empty results
    private var cacheOrder: [String] = []
    private let cacheLimit = 50
    private static let userAgent = "DynaNotch/3.0 (personal build)"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    func start() {
        guard !started else { return }
        started = true

        // Clear immediately on track change …
        NowPlayingService.shared.$snapshot
            .removeDuplicates { $0.trackKey == $1.trackKey }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.trackChanged(snapshot) }
            .store(in: &cancellables)

        // … and fetch once the track settles.
        NowPlayingService.shared.$snapshot
            .removeDuplicates { $0.trackKey == $1.trackKey }
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.load(snapshot) }
            .store(in: &cancellables)

        AppSettings.shared.$lyricsEnabled
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled {
                    self.load(NowPlayingService.shared.snapshot)
                } else {
                    self.apply(Result(lines: [], plain: ""))
                    self.isLoading = false
                }
            }
            .store(in: &cancellables)
    }

    func currentIndex(at elapsed: Double) -> Int? {
        LRCParser.currentIndex(at: elapsed, in: lines)
    }

    // MARK: Private (main queue)

    private func trackChanged(_ snapshot: NowPlayingSnapshot) {
        currentKey = snapshot.trackKey
        if let cached = cache[snapshot.trackKey] {
            apply(cached)
        } else {
            apply(Result(lines: [], plain: ""))
        }
        isLoading = false
    }

    private func apply(_ result: Result) {
        if lines != result.lines { lines = result.lines }
        if plain != result.plain { plain = result.plain }
    }

    private func load(_ snapshot: NowPlayingSnapshot) {
        let key = snapshot.trackKey
        guard key == currentKey else { return }
        guard AppSettings.shared.lyricsEnabled, !snapshot.title.isEmpty else { return }
        if let cached = cache[key] {
            apply(cached)
            return
        }
        isLoading = true
        fetchExact(snapshot) { [weak self] result, transient in
            guard let self = self else { return }
            if let result = result {
                self.finish(key: key, result: result, cacheable: true)
            } else if transient {
                // Network trouble: show nothing, but try again next time this track comes up.
                self.finish(key: key, result: Result(lines: [], plain: ""), cacheable: false)
            } else {
                self.fetchSearch(snapshot) { [weak self] result, transient in
                    self?.finish(key: key, result: result ?? Result(lines: [], plain: ""),
                                 cacheable: result != nil || !transient)
                }
            }
        }
    }

    private func finish(key: String, result: Result, cacheable: Bool) {
        if cacheable { store(key: key, result: result) }
        guard key == currentKey else { return }   // stale response
        isLoading = false
        apply(result)
    }

    private func store(key: String, result: Result) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheLimit {
                let oldest = cacheOrder.removeFirst()
                cache.removeValue(forKey: oldest)
            }
        }
        cache[key] = result
    }

    // MARK: Network (completions delivered on main)

    /// `transient` is true for network errors / server failures (not cached).
    private static func isTransient(_ status: Int) -> Bool {
        status == 0 || status == 429 || status >= 500
    }

    private func fetchExact(_ snapshot: NowPlayingSnapshot, completion: @escaping (Result?, Bool) -> Void) {
        var items = [
            URLQueryItem(name: "track_name", value: snapshot.title),
            URLQueryItem(name: "artist_name", value: snapshot.artist),
        ]
        if !snapshot.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: snapshot.album))
        }
        let duration = Int(snapshot.duration.rounded())
        if snapshot.duration.isFinite, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(duration)))
        }
        request(path: "https://lrclib.net/api/get", items: items) { data, status in
            guard status == 200, let data = data, let parsed = LRCLibParser.parse(data) else {
                completion(nil, LyricsService.isTransient(status))
                return
            }
            completion(Result(lines: parsed.synced, plain: parsed.plain), false)
        }
    }

    private func fetchSearch(_ snapshot: NowPlayingSnapshot, completion: @escaping (Result?, Bool) -> Void) {
        let items = [
            URLQueryItem(name: "track_name", value: snapshot.title),
            URLQueryItem(name: "artist_name", value: snapshot.artist),
        ]
        request(path: "https://lrclib.net/api/search", items: items) { data, status in
            guard status == 200, let data = data,
                  let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
                completion(nil, LyricsService.isTransient(status))
                return
            }
            var plainFallback: Result?
            for element in array {
                guard let elementData = try? JSONSerialization.data(withJSONObject: element),
                      let parsed = LRCLibParser.parse(elementData) else { continue }
                if !parsed.synced.isEmpty {
                    completion(Result(lines: parsed.synced, plain: parsed.plain), false)
                    return
                }
                if plainFallback == nil, !parsed.plain.isEmpty {
                    plainFallback = Result(lines: [], plain: parsed.plain)
                }
            }
            completion(plainFallback, false)
        }
    }

    private func request(path: String, items: [URLQueryItem], completion: @escaping (Data?, Int) -> Void) {
        var components = URLComponents(string: path)
        components?.queryItems = items
        guard let url = components?.url else {
            DispatchQueue.main.async { completion(nil, 0) }
            return
        }
        var request = URLRequest(url: url)
        request.setValue(LyricsService.userAgent, forHTTPHeaderField: "User-Agent")
        let logger = self.logger
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                logger.debug("lrclib request failed: \(error.localizedDescription, privacy: .public)")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { completion(data, status) }
        }.resume()
    }
}
