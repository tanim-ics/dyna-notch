import AppKit
import Combine
import Darwin
import Foundation
import os
import DynaNotchCore

/// Now Playing state for the island.
///
/// Primary engine: `Adapter/MediaRemoteAdapter.m` (built as `libMediaRemoteAdapter.dylib`) loaded into the
/// Apple-signed `/usr/bin/perl`, which is still entitled to read MediaRemote on macOS 15.4+. The adapter writes
/// one JSON object per line on stdout and reads commands (`toggle`, `next`, `prev`, `seek <s>`, `refresh`) on stdin.
///
/// Fallback engine (adapter missing or crashing repeatedly): AppleScript polling of Spotify / Music, only when
/// those apps are already running (never launches them).
///
/// All published state is mutated on the main queue only.
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    @Published private(set) var snapshot: NowPlayingSnapshot = .empty
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: NSColor = .white
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var appName: String = ""
    @Published private(set) var source: NowPlayingSource = .none

    /// Fires (on main) whenever a new, non-empty track key appears.
    let trackChanged = PassthroughSubject<NowPlayingSnapshot, Never>()

    // MARK: Constants

    private static let perlPath = "/usr/bin/perl"
    private static let perlScript = #"use strict; use warnings; use DynaLoader; my $p = shift @ARGV; my $h = DynaLoader::dl_load_file($p, 0) or die "dl_load_file failed: " . DynaLoader::dl_error(); my $s = DynaLoader::dl_find_symbol($h, "dn_run") or die "dn_run missing"; my $f = DynaLoader::dl_install_xsub("main::dn_run", $s); &$f();"#
    private static let spotifyID = "com.spotify.client"
    private static let musicID = "com.apple.Music"
    private static let spotifyScript = "tell application \"Spotify\" to return {player state as text, player position, name of current track, artist of current track, album of current track, (duration of current track) / 1000, artwork url of current track}"
    private static let musicScript = "tell application \"Music\" to return {player state as text, player position, name of current track, artist of current track, album of current track, duration of current track}"
    private static let maxRestarts = 5
    private static let restartWindow: TimeInterval = 600
    private static let artworkLookupDelay: TimeInterval = 1.5
    private static let maxLineBuffer = 64 * 1024 * 1024

    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "nowplaying")
    private var log: Logger { NowPlayingService.logger }

    // MARK: Adapter state (main queue unless noted)

    private var started = false
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var generation = 0
    private var restartTimes: [Date] = []
    private var restartWork: DispatchWorkItem?
    private var adapterFatal = false

    private let ioQueue = DispatchQueue(label: "com.tanim.dynanotch.nowplaying.io", qos: .utility)
    private let writeQueue = DispatchQueue(label: "com.tanim.dynanotch.nowplaying.write", qos: .userInitiated)
    // ioQueue only
    private var lineBuffer = Data()
    private var scanOffset = 0
    private var ioGeneration = -1

    // MARK: AppleScript state (main queue)

    private let scriptQueue = DispatchQueue(label: "com.tanim.dynanotch.nowplaying.applescript", qos: .utility)
    private var pollCancellable: AnyCancellable?
    private var pollInFlight = false
    private var lastRequestedArtworkURL: String?

    private struct ScriptResult {
        var snapshot: NowPlayingSnapshot
        var artworkURL: String?
    }

    // MARK: Track / artwork bookkeeping (main queue)

    private var lastTrackKey = ""
    private var artworkTrackKey = ""
    private var currentArtworkIdentifier: String?
    private var lookupWork: DispatchWorkItem?
    private var iconBundleIdentifier: String?

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        adapterFatal = false
        // Writing to the adapter's stdin after it died must not kill the app.
        signal(SIGPIPE, SIG_IGN)

        if let path = NowPlayingService.adapterPath(),
           FileManager.default.isExecutableFile(atPath: NowPlayingService.perlPath) {
            launchAdapter(dylibPath: path)
        } else {
            log.error("MediaRemote adapter unavailable, using AppleScript fallback")
            startAppleScript()
        }
    }

    func stop() {
        guard started else { return }
        started = false
        generation += 1
        restartWork?.cancel()
        restartWork = nil
        lookupWork?.cancel()
        lookupWork = nil
        terminateAdapter()
        pollCancellable?.cancel()
        pollCancellable = nil
        pollInFlight = false
        source = .none
        applyEmpty()
    }

    // MARK: Controls

    func togglePlayPause() {
        if sendCommand("toggle") {
            // routed to adapter
        } else if source == .appleScript {
            runAppleScriptControl("playpause")
        } else {
            return
        }
        optimisticToggle()
    }

    func next() {
        if sendCommand("next") { return }
        if source == .appleScript { runAppleScriptControl("next track") }
    }

    func previous() {
        if sendCommand("prev") { return }
        if source == .appleScript { runAppleScriptControl("previous track") }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        var target = max(0, seconds)
        if snapshot.duration > 0 { target = min(target, snapshot.duration) }
        if sendCommand("seek \(target)") {
            // routed to adapter
        } else if source == .appleScript {
            runAppleScriptControl("set player position to \(target)")
        } else {
            return
        }
        guard !snapshot.isEmpty else { return }
        var s = snapshot
        s.elapsed = target
        s.timestamp = Date()
        snapshot = s
    }

    private func optimisticToggle() {
        guard !snapshot.isEmpty else { return }
        let now = Date()
        var s = snapshot
        s.elapsed = s.elapsed(at: now)
        s.timestamp = now
        s.isPlaying.toggle()
        if s.isPlaying {
            if s.playbackRate <= 0 { s.playbackRate = 1 }
        } else {
            s.playbackRate = 0
        }
        snapshot = s
    }

    // MARK: Adapter process

    private static func adapterPath() -> String? {
        let fm = FileManager.default
        if let url = Bundle.main.url(forResource: "libMediaRemoteAdapter", withExtension: "dylib"),
           fm.fileExists(atPath: url.path) {
            return url.path
        }
        if let exe = Bundle.main.executableURL {
            let dir = exe.deletingLastPathComponent()
            let resources = dir.appendingPathComponent("../Resources/libMediaRemoteAdapter.dylib").standardizedFileURL
            if fm.fileExists(atPath: resources.path) { return resources.path }
            let sibling = dir.appendingPathComponent("libMediaRemoteAdapter.dylib")
            if fm.fileExists(atPath: sibling.path) { return sibling.path }
        }
        return nil
    }

    private func launchAdapter(dylibPath: String) {
        generation += 1
        let gen = generation

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: NowPlayingService.perlPath)
        proc.arguments = ["-e", NowPlayingService.perlScript, dylibPath]

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let self = self else { return }
            self.ioQueue.async { self.consume(data, generation: gen) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data.prefix(2000), as: UTF8.self)
            NowPlayingService.logger.debug("adapter stderr: \(text, privacy: .public)")
        }
        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async {
                self?.adapterTerminated(generation: gen, status: status)
            }
        }

        do {
            try proc.run()
            process = proc
            stdinHandle = inPipe.fileHandleForWriting
            log.info("MediaRemote adapter launched (pid \(proc.processIdentifier))")
        } catch {
            log.error("failed to launch adapter: \(error.localizedDescription, privacy: .public)")
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            proc.terminationHandler = nil
            adapterTerminated(generation: gen, status: -1)
        }
    }

    private func terminateAdapter() {
        guard let proc = process else {
            stdinHandle = nil
            return
        }
        proc.terminationHandler = nil
        if let out = proc.standardOutput as? Pipe { out.fileHandleForReading.readabilityHandler = nil }
        if let err = proc.standardError as? Pipe { err.fileHandleForReading.readabilityHandler = nil }
        if let handle = stdinHandle {
            writeQueue.async { try? handle.close() }
        }
        if proc.isRunning { proc.terminate() }
        process = nil
        stdinHandle = nil
    }

    private func adapterTerminated(generation gen: Int, status: Int32) {
        guard gen == generation, started else { return }
        log.error("MediaRemote adapter exited with status \(status)")
        if let proc = process {
            if let out = proc.standardOutput as? Pipe { out.fileHandleForReading.readabilityHandler = nil }
            if let err = proc.standardError as? Pipe { err.fileHandleForReading.readabilityHandler = nil }
        }
        process = nil
        stdinHandle = nil
        if source == .mediaRemote { source = .none }

        if adapterFatal {
            log.error("MediaRemote unusable, switching to AppleScript fallback")
            startAppleScript()
            return
        }

        let now = Date()
        restartTimes = restartTimes.filter { now.timeIntervalSince($0) < NowPlayingService.restartWindow }
        if restartTimes.count >= NowPlayingService.maxRestarts {
            log.error("adapter restarted too often, switching to AppleScript fallback")
            startAppleScript()
            return
        }
        let delay = pow(2.0, Double(restartTimes.count))   // 1, 2, 4, 8, 16 s
        restartTimes.append(now)

        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.started, self.process == nil, self.source != .appleScript else { return }
            if let path = NowPlayingService.adapterPath() {
                self.launchAdapter(dylibPath: path)
            } else {
                self.startAppleScript()
            }
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Sends one command line to the adapter. Returns false when the adapter is not running.
    @discardableResult
    private func sendCommand(_ command: String) -> Bool {
        guard let proc = process, proc.isRunning, let handle = stdinHandle else { return false }
        guard let data = (command + "\n").data(using: .utf8) else { return false }
        writeQueue.async {
            do {
                try handle.write(contentsOf: data)
            } catch {
                NowPlayingService.logger.error("adapter write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }

    // ioQueue only
    private func consume(_ data: Data, generation gen: Int) {
        if gen != ioGeneration {
            ioGeneration = gen
            lineBuffer = Data()
            scanOffset = 0
        }
        lineBuffer.append(data)
        if lineBuffer.count > NowPlayingService.maxLineBuffer {
            NowPlayingService.logger.error("adapter line buffer overflow, dropping data")
            lineBuffer = Data()
            scanOffset = 0
            return
        }
        while true {
            let searchStart = lineBuffer.startIndex + scanOffset
            guard let newline = lineBuffer[searchStart...].firstIndex(of: 0x0A) else {
                scanOffset = lineBuffer.count
                return
            }
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newline)
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            scanOffset = 0
            handleLine(lineData, generation: gen)
        }
    }

    // ioQueue only: parse + decode artwork off the main thread.
    private func handleLine(_ lineData: Data, generation gen: Int) {
        guard !lineData.isEmpty else { return }
        let line = String(decoding: lineData, as: UTF8.self)
        let message = AdapterParser.parse(line: line)
        var image: NSImage?
        var accent: NSColor?
        if case .nowPlaying(let snap) = message, let art = snap.artworkData, !art.isEmpty, let img = NSImage(data: art) {
            image = img
            accent = img.dominantAccentColor()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.started, gen == self.generation else { return }
            self.handle(message, decodedArtwork: image, accent: accent)
        }
    }

    private func handle(_ message: AdapterMessage, decodedArtwork: NSImage?, accent: NSColor?) {
        switch message {
        case .ready:
            log.info("MediaRemote adapter ready")
            source = .mediaRemote
            sendCommand("refresh")
        case .nowPlaying(let snap):
            if source != .mediaRemote { source = .mediaRemote }
            if snap.isEmpty {
                applyEmpty()
            } else {
                apply(snap, decodedArtwork: decodedArtwork, accent: accent)
            }
        case .empty:
            if source != .mediaRemote { source = .mediaRemote }
            applyEmpty()
        case .error(let text):
            log.error("adapter error: \(text, privacy: .public)")
            let lower = text.lowercased()
            if lower.contains("unavailable") || lower.contains("missing") {
                adapterFatal = true
            }
        case .unknown:
            break
        }
    }

    // MARK: Snapshot handling (main)

    private func apply(_ incoming: NowPlayingSnapshot, decodedArtwork: NSImage?, accent: NSColor?) {
        var new = incoming
        new.artworkData = nil   // the decoded image lives in `artwork`
        let key = new.trackKey
        let isNewTrack = key != lastTrackKey

        if let img = decodedArtwork {
            setArtwork(img, accent: accent ?? img.dominantAccentColor(), trackKey: key, identifier: incoming.artworkIdentifier)
        } else if artwork != nil {
            let sameTrack = key == artworkTrackKey
            let sameIdentifier = incoming.artworkIdentifier != nil && incoming.artworkIdentifier == currentArtworkIdentifier
            if sameTrack {
                // keep
            } else if sameIdentifier {
                artworkTrackKey = key
            } else {
                clearArtwork()
            }
        }

        snapshot = new
        updateAppInfo(bundleIdentifier: new.bundleIdentifier)

        if isNewTrack {
            lastTrackKey = key
            trackChanged.send(new)
            scheduleArtworkLookup(for: new)
        }
    }

    private func applyEmpty() {
        lookupWork?.cancel()
        lookupWork = nil
        snapshot = .empty
        clearArtwork()
        lastTrackKey = ""
        iconBundleIdentifier = nil
        if appIcon != nil { appIcon = nil }
        if !appName.isEmpty { appName = "" }
    }

    private func setArtwork(_ image: NSImage, accent: NSColor, trackKey: String, identifier: String?) {
        artwork = image
        accentColor = accent
        artworkTrackKey = trackKey
        currentArtworkIdentifier = identifier
    }

    private func clearArtwork() {
        if artwork != nil { artwork = nil }
        accentColor = .white
        artworkTrackKey = ""
        currentArtworkIdentifier = nil
    }

    private func scheduleArtworkLookup(for snap: NowPlayingSnapshot) {
        lookupWork?.cancel()
        lookupWork = nil
        guard !snap.isEmpty else { return }
        let key = snap.trackKey
        let title = snap.title
        let artist = snap.artist
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.snapshot.trackKey == key else { return }
            if self.artwork != nil && self.artworkTrackKey == key { return }
            ArtworkLookup.shared.lookup(title: title, artist: artist) { [weak self] image in
                guard let self = self, let image = image, self.snapshot.trackKey == key else { return }
                if self.artwork != nil && self.artworkTrackKey == key { return }
                self.setArtwork(image, accent: image.dominantAccentColor(), trackKey: key, identifier: nil)
            }
        }
        lookupWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NowPlayingService.artworkLookupDelay, execute: work)
    }

    private func updateAppInfo(bundleIdentifier: String?) {
        guard bundleIdentifier != iconBundleIdentifier else { return }
        iconBundleIdentifier = bundleIdentifier
        guard let id = bundleIdentifier, !id.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            appIcon = nil
            appName = ""
            return
        }
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        appName = name
    }

    // MARK: AppleScript fallback

    private func startAppleScript() {
        guard started else { return }
        restartWork?.cancel()
        restartWork = nil
        terminateAdapter()
        source = .appleScript
        guard pollCancellable == nil else { return }
        pollCancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pollAppleScript() }
        pollAppleScript()
    }

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    private func pollAppleScript() {
        guard started, source == .appleScript, !pollInFlight else { return }
        let spotifyRunning = NowPlayingService.isRunning(NowPlayingService.spotifyID)
        let musicRunning = NowPlayingService.isRunning(NowPlayingService.musicID)
        guard spotifyRunning || musicRunning else {
            if !snapshot.isEmpty { applyEmpty() }
            return
        }
        pollInFlight = true
        scriptQueue.async { [weak self] in
            var result: ScriptResult?
            if spotifyRunning {
                result = NowPlayingService.querySpotify()
            }
            if musicRunning, result == nil || result?.snapshot.isPlaying == false {
                if let music = NowPlayingService.queryMusic(), result == nil || music.snapshot.isPlaying {
                    result = music
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pollInFlight = false
                guard self.started, self.source == .appleScript else { return }
                if let r = result {
                    self.applyScriptResult(r)
                } else if !self.snapshot.isEmpty {
                    self.applyEmpty()
                }
            }
        }
    }

    private func applyScriptResult(_ result: ScriptResult) {
        apply(result.snapshot, decodedArtwork: nil, accent: nil)

        guard let urlString = result.artworkURL, !urlString.isEmpty,
              urlString != lastRequestedArtworkURL,
              let url = URL(string: urlString) else { return }
        if artwork != nil && currentArtworkIdentifier == urlString { return }
        lastRequestedArtworkURL = urlString
        let key = result.snapshot.trackKey
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            var image: NSImage?
            var accent: NSColor?
            if let data = data, let img = NSImage(data: data) {
                image = img
                accent = img.dominantAccentColor()
            }
            DispatchQueue.main.async {
                guard let self = self, let image = image, self.snapshot.trackKey == key else { return }
                self.setArtwork(image, accent: accent ?? .white, trackKey: key, identifier: urlString)
            }
        }.resume()
    }

    private func runAppleScriptControl(_ command: String) {
        let appName: String
        let bundle: String
        if snapshot.bundleIdentifier == NowPlayingService.musicID {
            appName = "Music"
            bundle = NowPlayingService.musicID
        } else if snapshot.bundleIdentifier == NowPlayingService.spotifyID {
            appName = "Spotify"
            bundle = NowPlayingService.spotifyID
        } else {
            return
        }
        guard NowPlayingService.isRunning(bundle) else { return }
        let scriptSource = "tell application \"\(appName)\" to \(command)"
        scriptQueue.async { [weak self] in
            _ = NowPlayingService.runScript(scriptSource)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.pollAppleScript()
            }
        }
    }

    // scriptQueue only
    private static func runScript(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo = errorInfo {
            let text = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown error"
            logger.debug("AppleScript failed: \(text, privacy: .public)")
            return nil
        }
        return result
    }

    private static func string(_ descriptor: NSAppleEventDescriptor?) -> String {
        descriptor?.stringValue ?? ""
    }

    private static func number(_ descriptor: NSAppleEventDescriptor?) -> Double {
        let text = (descriptor?.stringValue ?? "").replacingOccurrences(of: ",", with: ".")
        let value = Double(text.trimmingCharacters(in: .whitespaces)) ?? 0
        return value.isFinite ? value : 0
    }

    // scriptQueue only
    private static func querySpotify() -> ScriptResult? {
        guard let list = runScript(spotifyScript), list.numberOfItems >= 6 else { return nil }
        let state = string(list.atIndex(1)).lowercased()
        guard state != "stopped" else { return nil }
        let title = string(list.atIndex(3))
        guard !title.isEmpty else { return nil }
        let playing = state == "playing"
        let artworkURL: String? = list.numberOfItems >= 7 ? list.atIndex(7)?.stringValue : nil
        let snap = NowPlayingSnapshot(
            title: title,
            artist: string(list.atIndex(4)),
            album: string(list.atIndex(5)),
            duration: number(list.atIndex(6)),
            elapsed: number(list.atIndex(2)),
            timestamp: Date(),
            playbackRate: playing ? 1 : 0,
            isPlaying: playing,
            bundleIdentifier: spotifyID,
            artworkIdentifier: artworkURL,
            artworkData: nil
        )
        return ScriptResult(snapshot: snap, artworkURL: artworkURL)
    }

    // scriptQueue only
    private static func queryMusic() -> ScriptResult? {
        guard let list = runScript(musicScript), list.numberOfItems >= 6 else { return nil }
        let state = string(list.atIndex(1)).lowercased()
        guard state != "stopped" else { return nil }
        let title = string(list.atIndex(3))
        guard !title.isEmpty else { return nil }
        let playing = state == "playing"
        let snap = NowPlayingSnapshot(
            title: title,
            artist: string(list.atIndex(4)),
            album: string(list.atIndex(5)),
            duration: number(list.atIndex(6)),
            elapsed: number(list.atIndex(2)),
            timestamp: Date(),
            playbackRate: playing ? 1 : 0,
            isPlaying: playing,
            bundleIdentifier: musicID,
            artworkIdentifier: nil,
            artworkData: nil
        )
        return ScriptResult(snapshot: snap, artworkURL: nil)
    }
}
