import AppKit
import Combine
import Foundation
import IOBluetooth
import os
import DynaNotchCore

// Services behind the Home cards (tabs agent, CLAUDE.md §6.7).

/// tabs agent — live Claude Code / Codex sessions (log files written in the last 10 minutes).
struct CodingAgentSession: Identifiable, Equatable {
    let id: String
    let tool: String         // "Claude Code" / "Codex"
    let project: String
    let lastActivity: Date
}

final class CodingAgentsService: ObservableObject {
    static let shared = CodingAgentsService()
    @Published private(set) var sessions: [CodingAgentSession] = []

    /// A session counts as live when its log changed within this window.
    static let activeWindow: TimeInterval = 600

    private let queue = DispatchQueue(label: "com.tanim.dynanotch.codingAgents", qos: .utility)
    private var timer: AnyCancellable?
    private var isRefreshing = false

    private init() {}

    /// Idempotent: refreshes now and every 30 s.
    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        queue.async { [weak self] in
            let now = Date()
            let found = (CodingAgentsService.claudeSessions(now: now) + CodingAgentsService.codexSessions(now: now))
                .sorted { $0.lastActivity > $1.lastActivity }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false
                if found != self.sessions { self.sessions = found }
            }
        }
    }

    // MARK: Scanning

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func recentFiles(in dir: URL, suffix: String, now: Date) -> [(URL, Date)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        return names.compactMap { url in
            guard url.lastPathComponent.hasSuffix(suffix),
                  let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(date) < activeWindow else { return nil }
            return (url, date)
        }
    }

    /// ~/.claude/projects/<encoded path>/<session>.jsonl
    private static func claudeSessions(now: Date) -> [CodingAgentSession] {
        let root = home.appendingPathComponent(".claude/projects")
        guard let projects = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                          options: [.skipsHiddenFiles]) else { return [] }
        var out: [CodingAgentSession] = []
        for dir in projects {
            // A project directory's mtime changes when a session file is created; files changing update only the file.
            for (file, date) in recentFiles(in: dir, suffix: ".jsonl", now: now) {
                let cwd = cwdFromTail(file) ?? decodeProjectDir(dir.lastPathComponent)
                out.append(CodingAgentSession(id: "claude:" + file.lastPathComponent, tool: "Claude Code",
                                              project: projectName(cwd), lastActivity: date))
            }
        }
        return out
    }

    /// ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (today and yesterday).
    private static func codexSessions(now: Date) -> [CodingAgentSession] {
        let root = home.appendingPathComponent(".codex/sessions")
        var out: [CodingAgentSession] = []
        let cal = Calendar.current
        for offset in [0, -1] {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0))
            for (file, date) in recentFiles(in: dir, suffix: ".jsonl", now: now) where file.lastPathComponent.hasPrefix("rollout-") {
                let cwd = cwdFromHead(file) ?? ""
                out.append(CodingAgentSession(id: "codex:" + file.lastPathComponent, tool: "Codex",
                                              project: projectName(cwd), lastActivity: date))
            }
        }
        return out
    }

    private static func projectName(_ cwd: String) -> String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "Unknown project" : name
    }

    /// "-Users-me-Desktop-app" → "/Users/me/Desktop/app" (best effort: dashes inside names are ambiguous).
    private static func decodeProjectDir(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: "/")
    }

    private static func cwdFromTail(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let length: UInt64 = 32_768
        try? handle.seek(toOffset: size > length ? size - length : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            if let cwd = cwd(in: String(line)) { return cwd }
        }
        return nil
    }

    private static func cwdFromHead(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16_384), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(5) {
            if let cwd = cwd(in: String(line)) { return cwd }
        }
        return nil
    }

    /// `"cwd":"/path"` at the top level or inside `payload` (Codex session_meta).
    private static func cwd(in line: String) -> String? {
        guard line.contains("\"cwd\""), let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let cwd = object["cwd"] as? String, !cwd.isEmpty { return cwd }
        if let payload = object["payload"] as? [String: Any], let cwd = payload["cwd"] as? String, !cwd.isEmpty { return cwd }
        return nil
    }
}

/// tabs agent — paired Bluetooth devices with connect / disconnect (IOBluetooth).
struct PairedDevice: Identifiable, Equatable {
    let id: String           // address
    let name: String
    let isConnected: Bool
}

final class BluetoothConnectService: ObservableObject {
    static let shared = BluetoothConnectService()
    @Published private(set) var devices: [PairedDevice] = []
    /// Addresses with a connect / disconnect in flight.
    @Published private(set) var busy: Set<String> = []

    private let queue = DispatchQueue(label: "com.tanim.dynanotch.btconnect", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "bluetooth-connect")

    private init() {}

    func refresh() {
        queue.async { [weak self] in
            let list = BluetoothConnectService.readPaired()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if list != self.devices { self.devices = list }
            }
        }
    }

    func toggle(_ device: PairedDevice) {
        guard !busy.contains(device.id) else { return }
        busy.insert(device.id)
        let address = device.id
        let connect = !device.isConnected
        queue.async { [weak self] in
            var result: IOReturn = kIOReturnError
            if let bt = IOBluetoothDevice(addressString: address) {
                // Both calls block until the link is up / down (connect may take a few seconds).
                result = connect ? bt.openConnection() : bt.closeConnection()
            }
            let list = BluetoothConnectService.readPaired()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if result != kIOReturnSuccess {
                    self.logger.error("bluetooth \(connect ? "connect" : "disconnect", privacy: .public) failed: \(result)")
                }
                self.busy.remove(address)
                if list != self.devices { self.devices = list }
            }
        }
    }

    private static func readPaired() -> [PairedDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
        return paired.compactMap { device -> PairedDevice? in
            guard let address = device.addressString, !address.isEmpty else { return nil }
            let name = device.name ?? device.nameOrAddress ?? address
            return PairedDevice(id: address, name: name, isConnected: device.isConnected())
        }
        .sorted { a, b in
            if a.isConnected != b.isConnected { return a.isConnected }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
