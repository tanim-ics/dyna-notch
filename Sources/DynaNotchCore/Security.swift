import Foundation

// Security rules for everything that reaches DynaNotch from outside (docs/SECURITY.md).

/// Who may use a `dynanotch://` URL. Web pages, mail and documents can open custom URLs, so only harmless hooks are
/// public; everything that changes settings, clicks, answers Claude Code, writes files or touches updates needs the
/// per-launch secret from `~/Library/Application Support/DynaNotch/test-token` (readable only by this user).
public enum URLHookPolicy {
    /// Hooks anyone may call: show a message, open / close the panel or a tab, start a timer, play a demo popup.
    public static let publicActions: Set<String> = [
        "notify", "tab", "expand", "collapse", "settings", "timer", "whatsnew", "simulate", "pin", "unpin", "batteries",
    ]

    public static let tokenItem = "token"

    /// True when `action` is public, or the URL carries the secret `expected` token.
    public static func isAllowed(action: String, token: String?, expected: String) -> Bool {
        if publicActions.contains(action.lowercased()) { return true }
        guard let token = token, !expected.isEmpty else { return false }
        return constantTimeEqual(token, expected)
    }

    /// Compares without returning early, so timing reveals nothing about the secret.
    public static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    /// Hex encoding of random bytes (the caller supplies them from the system's secure generator).
    public static func hexToken(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// File names that come from outside (URL hooks): letters, digits, `.`, `_`, `-`; no leading dot, no path parts.
public enum SafeFileName {
    public static func sanitize(_ name: String, fallback: String, maxLength: Int = 64) -> String {
        let allowed = name.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "." || $0 == "_" || $0 == "-"
        }
        var cleaned = String(String.UnicodeScalarView(allowed))
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = String(cleaned.prefix(maxLength))
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// True when `path` (after resolving `..` and symlinks) is inside `directory`.
    public static func isInside(_ path: String, directory: String) -> Bool {
        let file = canonical(path)
        var dir = canonical(directory)
        if !dir.hasSuffix("/") { dir += "/" }
        return file.hasPrefix(dir)
    }

    /// Resolves `..` and the symlinks of the longest existing ancestor (so a file that doesn't exist yet and its
    /// folder resolve alike, e.g. /private/tmp → /tmp).
    static func canonical(_ path: String) -> String {
        var existing = URL(fileURLWithPath: path).standardizedFileURL
        var rest: [String] = []
        while existing.path != "/" && !FileManager.default.fileExists(atPath: existing.path) {
            rest.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for part in rest { resolved.appendPathComponent(part) }
        return resolved.standardizedFileURL.path
    }
}

/// Where updates may come from: this repository's GitHub releases over HTTPS, nothing else.
public enum UpdateTrust {
    public static let owner = "tanim-ics"
    public static let repo = "dyna-notch"

    /// A release asset download (`https://github.com/<owner>/<repo>/releases/download/…`).
    public static func isTrustedAsset(_ url: URL) -> Bool {
        isGitHub(url) && url.path.hasPrefix("/\(owner)/\(repo)/releases/download/")
    }

    /// The release page opened when the app can't replace itself.
    public static func isTrustedPage(_ url: URL) -> Bool {
        isGitHub(url) && url.path.hasPrefix("/\(owner)/\(repo)/")
    }

    /// Install only a trusted asset whose SHA-256 GitHub published (checked against the download before unpacking).
    public static func canInstall(_ update: AvailableUpdate) -> Bool {
        isTrustedAsset(update.zipURL) && update.sha256 != nil
    }

    private static func isGitHub(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "github.com" && url.user == nil
            && url.password == nil && (url.port == nil || url.port == 443) && !url.path.contains("..")
    }
}

extension AgentRequest {
    /// The hook script names requests `<milliseconds>-<pid>`; anything else is not ours.
    public static func isValidID(_ id: String) -> Bool {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.count <= 20 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }
}
