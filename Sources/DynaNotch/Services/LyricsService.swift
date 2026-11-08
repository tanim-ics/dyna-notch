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
    private var lastQuery = ""
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
        lastQuery = "\(snapshot.artist) — \(snapshot.title)"
        // Browsers and YouTube send titles like "Artist - Song (Official Video)": clean them up, then try
        // the exact lookup, a search with the cleaned names and finally a title-only search matched by length.
        let cleaned = LyricsQuery.clean(title: snapshot.title, artist: snapshot.artist)
        let duration = snapshot.duration.isFinite ? snapshot.duration : 0
        var steps: [(@escaping (Result?, Bool) -> Void) -> Void] = [
            { [weak self] done in self?.fetchExact(title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
                                                  duration: duration, completion: done) },
        ]
        if cleaned.title != snapshot.title || cleaned.artist != snapshot.artist {
            steps.append { [weak self] done in self?.fetchExact(title: cleaned.title, artist: cleaned.artist, album: "",
                                                               duration: duration, completion: done) }
        }
        steps.append { [weak self] done in
            self?.fetchSearch([URLQueryItem(name: "track_name", value: cleaned.title),
                               URLQueryItem(name: "artist_name", value: cleaned.artist)],
                              artist: cleaned.artist, duration: duration, requireArtist: false, completion: done)
        }
        steps.append { [weak self] done in
            self?.fetchSearch([URLQueryItem(name: "q", value: "\(cleaned.artist) \(cleaned.title)")],
                              artist: cleaned.artist, duration: duration, requireArtist: true, completion: done)
        }
        if duration > 0 || !cleaned.artist.isEmpty {
            steps.append { [weak self] done in
                self?.fetchSearch([URLQueryItem(name: "track_name", value: cleaned.title)],
                                  artist: cleaned.artist, duration: duration, requireArtist: duration <= 0, completion: done)
            }
        }
        run(steps, key: key, sawTransient: false, plainFallback: nil)
    }

    /// Tries each lookup in turn; stops at the first synced result, keeps the first plain one as a fallback.
    private func run(_ steps: [(@escaping (Result?, Bool) -> Void) -> Void], key: String, sawTransient: Bool,
                     plainFallback: Result?) {
        guard key == currentKey else { return }
        guard let step = steps.first else {
            finish(key: key, result: plainFallback ?? Result(lines: [], plain: ""),
                   cacheable: plainFallback != nil || !sawTransient)
            return
        }
        step { [weak self] result, transient in
            guard let self = self else { return }
            if let result = result, !result.lines.isEmpty {
                self.finish(key: key, result: result, cacheable: true)
                return
            }
            let fallback = plainFallback ?? result.flatMap { $0.plain.isEmpty ? nil : $0 }
            self.run(Array(steps.dropFirst()), key: key, sawTransient: sawTransient || transient, plainFallback: fallback)
        }
    }

    /// For `dynanotch://state`.
    var state: [String: Any] {
        ["lines": lines.count, "plain": !plain.isEmpty, "loading": isLoading, "query": lastQuery,
         "current": LRCParser.currentIndex(at: NowPlayingService.shared.snapshot.elapsed(at: Date())
                                             + AppSettings.shared.lyricsOffset, in: lines) ?? -1]
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

    private func fetchExact(title: String, artist: String, album: String, duration: Double,
                            completion: @escaping (Result?, Bool) -> Void) {
        guard !title.isEmpty, !artist.isEmpty else {
            completion(nil, false)
            return
        }
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        let seconds = Int(duration.rounded())
        if seconds > 0 { items.append(URLQueryItem(name: "duration", value: String(seconds))) }
        request(path: "https://lrclib.net/api/get", items: items) { data, status in
            guard status == 200, let data = data, let parsed = LRCLibParser.parse(data) else {
                completion(nil, LyricsService.isTransient(status))
                return
            }
            completion(Result(lines: parsed.synced, plain: parsed.plain), false)
        }
    }

    private func fetchSearch(_ items: [URLQueryItem], artist: String, duration: Double, requireArtist: Bool,
                             completion: @escaping (Result?, Bool) -> Void) {
        guard items.allSatisfy({ !($0.value ?? "").trimmingCharacters(in: .whitespaces).isEmpty }) else {
            completion(nil, false)
            return
        }
        request(path: "https://lrclib.net/api/search", items: items) { data, status in
            guard status == 200, let data = data,
                  let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
                completion(nil, LyricsService.isTransient(status))
                return
            }
            var parsed: [(synced: [LyricLine], plain: String)] = []
            var candidates: [LyricsQuery.Candidate] = []
            for element in array.prefix(20) {
                guard let elementData = try? JSONSerialization.data(withJSONObject: element),
                      let result = LRCLibParser.parse(elementData) else { continue }
                parsed.append(result)
                candidates.append(LyricsQuery.Candidate(artist: element["artistName"] as? String ?? "",
                                                        duration: element["duration"] as? Double ?? 0,
                                                        hasSynced: !result.synced.isEmpty,
                                                        hasPlain: !result.plain.isEmpty))
            }
            guard let index = LyricsQuery.best(candidates, artist: artist, duration: duration,
                                               requireArtist: requireArtist) else {
                completion(nil, false)
                return
            }
            completion(Result(lines: parsed[index].synced, plain: parsed[index].plain), false)
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
                logger.debug("lrclib request failed: \(error.localizedDescription, privacy: .private)")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { completion(data, status) }
        }.resume()
    }
}
