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

    /// Tabs a link may open without the token. Mirror turns the camera on; Clipboard, Notes, Reminders, Calendar,
    /// Shelf and AI Usage put private data on screen (e.g. during a screen share).
    public static let publicTabs: Set<String> = [
        "home", "nowPlaying", "timer", "calculator", "emoji", "quickSearch", "launcher", "shortcuts", "system",
        "quickSettings",
    ]

    /// True when the URL carries the secret `expected` token, or the hook is public (and, for `tab` / `pin`, the tab
    /// is one of `publicTabs`; `pin` with no tab is fine).
    public static func isAllowed(action: String, argument: String = "", token: String?, expected: String) -> Bool {
        if let token = token, !expected.isEmpty, constantTimeEqual(token, expected) { return true }
        let action = action.lowercased()
        guard publicActions.contains(action) else { return false }
        if action == "tab" || (action == "pin" && !argument.isEmpty) { return publicTabs.contains(argument) }
        return true
    }

    /// `dynanotch://timer/<minutes>`: 0 < minutes ≤ 24 h, finite (`1e300` used to crash the time formatter).
    public static func timerMinutes(_ argument: String) -> Double? {
        guard let minutes = Double(argument), minutes.isFinite, minutes > 0, minutes <= 24 * 60 else { return nil }
        return minutes
    }

    /// Title / body of a notification from outside, trimmed to what the notch can show.
    public static func clamp(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
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

/// Public hooks per time window, so a page that may open dynanotch:// links can't flood the notch or its sounds.
public struct HookRateLimiter: Equatable {
    public var limit: Int
    public var window: TimeInterval
    private var stamps: [Date] = []

    public init(limit: Int = 8, window: TimeInterval = 10) {
        self.limit = limit
        self.window = window
    }

    public mutating func allow(now: Date) -> Bool {
        stamps.removeAll { now.timeIntervalSince($0) >= window || $0 > now }
        guard stamps.count < limit else { return false }
        stamps.append(now)
        return true
    }
}

/// Text shown for someone to approve (Agent Island): what you see must be what runs.
public enum ApprovalText {
    /// Removes invisible and direction-changing characters (zero-width, bidi overrides, other format and control
    /// characters), turns every run of whitespace into one space, and keeps both ends of long text so the tail of a
    /// chained command (`npm test; curl … | sh`) is never cut off.
    public static func sanitize(_ text: String, limit: Int = 160) -> String {
        var out = ""
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            let category = scalar.properties.generalCategory
            if scalar == "\n" || scalar == "\r" {
                if !lastWasSpace { out += " ⏎ " }
                lastWasSpace = true
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || category == .spaceSeparator {
                if !lastWasSpace { out.unicodeScalars.append(" ") }
                lastWasSpace = true
                continue
            }
            if category == .control || category == .format || category == .unassigned
                || category == .privateUse || category == .surrogate { continue }
            out.unicodeScalars.append(scalar)
            lastWasSpace = false
        }
        out = out.trimmingCharacters(in: .whitespaces)
        guard out.count > limit else { return out }
        let head = (limit - 1) / 2, tail = limit - 1 - head
        return String(out.prefix(head)) + "…" + String(out.suffix(tail))
    }
}
