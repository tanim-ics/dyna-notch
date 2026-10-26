import SwiftUI
import AppKit
import Combine
import CoreImage
import os
import DynaNotchCore

/// Scan QR Code (header button): `screencapture -i` an area to a temp file, decode with CIDetector, copy the text.
/// A URL is never opened automatically: the header button turns into "Open link" for 20 s.
final class QRScanner: ObservableObject {
    static let shared = QRScanner()

    @Published private(set) var isScanning = false
    @Published private(set) var pendingURL: URL?

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "qr")
    private var expiry: DispatchWorkItem?

    private init() {}

    /// `report(title, body, symbol)` posts the result island.
    func scan(report: @escaping (String, String, String) -> Void) {
        guard !isScanning else { return }
        isScanning = true
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dynanotch-qr-\(UUID().uuidString).png")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", file.path]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                self?.logger.error("screencapture failed: \(error.localizedDescription, privacy: .public)")
            }
            // Esc during the selection leaves no file: then stay silent.
            let captured = FileManager.default.fileExists(atPath: file.path)
            let texts = captured ? QRScanner.decode(file) : []
            try? FileManager.default.removeItem(at: file)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isScanning = false
                guard captured else { return }
                guard let text = texts.first else {
                    report("No QR Code Found", "Select an area that contains a QR code", "qrcode.viewfinder")
                    return
                }
                PanelPasteboard.copy(text)
                if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                    self.offer(url)
                    report("QR Link Copied", url.host ?? text, "qrcode")
                } else {
                    report("QR Code Copied", String(text.prefix(80)), "qrcode")
                }
            }
        }
    }

    func openPending() {
        guard let url = pendingURL else { return }
        NSWorkspace.shared.open(url)
        clearPending()
    }

    func clearPending() {
        expiry?.cancel()
        expiry = nil
        pendingURL = nil
    }

    private func offer(_ url: URL) {
        expiry?.cancel()
        pendingURL = url
        let work = DispatchWorkItem { [weak self] in self?.pendingURL = nil }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    static func decode(_ file: URL) -> [String] {
        guard let image = CIImage(contentsOf: file),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return [] }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.filter { !$0.isEmpty }
    }
}

/// Listening TCP ports (header "Ports" button): `lsof -iTCP -sTCP:LISTEN -nP`.
final class PortsService: ObservableObject {
    struct ListeningPort: Identifiable, Equatable {
        var id: String { "\(pid):\(port)" }
        let command: String
        let pid: Int32
        let port: Int
        let address: String
    }

    static let shared = PortsService()

    @Published private(set) var ports: [ListeningPort] = []

    private let queue = DispatchQueue(label: "com.tanim.dynanotch.ports", qos: .utility)
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "ports")
    private var timer: AnyCancellable?
    private var holders = 0

    private init() {}

    /// Refreshes every 10 s while at least one view holds it.
    func acquire() {
        holders += 1
        refresh()
        if timer == nil {
            timer = Timer.publish(every: 10, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        }
    }

    func release() {
        holders = max(0, holders - 1)
        if holders == 0 {
            timer?.cancel()
            timer = nil
        }
    }

    func refresh() {
        queue.async { [weak self] in
            let list = PortsService.read()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if list != self.ports { self.ports = list }
            }
        }
    }

    /// SIGTERM to the owning process (only processes of this user can be stopped).
    func stop(_ port: ListeningPort) {
        let result = kill(port.pid, SIGTERM)
        if result != 0 { logger.error("kill \(port.pid) failed: \(errno)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.refresh() }
    }

    private static func read() -> [ListeningPort] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-nP", "-F", "pcn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// `-F pcn` output: "p<pid>", "c<command>", then one "n<addr>:<port>" per socket.
    static func parse(_ text: String) -> [ListeningPort] {
        var out: [ListeningPort] = []
        var seen = Set<String>()
        var pid: Int32 = 0
        var command = ""
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                let address = String(value[..<colon])
                let key = "\(pid):\(port)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(ListeningPort(command: command, pid: pid, port: port, address: address))
            default: break
            }
        }
        return out.sorted { $0.port < $1.port }
    }
}
