import Foundation
import AppKit
import Combine
import CoreAudio
import ApplicationServices

class MusicViewModel: ObservableObject {
    @Published var title:       String   = ""
    @Published var artist:      String   = ""
    @Published var album:       String   = ""
    @Published var albumArt:    NSImage? = nil
    @Published var isPlaying:   Bool     = false
    @Published var progress:    Double   = 0
    @Published var duration:    Double   = 1
    @Published var appName:     String   = ""
    @Published var installedMusicApps: [String] = []

    // MediaRemote bindings
    private typealias MRGetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping (NSDictionary) -> Void) -> Void
    private typealias MRSendCommandFn       = @convention(c) (UInt32, NSDictionary?) -> Bool
    private typealias MRRegisterForNotifsFn = @convention(c) (DispatchQueue) -> Void
    private typealias MRGetNowPlayingPIDFn  = @convention(c) (DispatchQueue, @escaping (pid_t) -> Void) -> Void
    private typealias MRIsPlayingFn         = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    private var mrGetInfo:   MRGetNowPlayingInfoFn?
    private var mrSendCmd:   MRSendCommandFn?
    private var mrGetPID:    MRGetNowPlayingPIDFn?
    private var mrIsPlaying: MRIsPlayingFn?

    // Active AX element handles for direct control
    private var activePlayPauseEl: AXUIElement?
    private var activeNextEl:      AXUIElement?
    private var activePrevEl:      AXUIElement?

    private var progressTimer: AnyCancellable?
    private var pollTimer:     AnyCancellable?
    private var lastTickTime:  Date   = Date()
    private var isAudioOutputRunning: Bool = false

    private var lastTrackKey: String = ""
    private var artworkCache: [String: NSImage] = [:]

    static let shared = MusicViewModel()

    private init() {
        refreshInstalledApps()
        loadMediaRemote()
        setupAudioDeviceObserver()
        startTimers()
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        appendLog("[DynaNotch] init: AXIsProcessTrusted=\(isTrusted)\n")
        
        // Immediate first scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scanActiveMedia()
        }
    }

    // MARK: – Installed Music Apps Detection
    func refreshInstalledApps() {
        var detected: [String] = []
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil {
            detected.append("Apple Music")
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil {
            detected.append("Spotify")
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.brave.Browser.app.cinhimbnkkaeohfgghhklpknlkffjgod") != nil ||
           NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod") != nil {
            detected.append("YouTube Music")
        }
        self.installedMusicApps = detected
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
            dist.addObserver(self, selector: #selector(handleNotificationTrigger),
                             name: NSNotification.Name(n), object: nil)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTestMusicPreview),
            name: .testMusicPreview,
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
            DispatchQueue.main.async { vm.scanActiveMedia() }
        }
        for name in names {
            CFNotificationCenterAddObserver(center, rawSelf, cb,
                name as CFString, nil, .deliverImmediately)
        }
    }

    @objc private func handleNotificationTrigger() {
        scanActiveMedia()
    }

    // MARK: – CoreAudio Monitoring
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
            if running && !self.title.isEmpty && !self.isPlaying {
                self.isPlaying = true
            } else if !running && !self.title.isEmpty && self.isPlaying && self.appName != "YouTube Music" {
                self.isPlaying = false
            }
        }
    }

    // MARK: – Timers
    private func startTimers() {
        // High frequency 0.25s ticker for smooth progress bar
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

        // Periodic 1.2s scanner to synchronize active playing state
        pollTimer = Timer.publish(every: 1.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.scanActiveMedia()
            }
    }

    // MARK: – Multi-Source Active Media Scanner
    @objc func scanActiveMedia() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let startLog = "[DynaNotch] scanActiveMedia started. currentTitle='\(self.title)'\n"
            if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/dynanotch.log")) {
                h.seekToEndOfFile(); h.write(startLog.data(using: .utf8)!); h.closeFile()
            } else {
                try? startLog.write(to: URL(fileURLWithPath: "/tmp/dynanotch.log"), atomically: true, encoding: .utf8)
            }

            // 1. Browser Tab Inspector (Brave/Chrome/Safari - zero prompts, instant)
            if self.detectBrowserAudio() {
                return
            }

            // 2. YouTube Music PWA (AX UI)
            if self.detectYouTubeMusicPWA() {
                return
            }

            // 3. Spotify (Only if running)
            if self.detectSpotifyIfRunning() {
                return
            }

            // 4. Apple Music (Only if running)
            if self.detectAppleMusicIfRunning() {
                return
            }

            // 5. MediaRemote Framework
            if self.detectMediaRemote() {
                return
            }

            // If audio output is stopped and no active player, mark paused
            DispatchQueue.main.async {
                if !self.isAudioOutputRunning && self.isPlaying {
                    self.isPlaying = false
                }
            }
        }
    }

    private func appendLog(_ text: String) {
        if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/dynanotch.log")) {
            h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); h.closeFile()
        } else {
            try? text.write(to: URL(fileURLWithPath: "/tmp/dynanotch.log"), atomically: true, encoding: .utf8)
        }
    }

    // MARK: – Engine 1: YouTube Music PWA
    private func detectYouTubeMusicPWA() -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            let bid = (app.bundleIdentifier ?? "").lowercased()
            let name = (app.localizedName ?? "").lowercased()
            return bid.contains("cinhimbnkkaeohfgghhklpknlkffjgod") ||
                   bid.contains("youtube") ||
                   name.contains("youtube music")
        }
        appendLog("[DynaNotch] detectYTM: apps=\(apps.count), first=\(apps.first?.localizedName ?? "nil")\n")
        guard let app = apps.first(where: { !($0.bundleIdentifier ?? "").contains("xpc") }) ?? apps.first else {
            appendLog("[DynaNotch] detectYTM: no suitable app found\n")
            return false
        }

        // 1. Direct window title inspection
        var winTitleTrack = ""
        if let winList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for w in winList {
                let owner = w[kCGWindowOwnerName as String] as? String ?? ""
                let title = w[kCGWindowName as String] as? String ?? ""
                if (owner.contains("YouTube Music") || owner.contains("Brave") || owner.contains("Chrome")) &&
                   (title.contains("YouTube Music - ") || title.contains(" | YouTube Music")) {
                    var clean = title.replacingOccurrences(of: "YouTube Music - ", with: "")
                                     .replacingOccurrences(of: " | YouTube Music", with: "")
                                     .replacingOccurrences(of: " - Audio playing", with: "")
                                     .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        winTitleTrack = clean
                        break
                    }
                }
            }
        }
        appendLog("[DynaNotch] detectYTM: winTitleTrack='\(winTitleTrack)'\n")

        // 2. AX UI inspection for rich metadata & native button controls
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        var windowsRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        let windows = (windowsRef as? [AXUIElement]) ?? []
        appendLog("[DynaNotch] detectYTM: windows=\(windows.count)\n")

        for win in windows {
            var items: [(role: String, val: String, ttl: String, desc: String, el: AXUIElement)] = []
            func traverse(el: AXUIElement, depth: Int) {
                if depth > 15 { return }
                var roleRef: CFTypeRef?
                var valRef: CFTypeRef?
                var descRef: CFTypeRef?
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
                AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valRef)
                AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
                AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)

                let role = roleRef as? String ?? ""
                let val = valRef as? String ?? ""
                let desc = descRef as? String ?? ""
                let ttl = titleRef as? String ?? ""
                if !val.isEmpty || !desc.isEmpty || !ttl.isEmpty {
                    items.append((role, val, ttl, desc, el))
                }
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for child in children {
                        traverse(el: child, depth: depth + 1)
                    }
                }
            }
            traverse(el: win, depth: 0)

            var scannedTitle = ""
            var scannedArtist = ""
            var scannedAlbum = ""
            var scannedProgress: Double = 0
            var scannedDuration: Double = 1
            var scannedPlaying: Bool = false
            var playPauseBtn: AXUIElement?
            var nextBtn: AXUIElement?
            var prevBtn: AXUIElement?

            for item in items {
                let name = !item.desc.isEmpty ? item.desc : item.ttl
                if item.role == "AXGroup" || item.role == "AXButton" {
                    if name == "Pause" {
                        scannedPlaying = true
                        playPauseBtn = item.el
                    } else if name == "Play" && playPauseBtn == nil {
                        scannedPlaying = false
                        playPauseBtn = item.el
                    } else if name == "Next" {
                        nextBtn = item.el
                    } else if name == "Previous" {
                        prevBtn = item.el
                    }
                }

                // Parse "7:37 / 11:41"
                if item.role == "AXStaticText" && item.val.contains(" / ") {
                    let parts = item.val.components(separatedBy: " / ")
                    if parts.count == 2 {
                        scannedProgress = parseDuration(parts[0].trimmingCharacters(in: .whitespaces))
                        scannedDuration = parseDuration(parts[1].trimmingCharacters(in: .whitespaces))
                    }
                }

                // Track title
                if item.role == "AXHeading" && !item.ttl.isEmpty && scannedTitle.isEmpty {
                    scannedTitle = item.ttl
                }

                // Artist & Album group: "We Lost The Sea • Departure Songs • 2015"
                if item.ttl.contains(" • ") || item.desc.contains(" • ") {
                    let raw = !item.desc.isEmpty ? item.desc : item.ttl
                    let parts = raw.components(separatedBy: " • ")
                    if parts.count >= 2 {
                        scannedArtist = parts[0].trimmingCharacters(in: .whitespaces)
                        scannedAlbum = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            // Window title fallback if heading was missed
            if scannedTitle.isEmpty {
                if let winList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
                    for w in winList {
                        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
                        let title = w[kCGWindowName as String] as? String ?? ""
                        if owner.contains("YouTube Music") && title.contains(" - ") {
                            let clean = title.replacingOccurrences(of: "YouTube Music - ", with: "")
                                             .replacingOccurrences(of: " | YouTube Music", with: "")
                            scannedTitle = clean
                            break
                        }
                    }
                }
            }

            let effectiveTitle = !scannedTitle.isEmpty ? scannedTitle : winTitleTrack
            if !effectiveTitle.isEmpty {
                let isAudioPlaying = scannedPlaying || self.isAudioOutputRunning
                DispatchQueue.main.async {
                    self.activePlayPauseEl = playPauseBtn
                    self.activeNextEl = nextBtn
                    self.activePrevEl = prevBtn
                    self.appName = "YouTube Music"

                    let trackKey = "\(effectiveTitle)|\(scannedArtist)"
                    let isNew = (trackKey != self.lastTrackKey)
                    self.lastTrackKey = trackKey

                    self.title = effectiveTitle
                    if !scannedArtist.isEmpty { self.artist = scannedArtist }
                    if !scannedAlbum.isEmpty { self.album = scannedAlbum }
                    self.duration = max(scannedDuration, 1)
                    if abs(self.progress - scannedProgress) > 1.5 || self.progress == 0 || isNew {
                        self.progress = scannedProgress
                    }
                    self.isPlaying = isAudioPlaying
                    self.lastTickTime = Date()

                    if isNew || self.albumArt == nil {
                        self.resolveArtwork(title: effectiveTitle, artist: self.artist)
                    }
                    let endLog = "[DynaNotch] YTM detected: effectiveTitle='\(effectiveTitle)', artist='\(self.artist)', isAudioPlaying=\(isAudioPlaying)\n"
                    if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/dynanotch.log")) {
                        h.seekToEndOfFile(); h.write(endLog.data(using: .utf8)!); h.closeFile()
                    }
                }
                return true
            }
        }

        if !winTitleTrack.isEmpty {
            DispatchQueue.main.async {
                self.appName = "YouTube Music"
                let isNew = (winTitleTrack != self.title)
                self.title = winTitleTrack
                self.isPlaying = self.isAudioOutputRunning
                self.lastTickTime = Date()
                if isNew || self.albumArt == nil {
                    self.resolveArtwork(title: winTitleTrack, artist: self.artist)
                }
            }
            return true
        }
        return false
    }

    // MARK: – Engine 2: Spotify (Safe - only runs if process exists)
    private func detectSpotifyIfRunning() -> Bool {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.spotify.client"
        }
        guard isRunning else { return false }

        let script = "tell application \"Spotify\" to return {player state as text, player position, name of current track, artist of current track, (duration of current track) / 1000, artwork url of current track}"
        var err: NSDictionary?
        guard let s = NSAppleScript(source: script) else { return false }
        let res = s.executeAndReturnError(&err)
        guard let list = res.coerce(toDescriptorType: typeAEList) else { return false }

        let state   = list.atIndex(1)?.stringValue ?? ""
        let pos     = list.atIndex(2)?.doubleValue ?? 0
        let tTitle  = list.atIndex(3)?.stringValue ?? ""
        let tArtist = list.atIndex(4)?.stringValue ?? ""
        let tDur    = list.atIndex(5)?.doubleValue ?? 1
        let artUrl  = list.atIndex(6)?.stringValue ?? ""

        guard !tTitle.isEmpty else { return false }

        DispatchQueue.main.async {
            self.appName = "Spotify"
            self.activePlayPauseEl = nil
            self.activeNextEl = nil
            self.activePrevEl = nil

            let trackKey = "\(tTitle)|\(tArtist)"
            let isNew = (trackKey != self.lastTrackKey)
            self.lastTrackKey = trackKey

            self.title = tTitle
            self.artist = tArtist
            self.duration = max(tDur, 1)
            self.progress = pos
            self.isPlaying = (state == "playing")
            self.lastTickTime = Date()

            if isNew || self.albumArt == nil {
                if !artUrl.isEmpty, let url = URL(string: artUrl) {
                    self.downloadArtwork(from: url, key: trackKey)
                } else {
                    self.resolveArtwork(title: tTitle, artist: tArtist)
                }
            }
        }
        return true
    }

    // MARK: – Engine 3: Apple Music (Safe - only runs if process exists)
    private func detectAppleMusicIfRunning() -> Bool {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
        guard isRunning else { return false }

        let script = "tell application \"Music\" to return {player state as text, player position, name of current track, artist of current track, duration of current track}"
        var err: NSDictionary?
        guard let s = NSAppleScript(source: script) else { return false }
        let res = s.executeAndReturnError(&err)
        guard let list = res.coerce(toDescriptorType: typeAEList) else { return false }

        let state   = list.atIndex(1)?.stringValue ?? ""
        let pos     = list.atIndex(2)?.doubleValue ?? 0
        let tTitle  = list.atIndex(3)?.stringValue ?? ""
        let tArtist = list.atIndex(4)?.stringValue ?? ""
        let tDur    = list.atIndex(5)?.doubleValue ?? 1

        guard !tTitle.isEmpty else { return false }

        DispatchQueue.main.async {
            self.appName = "Apple Music"
            self.activePlayPauseEl = nil
            self.activeNextEl = nil
            self.activePrevEl = nil

            let trackKey = "\(tTitle)|\(tArtist)"
            let isNew = (trackKey != self.lastTrackKey)
            self.lastTrackKey = trackKey

            self.title = tTitle
            self.artist = tArtist
            self.duration = max(tDur, 1)
            self.progress = pos
            self.isPlaying = (state == "playing")
            self.lastTickTime = Date()

            if isNew || self.albumArt == nil {
                self.resolveArtwork(title: tTitle, artist: tArtist)
            }
        }
        return true
    }

    // MARK: – Engine 4: MediaRemote
    private func detectMediaRemote() -> Bool {
        guard let mrGetInfo else { return false }
        var detected = false
        let sema = DispatchSemaphore(value: 0)

        mrGetInfo(DispatchQueue.global()) { [weak self] info in
            defer { sema.signal() }
            guard let self else { return }

            var rawTitle  = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? ""
            var rawArtist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""

            guard !rawTitle.isEmpty else { return }
            detected = true

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
            let timeSince = max(0, Date().timeIntervalSince(timestamp))
            let currentElapsed = (rate > 0) ? min(baseElapsed + timeSince * rate, dur > 0 ? dur : Double.infinity) : baseElapsed

            var directArt: NSImage? = nil
            if let rawData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, !rawData.isEmpty {
                directArt = NSImage(data: rawData)
            }

            DispatchQueue.main.async {
                self.activePlayPauseEl = nil
                self.activeNextEl = nil
                self.activePrevEl = nil

                let trackKey = "\(rawTitle)|\(rawArtist)"
                let isNew = (trackKey != self.lastTrackKey)
                self.lastTrackKey = trackKey

                self.title = rawTitle
                self.artist = rawArtist
                self.duration = max(dur, 1)
                self.progress = currentElapsed
                self.isPlaying = (rate > 0) || self.isAudioOutputRunning
                self.lastTickTime = Date()

                if let img = directArt {
                    self.albumArt = img
                    self.artworkCache[trackKey] = img
                } else if isNew || self.albumArt == nil {
                    self.resolveArtwork(title: rawTitle, artist: rawArtist)
                }
            }
        }
        _ = sema.wait(timeout: .now() + 0.15)
        return detected
    }

    // MARK: – Engine 5: Browser Tab Inspector (Zero Prompts, 100% Targeted)
    private func detectBrowserAudio() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        let isBrave = runningApps.contains { $0.bundleIdentifier == "com.brave.Browser" }
        let isChrome = runningApps.contains { $0.bundleIdentifier == "com.google.Chrome" }
        let isSafari = runningApps.contains { $0.bundleIdentifier == "com.apple.Safari" }

        guard isBrave || isChrome || isSafari else {
            appendLog("[DynaNotch] detectBrowserAudio: no supported browser running\n")
            return false
        }
        appendLog("[DynaNotch] detectBrowserAudio: scanning (Brave=\(isBrave), Chrome=\(isChrome), Safari=\(isSafari))\n")

        var foundTitle = ""
        var foundUrl = ""
        var resolvedApp = "YouTube Music"

        func queryBrowser(name: String) -> (title: String, url: String)? {
            let script = """
            tell application "\(name)"
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if u contains "music.youtube.com" then
                            return (title of t & "|||" & u)
                        end if
                    end repeat
                end repeat
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if u contains "youtube.com/watch" then
                            return (title of t & "|||" & u)
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
            var err: NSDictionary?
            if let s = NSAppleScript(source: script) {
                let res = s.executeAndReturnError(&err).stringValue ?? ""
                self.appendLog("[DynaNotch] queryBrowser('\(name)') res='\(res)' err=\(String(describing: err))\n")
                if res.contains("|||") {
                    let parts = res.components(separatedBy: "|||")
                    return (parts[0], parts[1])
                }
            } else {
                self.appendLog("[DynaNotch] queryBrowser('\(name)') could not create NSAppleScript\n")
            }
            return nil
        }

        if isBrave, let info = queryBrowser(name: "Brave Browser") {
            foundTitle = info.title
            foundUrl = info.url
        } else if isChrome, let info = queryBrowser(name: "Google Chrome") {
            foundTitle = info.title
            foundUrl = info.url
        } else if isSafari, let info = queryBrowser(name: "Safari") {
            foundTitle = info.title
            foundUrl = info.url
        }

        guard !foundTitle.isEmpty else {
            appendLog("[DynaNotch] detectBrowserAudio: no music tab found\n")
            return false
        }
        appendLog("[DynaNotch] detectBrowserAudio: FOUND '\(foundTitle)' -> url: '\(foundUrl)'\n")

        var clean = foundTitle.replacingOccurrences(of: " | YouTube Music", with: "")
                              .replacingOccurrences(of: " - YouTube Music", with: "")
                              .replacingOccurrences(of: " - YouTube", with: "")
                              .replacingOccurrences(of: " - Audio playing", with: "")
                              .replacingOccurrences(of: "🔊", with: "")
                              .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty,
              clean != "YouTube Music",
              clean != "YouTube",
              clean != "New Tab" else {
            appendLog("[DynaNotch] detectBrowserAudio: title '\(clean)' is placeholder, skipping\n")
            return false
        }

        var tTitle = clean
        var tArtist = ""
        if clean.contains(" - ") {
            let parts = clean.components(separatedBy: " - ")
            tArtist = parts[0].trimmingCharacters(in: .whitespaces)
            tTitle = parts[1].trimmingCharacters(in: .whitespaces)
        }

        if foundUrl.contains("music.youtube.com") {
            resolvedApp = "YouTube Music"
        } else {
            resolvedApp = "YouTube"
        }

        DispatchQueue.main.async {
            self.appName = resolvedApp
            self.activePlayPauseEl = nil
            self.activeNextEl = nil
            self.activePrevEl = nil

            let trackKey = "\(tTitle)|\(tArtist)"
            let isNew = (trackKey != self.lastTrackKey)
            self.lastTrackKey = trackKey

            self.title = tTitle
            if !tArtist.isEmpty { self.artist = tArtist }
            self.isPlaying = self.isAudioOutputRunning
            self.lastTickTime = Date()

            if isNew || self.albumArt == nil {
                self.resolveArtwork(title: tTitle, artist: tArtist)
            }
        }
        return true
    }

    // MARK: – Artwork Resolution
    func resolveArtwork(title: String, artist: String) {
        let key = "\(title)|\(artist)"
        if let cached = artworkCache[key] {
            DispatchQueue.main.async { self.albumArt = cached }
            return
        }

        let cleanTitle = title
            .replacingOccurrences(of: #"\s*[\(\[][^()\[\]]*(?:video|audio|lyrics?|visualizer|official|music|4k|hd)[^()\[\]]*[\)\]]"#,
                                  with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let query = "\(cleanTitle) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // 1. iTunes Store API (High definition 600x600 music track search)
        var comp = URLComponents(string: "https://itunes.apple.com/search")
        comp?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let searchURL = comp?.url else { return }

        URLSession.shared.dataTask(with: searchURL) { [weak self] data, _, _ in
            guard let self else { return }
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let first = results.first {

                if let aName = first["artistName"] as? String, !aName.isEmpty {
                    DispatchQueue.main.async {
                        if self.artist.isEmpty || self.artist == "YouTube" || self.artist == "YouTube Music" {
                            self.artist = aName
                        }
                    }
                }

                if let col = first["collectionName"] as? String, !col.isEmpty {
                    DispatchQueue.main.async {
                        self.album = col
                    }
                }

                if let millis = (first["trackTimeMillis"] as? NSNumber)?.doubleValue ?? (first["trackTimeMillis"] as? Double), millis > 0 {
                    DispatchQueue.main.async {
                        if self.duration <= 1 {
                            self.duration = millis / 1000.0
                        }
                    }
                }

                if var artUrlStr = first["artworkUrl100"] as? String {
                    artUrlStr = artUrlStr.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg")
                    if let artUrl = URL(string: artUrlStr) {
                        self.downloadArtwork(from: artUrl, key: key)
                        return
                    }
                }
            }

            // 2. Fallback to Deezer API
            self.fetchDeezerArtwork(query: query, key: key)
        }.resume()
    }

    private func downloadArtwork(from url: URL, key: String) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.artworkCache[key] = img
                if "\(self.title)|\(self.artist)" == key {
                    self.albumArt = img
                }
            }
        }.resume()
    }

    private func fetchDeezerArtwork(query: String, key: String) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=1") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArr = json["data"] as? [[String: Any]],
                  let first = dataArr.first,
                  let album = first["album"] as? [String: Any],
                  let coverUrlStr = (album["cover_xl"] as? String) ?? (album["cover_big"] as? String),
                  let coverUrl = URL(string: coverUrlStr) else { return }

            self.downloadArtwork(from: coverUrl, key: key)
        }.resume()
    }

    // MARK: – Native Playback Controls (100% Reliable)
    func playPause() {
        if let el = activePlayPauseEl {
            AXUIElementPerformAction(el, kAXPressAction as CFString)
        } else if appName == "Spotify" {
            NSAppleScript(source: "tell application \"Spotify\" to playpause")?.executeAndReturnError(nil)
        } else if appName == "Apple Music" {
            NSAppleScript(source: "tell application \"Music\" to playpause")?.executeAndReturnError(nil)
        } else {
            _ = mrSendCmd?(2, nil) // kMRTogglePlayPause
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.scanActiveMedia()
        }
    }

    func nextTrack() {
        if let el = activeNextEl {
            AXUIElementPerformAction(el, kAXPressAction as CFString)
        } else if appName == "Spotify" {
            NSAppleScript(source: "tell application \"Spotify\" to next track")?.executeAndReturnError(nil)
        } else if appName == "Apple Music" {
            NSAppleScript(source: "tell application \"Music\" to next track")?.executeAndReturnError(nil)
        } else {
            _ = mrSendCmd?(4, nil) // kMRNextTrack
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.scanActiveMedia()
        }
    }

    func prevTrack() {
        if let el = activePrevEl {
            AXUIElementPerformAction(el, kAXPressAction as CFString)
        } else if appName == "Spotify" {
            NSAppleScript(source: "tell application \"Spotify\" to previous track")?.executeAndReturnError(nil)
        } else if appName == "Apple Music" {
            NSAppleScript(source: "tell application \"Music\" to previous track")?.executeAndReturnError(nil)
        } else {
            _ = mrSendCmd?(5, nil) // kMRPreviousTrack
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.scanActiveMedia()
        }
    }

    private func parseDuration(_ str: String) -> Double {
        let parts = str.components(separatedBy: ":")
        if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let s = Double(parts[1]) ?? 0
            return m * 60 + s
        } else if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let s = Double(parts[2]) ?? 0
            return h * 3600 + m * 60 + s
        }
        return 0
    }

    @objc private func handleTestMusicPreview() {
        DispatchQueue.main.async {
            self.title = "A Gallant Gentleman"
            self.artist = "We Lost The Sea"
            self.album = "Departure Songs"
            self.appName = "YouTube Music"
            self.duration = 364
            self.progress = 72
            self.isPlaying = true
            self.resolveArtwork(title: "A Gallant Gentleman", artist: "We Lost The Sea")
        }
    }
}
