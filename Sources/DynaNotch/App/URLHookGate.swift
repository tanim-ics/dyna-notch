import Darwin
import Foundation
import os
import DynaNotchCore

/// Guards `dynanotch://` (docs/SECURITY.md). Links opened by anyone (web pages, mail, documents, other apps) may only
/// use the public hooks (`URLHookPolicy`), rate-limited. Everything else arrives through `LocalControlServer`: a Unix
/// socket in the private data folder that only accepts connections from this user, so there is no secret to leak.
enum URLHookGate {
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "security")

    /// Links from outside: at most 8 per 10 s (no flooding the notch or its sounds).
    private static var publicLimiter = HookRateLimiter()

    /// Called once at launch: locks the data folder to this user and removes the old token file.
    static func prepare() {
        let fm = FileManager.default
        let dir = AppDataStore.directory
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        } catch {
            logger.error("data folder lock failed: \(error.localizedDescription, privacy: .private)")
        }
        try? fm.removeItem(at: dir.appendingPathComponent("test-token"))
        DataProtection.lockDown(dir)
    }

    /// True when a link opened from outside may run (public hook, within the rate limit).
    static func allowsPublic(_ url: URL) -> Bool {
        let action = url.host ?? ""
        let argument = url.pathComponents.dropFirst().first ?? ""
        guard URLHookPolicy.isPublic(action: action, argument: argument) else {
            logger.notice("refused dynanotch://\(action, privacy: .public)/\(argument, privacy: .public) from outside")
            return false
        }
        guard publicLimiter.allow(now: Date()) else {
            logger.notice("rate-limited dynanotch://\(action, privacy: .public)")
            return false
        }
        return true
    }
}

/// Test and automation channel: `~/Library/Application Support/DynaNotch/control.sock` (0600, folder 0700). One
/// `dynanotch://…` line per connection; the reply is `ok` or `refused`. Only processes running as this user get in
/// (`getpeereid`). Idle cost: one listening descriptor, no timers.
final class LocalControlServer {
    static let shared = LocalControlServer()

    var handler: ((URL) -> Void)?

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "security")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.control")
    private var listenSource: DispatchSourceRead?
    private var listenFD: Int32 = -1

    static var socketURL: URL { AppDataStore.directory.appendingPathComponent("control.sock") }

    func start() {
        guard listenSource == nil else { return }
        let path = LocalControlServer.socketURL.path
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return logger.error("control socket: socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else {
            close(fd)
            return logger.error("control socket: path too long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let oldMask = umask(0o177)   // the socket file is created 0600
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(oldMask)
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            return logger.error("control socket: bind/listen failed (\(errno, privacy: .public))")
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.setCancelHandler { close(fd) }
        source.resume()
        listenSource = source
    }

    func stop() {
        listenSource?.cancel()
        listenSource = nil
        unlink(LocalControlServer.socketURL.path)
    }

    // MARK: Private (control queue)

    private func acceptClient() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
            logger.notice("control socket: refused another user")
            close(client)
            return
        }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 16_384 {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
            if buffer[0..<n].contains(0x0A) { break }
        }
        let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
        let reply: String
        if let url = URL(string: line.trimmingCharacters(in: .whitespaces)), url.scheme?.lowercased() == "dynanotch" {
            reply = "ok\n"
            DispatchQueue.main.async { [weak self] in self?.handler?(url) }
        } else {
            reply = "refused\n"
        }
        _ = reply.withCString { write(client, $0, strlen($0)) }
        close(client)
    }
}

/// Data at rest (docs/SECURITY.md). Files are readable by this user only, and the clipboard history (short-lived,
/// often sensitive) stays out of Time Machine and other backups. Full encryption would need a Keychain key, which an
/// ad-hoc signed app can't read without a password prompt after every update; it comes with a Developer ID.
enum DataProtection {
    /// Clipboard history and its images.
    static let excludedFromBackup = ["clipboard.json", "Clips"]

    static func lockDown(_ dir: URL) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent != "control.sock" {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            try? fm.setAttributes([.posixPermissions: isDir.boolValue ? 0o700 : 0o600], ofItemAtPath: item.path)
        }
        for name in excludedFromBackup {
            keepPrivate(dir.appendingPathComponent(name))
        }
    }

    /// 0600 / 0700 and excluded from backups (the exclusion is an attribute of the file itself).
    static func keepPrivate(_ url: URL) {
        var target = url
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir)
        try? FileManager.default.setAttributes([.posixPermissions: isDir.boolValue ? 0o700 : 0o600],
                                               ofItemAtPath: target.path)
    }
}
