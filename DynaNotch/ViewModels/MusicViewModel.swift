import Foundation
import AppKit
import Combine
import CoreAudio

class MusicViewModel: ObservableObject {
    @Published var title:    String   = ""
    @Published var artist:   String   = ""
    @Published var albumArt: NSImage? = nil
    @Published var isPlaying: Bool    = false
    @Published var progress:  Double  = 0
    @Published var duration:  Double  = 1
    @Published var appName:   String  = ""

    private typealias MRGetNowPlayingInfoFn  = @convention(c) (DispatchQueue, @escaping (NSDictionary) -> Void) -> Void
    private typealias MRSendCommandFn        = @convention(c) (UInt32, NSDictionary?) -> Bool
    private typealias MRRegisterForNotifsFn  = @convention(c) (DispatchQueue) -> Void
    private typealias MRGetNowPlayingPIDFn   = @convention(c) (DispatchQueue, @escaping (pid_t) -> Void) -> Void
    private typealias MRIsPlayingFn          = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    private var mrGetInfo:    MRGetNowPlayingInfoFn?
    private var mrSendCmd:    MRSendCommandFn?
    private var mrGetPID:     MRGetNowPlayingPIDFn?
    private var mrIsPlaying:  MRIsPlayingFn?

    private var progressTimer: AnyCancellable?
    private var pollTimer:     AnyCancellable?
    private var lastTickTime:  Date   = Date()
    private var isAudioOutputRunning: Bool = false

    private var lastTrackKey: String = ""
    private var artworkCache: [String: NSImage] = [:]

    static let shared = MusicViewModel()

    private init() {
        loadMediaRemote()
        setupAudioDeviceObserver()
        startTimers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    // MARK: – Load MediaRemote
    private func loadMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let url    = NSURL(fileURLWithPath: path) as CFURL?,
              let bundle = CFBundleCreate(kCFAllocatorDefault, url) else { return }
        _ = CFBundleLoadExecutable(bundle)

        func sym<T>(_ name: String) -> T? {
            guard let p = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        mrGetInfo   = sym("MRMediaRemoteGetNowPlayingInfo")
        mrSendCmd   = sym("MRMediaRemoteSendCommand")
        mrGetPID    = sym("MRMediaRemoteGetNowPlayingApplicationPID")
        mrIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        print("[DynaNotch] loadMediaRemote: getInfo=\(mrGetInfo != nil) sendCmd=\(mrSendCmd != nil)")

        if let reg: MRRegisterForNotifsFn = sym("MRMediaRemoteRegisterForNowPlayingNotifications") {
            reg(.main)
        }

        registerDarwinNotifications()

        let dist = DistributedNotificationCenter.default()
        let distNames = [
            "com.apple.NowPlayingInfoCenter.nowPlayingInfoDidChange",
            "com.apple.mediaremote.nowplayinginfo",
        ]
        for n in distNames {
            dist.addObserver(self, selector: #selector(fetchNowPlaying),
                             name: NSNotification.Name(n), object: nil)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTestMusicPreview),
            name: .testMusicPreview,
            object: nil
        )

        dist.addObserver(
            self,
            selector: #selector(handleTestMusicPreview),
            name: NSNotification.Name("DynaNotch.testMusicPreview"),
            object: nil
        )
    }

    private func registerDarwinNotifications() {
        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ]
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()

