import Combine
import Foundation
import os
import DynaNotchCore

/// Agent Island (CONTRACTS §6.14): Claude Code permission requests and session status, handed over by
/// `agent-hook.pl` through files in App Support/DynaNotch/agent/. Directory vnode sources wake us; nothing polls.
final class AgentIslandService {
    static let shared = AgentIslandService()

    /// Waiting requests, oldest first (main queue).
    @Published private(set) var requests: [AgentRequest] = []
    /// Main queue: a session's latest status line.
    let statuses = PassthroughSubject<AgentSessionStatus, Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "agent")
    private var started = false
    private var enabled = false
    private var cancellables = Set<AnyCancellable>()
    private var sources: [DispatchSourceFileSystemObject] = []
    /// While requests wait: drops those whose hook died (Ctrl-C in Claude Code) — a dead hook makes no file event.
    private var pruneTimer: AnyCancellable?
    private var lastStatusAt: [String: Date] = [:]
    private(set) var lastAnswer = "none"
    /// `dynanotch://agent/install-test` result (state.json `agent.installTest`).
    var installTest = "none"

    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["DYNANOTCH_AGENT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return AppDataStore.directory.appendingPathComponent("agent", isDirectory: true)
    }
    private var requestsDir: URL { AgentIslandService.directory.appendingPathComponent("requests", isDirectory: true) }
    private var answersDir: URL { AgentIslandService.directory.appendingPathComponent("answers", isDirectory: true) }
    private var statusDir: URL { AgentIslandService.directory.appendingPathComponent("status", isDirectory: true) }
    private var pidURL: URL { AgentIslandService.directory.appendingPathComponent("app.pid") }
    private var timeoutURL: URL { AgentIslandService.directory.appendingPathComponent("timeout") }

    private init() {}

    var timeout: TimeInterval { AppSettings.shared.agentTimeout }

    /// state.json `agent`.
    var state: [String: Any] {
        ["enabled": enabled, "pending": requests.map { "\($0.tool): \($0.detail)" }, "lastAnswer": lastAnswer,
         "sessions": lastStatusAt.count, "hooksInstalled": ShellHookInstaller.agentHooksInstalled, "installTest": installTest]
    }

    func start() {
        guard !started else { return }
        started = true
        let settings = AppSettings.shared
        settings.$agentIsland
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.enable() : self?.disable() }
            .store(in: &cancellables)
        settings.$agentTimeout
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.writeTimeout() }
            .store(in: &cancellables)
    }

    /// Answers a request (buttons in the notch, or `dynanotch://agent/answer`). Requests that are gone (answered in
    /// the terminal, timed out) are ignored, so a card that is still on screen can't answer a newer request.
    @discardableResult
    func answer(id: String, _ decision: AgentDecision) -> Bool {
        guard !id.isEmpty, requests.contains(where: { $0.id == id }),
              FileManager.default.fileExists(atPath: requestsDir.appendingPathComponent(id + ".json").path) else {
            lastAnswer = "ignored \(decision.rawValue) \(id)"
            scanRequests()
            return false
        }
        let url = answersDir.appendingPathComponent(id)
        let tmp = answersDir.appendingPathComponent(id + ".tmp")
        do {
            try FileManager.default.createDirectory(at: answersDir, withIntermediateDirectories: true)
            try decision.rawValue.write(to: tmp, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            logger.error("answer write failed: \(error.localizedDescription, privacy: .public)")
        }
        lastAnswer = "\(decision.rawValue) \(id)"
        requests.removeAll { $0.id == id }
        return true
    }

    // MARK: Private

    private func enable() {
        guard !enabled else { return }
        enabled = true
        let fm = FileManager.default
        for dir in [requestsDir, answersDir, statusDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Answers nobody picked up (their hook timed out or was killed) must never match a later request.
        for file in (try? fm.contentsOfDirectory(at: answersDir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: file)
        }
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: pidURL, atomically: true, encoding: .utf8)
        writeTimeout()
        watch(requestsDir) { [weak self] in self?.scanRequests() }
        watch(statusDir) { [weak self] in self?.scanStatus() }
        scanRequests()
    }

    private func disable() {
        guard enabled else { return }
        enabled = false
        try? FileManager.default.removeItem(at: pidURL)   // the hook script sees no app and returns at once
        sources.forEach { $0.cancel() }
        sources = []
        pruneTimer = nil
        requests = []
    }

    private func writeTimeout() {
        guard enabled else { return }
        try? "\(Int(timeout))".write(to: timeoutURL, atomically: true, encoding: .utf8)
    }

    private func watch(_ dir: URL, onChange: @escaping () -> Void) {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(fd) }
        source.resume()
        sources.append(source)
    }

    private func scanRequests() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: requestsDir, includingPropertiesForKeys: nil)) ?? []
        let now = Date()
        var found: [AgentRequest] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let request = AgentRequest.parse(data) else { continue }
            if now.timeIntervalSince(request.createdAt) > timeout + 30 || !AgentIslandService.hookIsAlive(request.id) {
                try? fm.removeItem(at: file)   // left behind by a hook that was killed
                continue
            }
            found.append(request)
        }
        found.sort { $0.createdAt < $1.createdAt }
        if found != requests { requests = found }
        if requests.isEmpty {
            pruneTimer = nil
        } else if pruneTimer == nil {
            pruneTimer = Timer.publish(every: 2, tolerance: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.scanRequests() }
        }
    }

    /// The hook's process id is the part of the request id after the dash ("<ms>-<pid>").
    private static func hookIsAlive(_ id: String) -> Bool {
        guard let pid = id.split(separator: "-").last.flatMap({ Int32($0) }), pid > 0 else { return true }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func scanStatus() {
        let files = (try? FileManager.default.contentsOfDirectory(at: statusDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let status = AgentSessionStatus.parse(data) else { continue }
            if let seen = lastStatusAt[status.session], status.at <= seen { continue }
            lastStatusAt[status.session] = status.at
            guard Date().timeIntervalSince(status.at) < 30 else { continue }   // old sessions: remember, don't show
            statuses.send(status)
        }
    }
}
