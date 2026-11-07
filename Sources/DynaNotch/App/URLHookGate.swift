import Foundation
import Security
import os
import DynaNotchCore

/// Guards `dynanotch://` (docs/SECURITY.md). Public hooks (notify, tab, timer …) work for anyone; every other hook
/// needs `token=<secret>`, a random value made at each launch and written to
/// `~/Library/Application Support/DynaNotch/test-token` (mode 0600, folder 0700). Scripts on this Mac running as the
/// owner can read it; web pages, mail and documents that open a `dynanotch://` link can't.
enum URLHookGate {
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "security")

    static let token: String = {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            logger.fault("no secure random bytes: test hooks stay locked")
            return ""
        }
        return URLHookPolicy.hexToken(bytes)
    }()

    static var tokenFile: URL { AppDataStore.directory.appendingPathComponent("test-token") }

    /// Called once at launch: locks the data folder to this user and publishes the token for local scripts.
    static func publishToken() {
        let fm = FileManager.default
        let dir = AppDataStore.directory
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? fm.removeItem(at: tokenFile)
            guard !token.isEmpty,
                  fm.createFile(atPath: tokenFile.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
            else { return }
        } catch {
            logger.error("token publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// True when the URL may run. Refusals are logged (without the token).
    static func allows(_ url: URL) -> Bool {
        let action = url.host ?? ""
        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == URLHookPolicy.tokenItem }?.value
        let ok = URLHookPolicy.isAllowed(action: action, token: token, expected: URLHookGate.token)
        if !ok { logger.notice("refused dynanotch://\(action, privacy: .public) without a valid token") }
        return ok
    }
}