        let cb: CFNotificationCallback = { _, rawObs, _, _, _ in
            guard let rawObs else { return }
            let vm = Unmanaged<MusicViewModel>.fromOpaque(rawObs).takeUnretainedValue()
            DispatchQueue.main.async { vm.fetchNowPlaying() }
        }
        for name in names {
            CFNotificationCenterAddObserver(center, rawSelf, cb,
                name as CFString, nil, .deliverImmediately)
        }
    }

    // MARK: – CoreAudio Output Device Monitoring
    private func setupAudioDeviceObserver() {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &propertySize,
            &defaultOutputDeviceID
        )
        guard status == noErr, defaultOutputDeviceID != 0 else { return }

        checkAudioOutputRunning(device: defaultOutputDeviceID)

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        _ = AudioObjectAddPropertyListenerBlock(
            defaultOutputDeviceID,
            &runningAddress,
            DispatchQueue.main,
            { [weak self] _, _ in
                self?.checkAudioOutputRunning(device: defaultOutputDeviceID)
            }
        )
    }

    private func checkAudioOutputRunning(device: AudioDeviceID) {
        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            device,
            &runningAddress,
            0, nil,
            &isRunningSize,
            &isRunning
        )
        let running = (status == noErr && isRunning > 0)
        self.isAudioOutputRunning = running

        DispatchQueue.main.async {
            if running && !self.title.isEmpty {
                self.isPlaying = true
            } else if !running && !self.title.isEmpty && self.isPlaying {
                self.isPlaying = false
            }
        }
    }

    // MARK: – Timers
    private func startTimers() {
        // Smooth 0.25s progress ticker
        progressTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let now = Date()
                let delta = now.timeIntervalSince(self.lastTickTime)
                self.lastTickTime = now

                guard self.isPlaying, self.duration > 0 else { return }
                self.progress = min(self.progress + delta, self.duration)
            }

        // Periodic 2.0s poll to ensure NowPlaying state is always fresh
        pollTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchNowPlaying()
                if self?.title.isEmpty ?? true {
                    self?.fetchFromActiveBrowserIfEmpty()
                }
            }
    }

    // MARK: – Fetch Now Playing
    @objc func fetchNowPlaying() {
        guard let mrGetInfo else {
            print("[DynaNotch] fetchNowPlaying: mrGetInfo is nil")
            return
        }

        let workQueue = DispatchQueue(label: "com.tanim.dynanotch.mr", qos: .userInitiated)
        mrGetInfo(workQueue) { [weak self] info in
            guard let self else { return }

            var rawTitle  = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? ""
            var rawArtist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
            print("[DynaNotch] mrGetInfo callback received: title='\(rawTitle)', artist='\(rawArtist)'")

            // Intelligently parse "Artist - Title" if artist is empty
            if rawArtist.isEmpty && rawTitle.contains(" - ") {
                let parts = rawTitle.components(separatedBy: " - ")
                if parts.count >= 2 {
                    rawArtist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    rawTitle = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            let rate: Double = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
                ?? (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0)
            let baseElapsed: Double = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue
                ?? (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0)
            let dur: Double = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue
                ?? (info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0)

            let timestamp: Date = (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)
                ?? (info["kMRMediaRemoteNowPlayingInfoCurrentPlaybackDate"] as? Date)
                ?? Date()

            let timeSinceTimestamp = max(0, Date().timeIntervalSince(timestamp))
            let currentElapsed: Double = (rate > 0)
                ? min(baseElapsed + timeSinceTimestamp * rate, dur > 0 ? dur : Double.infinity)
                : baseElapsed

            // Extract artwork data from MediaRemote if available
            var directArtImage: NSImage? = nil
            if let rawData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] {
                var data: Data?
                if let d = rawData as? Data {
                    data = d
                } else if CFGetTypeID(rawData as CFTypeRef) == CFDataGetTypeID() {
                    data = (rawData as! CFData) as Data
                }
                if let data, !data.isEmpty {
                    directArtImage = NSImage(data: data)
                }
            }

            DispatchQueue.main.async {
                let trackKey = "\(rawTitle)|\(rawArtist)"
                let isNewTrack = (trackKey != self.lastTrackKey && !rawTitle.isEmpty)

                if isNewTrack {
                    self.lastTrackKey = trackKey
                    self.title = rawTitle
                    self.artist = rawArtist
                    self.duration = dur > 0 ? dur : 1
                    self.progress = currentElapsed
                    self.lastTickTime = Date()

                    if let img = directArtImage {
                        self.albumArt = img
                        self.artworkCache[trackKey] = img
                    } else if let cached = self.artworkCache[trackKey] {
                        self.albumArt = cached
                    } else {
                        self.albumArt = nil
                        self.resolveArtwork(title: rawTitle, artist: rawArtist)
                    }
                } else if !rawTitle.isEmpty {
                    self.duration = dur > 0 ? dur : 1
                    if abs(self.progress - currentElapsed) > 1.2 || self.progress == 0 {
                        self.progress = currentElapsed
                    }
                    self.lastTickTime = Date()

                    if self.albumArt == nil {
                        if let img = directArtImage {
                            self.albumArt = img
                            self.artworkCache[trackKey] = img
                        } else if let cached = self.artworkCache[trackKey] {
                            self.albumArt = cached
                        } else {
                            self.resolveArtwork(title: rawTitle, artist: rawArtist)
                        }
                    }
                }

                if rate > 0 {
                    self.isPlaying = true
                } else if self.isAudioOutputRunning && !rawTitle.isEmpty {
                    self.isPlaying = true
                } else if rate == 0 && !self.isAudioOutputRunning {
                    self.isPlaying = false
                }
            }
        }

        mrIsPlaying?(.main) { [weak self] isAppPlaying in
            guard let self else { return }
            DispatchQueue.main.async {
                if isAppPlaying { self.isPlaying = true }
            }
        }

        mrGetPID?(.main) { [weak self] pid in
            guard let self, pid > 0, let app = NSRunningApplication(processIdentifier: pid) else { return }
            var resolvedName = app.localizedName ?? ""
            let bundleId = (app.bundleIdentifier ?? "").lowercased()

            if bundleId.contains("cinhimbnkkaeohfgghhklpknlkffjgod") || bundleId.contains("youtube") || resolvedName.localizedCaseInsensitiveContains("youtube") {
                resolvedName = "YouTube Music"
            } else if bundleId.contains("spotify") {
                resolvedName = "Spotify"
            } else if bundleId.contains("apple.music") {
                resolvedName = "Apple Music"
            } else if bundleId.contains("browser") || bundleId.contains("chrome") || bundleId.contains("safari") || bundleId.contains("brave") || bundleId.contains("arc") {
                if self.title.localizedCaseInsensitiveContains("youtube") || self.artist.localizedCaseInsensitiveContains("youtube") {
                    resolvedName = "YouTube Music"
                } else if resolvedName.isEmpty {
                    resolvedName = "YouTube Music"
                }
            }

            if !resolvedName.isEmpty {
                DispatchQueue.main.async { self.appName = resolvedName }
            }
        }
    }

    @objc private func handleTestMusicPreview() {
        DispatchQueue.main.async {
            self.title = "A Gallant Gentleman"
            self.artist = "We Lost The Sea"
            self.appName = "YouTube Music"
            self.duration = 364
            self.progress = 72
            self.isPlaying = true
            self.resolveArtwork(title: "A Gallant Gentleman", artist: "We Lost The Sea")
        }
    }

    private func fetchFromActiveBrowserIfEmpty() {
        guard self.title.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let script = """
            tell application "System Events"
                set runningBrowsers to {}
                if exists (first process whose name is "Brave Browser") then copy "Brave Browser" to end of runningBrowsers
                if exists (first process whose name is "Google Chrome") then copy "Google Chrome" to end of runningBrowsers
                if exists (first process whose name is "Arc") then copy "Arc" to end of runningBrowsers
                if exists (first process whose name is "Safari") then copy "Safari" to end of runningBrowsers
            end tell

            repeat with b in runningBrowsers
                set appName to b as text
                try
                    if appName is "Safari" then
                        tell application "Safari"
                            repeat with w in windows
                                repeat with t in tabs of w
                                    set u to URL of t
                                    if u contains "music.youtube.com/watch" or u contains "youtube.com/watch" then
                                        set ttl to title of t
                                        return ttl & "|||" & u
                                    end if
                                end repeat
                            end repeat
                        end tell
                    else if appName is "Brave Browser" then
                        tell application "Brave Browser"
                            repeat with w in windows
                                repeat with t in tabs of w
                                    set u to URL of t
                                    if u contains "music.youtube.com/watch" or u contains "youtube.com/watch" then
                                        set ttl to title of t
                                        return ttl & "|||" & u
                                    end if
                                end repeat
                            end repeat
                        end tell
                    else if appName is "Google Chrome" then
                        tell application "Google Chrome"
                            repeat with w in windows
                                repeat with t in tabs of w
                                    set u to URL of t
                                    if u contains "music.youtube.com/watch" or u contains "youtube.com/watch" then
                                        set ttl to title of t
                                        return ttl & "|||" & u
                                    end if
                                end repeat
                            end repeat
                        end tell
                    else if appName is "Arc" then
                        tell application "Arc"
                            repeat with w in windows
                                repeat with t in tabs of w
                                    set u to URL of t
                                    if u contains "music.youtube.com/watch" or u contains "youtube.com/watch" then
                                        set ttl to title of t
                                        return ttl & "|||" & u
                                    end if
                                end repeat
                            end repeat
                        end tell
                    end if
                end try
            end repeat
            return ""
            """
            var err: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let res = appleScript.executeAndReturnError(&err).stringValue ?? ""
                if !res.isEmpty && res.contains("|||") {
                    let parts = res.components(separatedBy: "|||")
                    var tabTitle = parts[0]
                        .replacingOccurrences(of: " - YouTube Music", with: "")
                        .replacingOccurrences(of: " - YouTube", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    var artistName = "YouTube Music"
                    if tabTitle.contains(" - ") {
                        let sub = tabTitle.components(separatedBy: " - ")
                        artistName = sub[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        tabTitle = sub[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    DispatchQueue.main.async {
                        guard self.title.isEmpty else { return }
                        self.title = tabTitle
                        self.artist = artistName
                        self.appName = "YouTube Music"
                        self.isPlaying = self.isAudioOutputRunning
                        self.resolveArtwork(title: tabTitle, artist: artistName)
                    }
                }
            }
        }
    }

    // MARK: – Artwork Resolution
    private func resolveArtwork(title: String, artist: String) {
        let key = "\(title)|\(artist)"
        if let cached = artworkCache[key] {
            self.albumArt = cached
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // 1. YouTube Video thumbnail via active browser tabs
            if let ytId = self.findActiveYouTubeVideoId() {
                let urlStr = "https://img.youtube.com/vi/\(ytId)/hqdefault.jpg"
                if let url = URL(string: urlStr),
                   let data = try? Data(contentsOf: url),
                   let img = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self.artworkCache[key] = img
                        if self.title == title || self.lastTrackKey == key {
                            self.albumArt = img
                        }
                    }
                    return
                }
            }

            // 2. Spotify native artwork url
            if let spotifyUrlStr = self.findSpotifyArtworkUrl(), let url = URL(string: spotifyUrlStr) {
                if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self.artworkCache[key] = img
                        if self.title == title || self.lastTrackKey == key {
                            self.albumArt = img
                        }
                    }
                    return
                }
            }

            // 3. iTunes Store API search
            let cleanTitle = title
                .replacingOccurrences(of: #"\s*[\(\[][^()\[\]]*(?:video|audio|lyrics?|visualizer|official|music|4k|hd)[^()\[\]]*[\)\]]"#,
                                      with: "",
                                      options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let query = "\(cleanTitle) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }

            var comp = URLComponents(string: "https://itunes.apple.com/search")
            comp?.queryItems = [
                URLQueryItem(name: "term", value: query),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let searchURL = comp?.url else { return }

            URLSession.shared.dataTask(with: searchURL) { [weak self] data, _, _ in
                guard let self else { return }
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   var artUrlStr = first["artworkUrl100"] as? String {

                    artUrlStr = artUrlStr.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
                    if let artUrl = URL(string: artUrlStr),
                       let imgData = try? Data(contentsOf: artUrl),
                       let img = NSImage(data: imgData) {
                        DispatchQueue.main.async {
                            self.artworkCache[key] = img
                            if self.title == title || self.lastTrackKey == key {
                                self.albumArt = img
                            }
                        }
                        return
                    }
                }

                // 4. Deezer API Fallback
                self.fetchDeezerArtwork(query: query, titleKey: title, cacheKey: key)
            }.resume()
        }
    }

    private func fetchDeezerArtwork(query: String, titleKey: String, cacheKey: String) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=1") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArr = json["data"] as? [[String: Any]],
                  let first = dataArr.first,
                  let album = first["album"] as? [String: Any],
                  let coverUrlStr = (album["cover_xl"] as? String) ?? (album["cover_big"] as? String) ?? (album["cover_medium"] as? String),
                  let coverUrl = URL(string: coverUrlStr),
                  let imgData = try? Data(contentsOf: coverUrl),
                  let img = NSImage(data: imgData) else { return }

            DispatchQueue.main.async {
                self.artworkCache[cacheKey] = img
                if self.title == titleKey || self.lastTrackKey == cacheKey {
                    self.albumArt = img
                }
            }
        }.resume()
    }

    private func findActiveYouTubeVideoId() -> String? {
        let script = """
        tell application "System Events"
            set runningBrowsers to {}
            if exists (first process whose name is "Brave Browser") then copy "Brave Browser" to end of runningBrowsers
            if exists (first process whose name is "Google Chrome") then copy "Google Chrome" to end of runningBrowsers
            if exists (first process whose name is "Arc") then copy "Arc" to end of runningBrowsers
            if exists (first process whose name is "Safari") then copy "Safari" to end of runningBrowsers
            if exists (first process whose name is "Microsoft Edge") then copy "Microsoft Edge" to end of runningBrowsers
        end tell

        repeat with b in runningBrowsers
            set appName to b as text
            if appName is "Safari" then
                tell application "Safari"
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "music.youtube.com/watch" then return u
                        end repeat
                    end repeat
                end tell
            else if appName is "Brave Browser" then
                tell application "Brave Browser"
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "music.youtube.com/watch" then return u
                        end repeat
                    end repeat
                end tell
            else if appName is "Google Chrome" then
                tell application "Google Chrome"
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "music.youtube.com/watch" then return u
                        end repeat
                    end repeat
                end tell
            else if appName is "Arc" then
                tell application "Arc"
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "music.youtube.com/watch" then return u
                        end repeat
                    end repeat
                end tell
            else if appName is "Microsoft Edge" then
                tell application "Microsoft Edge"
                    repeat with w in windows
                        repeat with t in tabs of w
                            set u to URL of t
                            if u contains "youtube.com/watch" or u contains "music.youtube.com/watch" then return u
                        end repeat
                    end repeat
                end tell
            end if
        end repeat
        return ""
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            let urlString = output.stringValue ?? ""
            if !urlString.isEmpty {
                return extractYouTubeVideoId(from: urlString)
            }
        }
        return nil
    }

    private func extractYouTubeVideoId(from urlString: String) -> String? {
        let pattern = #"(?:v=|\/v\/|youtu\.be\/|\/embed\/|\/shorts\/)([a-zA-Z0-9_-]{11})"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let range = Range(match.range(at: 1), in: urlString) {
            return String(urlString[range])
        }
        return nil
    }

    private func findSpotifyArtworkUrl() -> String? {
        let script = """
        tell application "System Events"
            if exists (first process whose name is "Spotify") then
                try
                    tell application "Spotify" to return artwork url of current track
                end try
            end if
            return ""
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            let str = output.stringValue ?? ""
            if str.hasPrefix("http") { return str }
        }
        return nil
    }

    // MARK: – Commands & Playback Controls
    func playPause() {
        if appName.localizedCaseInsensitiveContains("spotify") {
            NSAppleScript(source: "tell application \"Spotify\" to playpause")?.executeAndReturnError(nil)
        } else if appName.localizedCaseInsensitiveContains("apple music") || appName.caseInsensitiveCompare("Music") == .orderedSame {
            NSAppleScript(source: "tell application \"Music\" to playpause")?.executeAndReturnError(nil)
        } else {
            _ = mrSendCmd?(2, nil) // kMRTogglePlayPause
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    func nextTrack() {
        if appName.localizedCaseInsensitiveContains("spotify") {
            NSAppleScript(source: "tell application \"Spotify\" to next track")?.executeAndReturnError(nil)
        } else if appName.localizedCaseInsensitiveContains("apple music") || appName.caseInsensitiveCompare("Music") == .orderedSame {
            NSAppleScript(source: "tell application \"Music\" to next track")?.executeAndReturnError(nil)
        } else {
            _ = mrSendCmd?(4, nil) // kMRNextTrack
            triggerBrowserMediaAction(action: "next")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    func prevTrack() {
        if appName.localizedCaseInsensitiveContains("spotify") {
            NSAppleScript(source: "tell application \"Spotify\" to previous track")?.executeAndReturnError(nil)
        } else if appName.localizedCaseInsensitiveContains("apple music") || appName.caseInsensitiveCompare("Music") == .orderedSame {
            NSAppleScript(source: "tell application \"Music\" to previous track")?.executeAndReturnError(nil)
        } else {
            _ = mrSendCmd?(5, nil) // kMRPreviousTrack
            triggerBrowserMediaAction(action: "prev")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    private func triggerBrowserMediaAction(action: String) {
        let js = action == "next"
            ? "document.querySelector('.next-button, .ytp-next-button')?.click()"
            : "document.querySelector('.previous-button, .ytp-prev-button')?.click()"

        let script = """
        tell application "System Events"
            set runningBrowsers to {}
            if exists (first process whose name is "Brave Browser") then copy "Brave Browser" to end of runningBrowsers
            if exists (first process whose name is "Google Chrome") then copy "Google Chrome" to end of runningBrowsers
            if exists (first process whose name is "Arc") then copy "Arc" to end of runningBrowsers
            if exists (first process whose name is "Safari") then copy "Safari" to end of runningBrowsers
        end tell

        repeat with b in runningBrowsers
            set appName to b as text
            try
                if appName is "Safari" then
                    tell application "Safari"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "youtube.com" or URL of t contains "music.youtube.com" then
                                    tell t to do JavaScript "\(js)"
                                    return
                                end if
                            end repeat
                        end repeat
                    end tell
                else if appName is "Brave Browser" then
                    tell application "Brave Browser"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "youtube.com" or URL of t contains "music.youtube.com" then
                                    tell t to execute javascript "\(js)"
                                    return
                                end if
                            end repeat
                        end repeat
                    end tell
                else if appName is "Google Chrome" then
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "youtube.com" or URL of t contains "music.youtube.com" then
                                    tell t to execute javascript "\(js)"
                                    return
                                end if
                            end repeat
                        end repeat
                    end tell
                else if appName is "Arc" then
                    tell application "Arc"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if URL of t contains "youtube.com" or URL of t contains "music.youtube.com" then
                                    tell t to execute javascript "\(js)"
                                    return
                                end if
                            end repeat
                        end repeat
                    end tell
                end if
            end try
        end repeat
        """
        DispatchQueue.global(qos: .userInitiated).async {
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }
}
