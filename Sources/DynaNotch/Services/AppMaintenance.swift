import AppKit
import Foundation
import ServiceManagement
import os
import DynaNotchCore

/// Caches and uninstall (Settings → About).
enum AppMaintenance {
    struct CacheInfo: Identifiable { let id: String; let name: String; let bytes: Int64 }

    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "maintenance")

    /// Things that can be removed without losing anything the user still sees: test snapshots, screenshots that are
    /// no longer on the Shelf, clipboard images no longer in the history, and the network (artwork / lyrics) cache.
    static func caches() -> [CacheInfo] {
        [
            CacheInfo(id: "snapshots", name: "Test snapshots", bytes: size(of: snapshotFiles())),
            CacheInfo(id: "screenshots", name: "Screenshots not on the Shelf", bytes: size(of: unusedScreenshots())),
            CacheInfo(id: "clips", name: "Unused clipboard images", bytes: size(of: unusedClipImages())),
            CacheInfo(id: "network", name: "Artwork & lyrics downloads", bytes: Int64(URLCache.shared.currentDiskUsage)),
        ]
    }

    static func clearCaches() {
        let files = snapshotFiles() + unusedScreenshots() + unusedClipImages()
        for url in files {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("could not remove \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
            }
        }
        URLCache.shared.removeAllCachedResponses()
        logger.info("cleared \(files.count) cached files")
    }

    /// Removes app data, the login item and installed shell hooks, then quits (the app bundle stays).
    static func uninstall() {
        logger.info("uninstalling DynaNotch data")
        ShellHookInstaller.removeZshHook()
        ShellHookInstaller.removeClaudeCostHook()
        ShellHookInstaller.removeAgentHooks()
        KeepAwakeService.shared.set(false)
        try? SMAppService.mainApp.unregister()
        try? FileManager.default.removeItem(at: AppDataStore.directory)
        URLCache.shared.removeAllCachedResponses()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
        }
        DispatchQueue.main.async {
            NSApp.terminate(nil)
            exit(0)   // terminate(nil) may be cancelled by a window; data is already gone
        }
    }

    // MARK: Private

    private static func children(of dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey],
                                                       options: [.skipsHiddenFiles])) ?? []
    }

    private static func snapshotFiles() -> [URL] {
        children(of: AppDataStore.directory.appendingPathComponent("Snapshots", isDirectory: true))
    }

    private static func unusedScreenshots() -> [URL] {
        let onShelf = Set(ShelfService.shared.items.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        return children(of: AppDataStore.directory.appendingPathComponent("Screenshots", isDirectory: true))
            .filter { !onShelf.contains($0.standardizedFileURL.path) }
    }

    private static func unusedClipImages() -> [URL] {
        let used = Set(ClipboardService.shared.history.items.compactMap { $0.imageFile })
        return children(of: AppDataStore.directory.appendingPathComponent("Clips", isDirectory: true))
            .filter { !used.contains($0.lastPathComponent) }
    }

    private static func size(of urls: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]), values.isDirectory == true {
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
                while let child = enumerator?.nextObject() as? URL {
                    total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                }
            } else {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return total
    }
}

/// Shell hooks: long-command islands in ~/.zshrc and the Claude Code session-cost Stop hook in ~/.claude/settings.json.
/// Both edits are reversible and leave everything else in those files alone. Target paths can be redirected for
/// tests with the environment variables DYNANOTCH_ZSHRC / DYNANOTCH_CLAUDE_SETTINGS (or `zshrcOverride` /
/// `claudeSettingsOverride`).
enum ShellHookInstaller {
    static var zshrcOverride: URL?
    static var claudeSettingsOverride: URL?

    static let blockStart = "# >>> dynanotch >>>"
    static let blockEnd = "# <<< dynanotch <<<"
    static let costScriptName = "claude-cost-hook.pl"

    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "hooks")

    static var zshrcURL: URL {
        if let url = zshrcOverride { return url }
        if let path = DebugEnvironment.value("DYNANOTCH_ZSHRC") { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zshrc")
    }

    static var claudeSettingsURL: URL {
        if let url = claudeSettingsOverride { return url }
        if let path = DebugEnvironment.value("DYNANOTCH_CLAUDE_SETTINGS") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    static var costScriptURL: URL {
        AppDataStore.directory.appendingPathComponent("hooks", isDirectory: true).appendingPathComponent(costScriptName)
    }

    // MARK: zsh long-command islands

    static var zshHookInstalled: Bool {
        guard let text = try? String(contentsOf: zshrcURL, encoding: .utf8) else { return false }
        return text.contains(blockStart)
    }

    /// Appends the hook block (commands that run ≥ 10 s post an island when they finish). Idempotent.
    @discardableResult
    static func installZshHook() -> Bool {
        let url = zshrcURL
        var text = ""
        if FileManager.default.fileExists(atPath: url.path) {
            guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
                logger.error("zshrc unreadable, not installing")
                return false
            }
            text = existing
        }
        text = removingBlock(from: text)
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += (text.isEmpty ? "" : "\n") + zshBlock
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            logger.info("zsh hook installed in \(url.path, privacy: .private)")
            return true
        } catch {
            logger.error("zsh hook install failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    static func removeZshHook() {
        let url = zshrcURL
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains(blockStart) else { return }
        do {
            try removingBlock(from: text).write(to: url, atomically: true, encoding: .utf8)
            logger.info("zsh hook removed from \(url.path, privacy: .private)")
        } catch {
            logger.error("zsh hook removal failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Text without our delimited block (and the blank line we added before it).
    static func removingBlock(from text: String) -> String {
        guard let start = text.range(of: blockStart) else { return text }
        let endRange = text.range(of: blockEnd, range: start.upperBound..<text.endIndex)
        var lower = start.lowerBound
        var upper = endRange?.upperBound ?? text.endIndex
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        // Swallow the single blank separator line we inserted.
        if lower > text.startIndex {
            let before = text.index(before: lower)
            if text[before] == "\n", before > text.startIndex, text[text.index(before: before)] == "\n" { lower = before }
        }
        var result = text
        result.removeSubrange(lower..<upper)
        return result
    }

    static let zshBlock = """
    \(blockStart)
    # DynaNotch long-command islands: commands that run 10 s or longer show an island when they finish.
    # Added by DynaNotch (Settings → Files & Utilities). Remove it there, or delete this block.
    zmodload zsh/datetime 2>/dev/null
    autoload -Uz add-zsh-hook
    __dynanotch_enc() {
      local LC_ALL=C s="$1" o="" c i
      for (( i = 1; i <= ${#s}; i++ )); do
        c="${s[i]}"
        case "$c" in
          [a-zA-Z0-9.~_-]) o+="$c" ;;
          *) o+=$(printf '%%%02X' "'$c") ;;
        esac
      done
      print -r -- "$o"
    }
    __dynanotch_preexec() { __dynanotch_cmd="$1"; __dynanotch_start=$EPOCHSECONDS; }
    __dynanotch_precmd() {
      local st=$?
      [[ -z "$__dynanotch_start" ]] && return
      local d=$(( EPOCHSECONDS - __dynanotch_start )); unset __dynanotch_start
      (( d >= 10 )) || return
      local first="${${(z)__dynanotch_cmd}[1]}"
      case "${first:t}" in
        vi|vim|nvim|nano|emacs|less|more|man|ssh|mosh|top|htop|btop|tmux|screen|watch|claude|codex|python|python3|node|irb|zsh|bash) return ;;
      esac
      local took="${d}s"; (( d >= 60 )) && took="$(( d / 60 ))m $(( d % 60 ))s"
      local title="Command finished" sym="checkmark.circle.fill"
      (( st != 0 )) && { title="Command failed ($st)"; sym="xmark.octagon.fill"; }
      local body="${__dynanotch_cmd[1,60]} · $took"
      /usr/bin/open -g "dynanotch://notify?title=$(__dynanotch_enc "$title")&body=$(__dynanotch_enc "$body")&symbol=$sym" >/dev/null 2>&1 &!
    }
    add-zsh-hook preexec __dynanotch_preexec
    add-zsh-hook precmd __dynanotch_precmd
    \(blockEnd)

    """

    // MARK: Claude Code cost Stop hook

    static var claudeCostHookInstalled: Bool {
        guard let root = readClaudeSettings(), let hooks = root["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [Any] else { return false }
        return stop.contains { isOurGroup($0) }
    }

    /// Writes the cost script to App Support and adds a Stop hook entry that runs it. Other settings stay as they are
    /// (a one-time backup is written next to the file as settings.json.dynanotch-backup).
    @discardableResult
    static func installClaudeCostHook() -> Bool {
        guard writeCostScript() else { return false }
        let url = claudeSettingsURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard var root = exists ? readClaudeSettings() : [:] else {
            logger.error("Claude settings unreadable, not installing the cost hook")
            return false
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var stop = (hooks["Stop"] as? [Any] ?? []).filter { !isOurGroup($0) }
        stop.append([
            "hooks": [["type": "command", "command": "\"\(costScriptURL.path)\""]],
        ] as [String: Any])
        hooks["Stop"] = stop
        root["hooks"] = hooks
        if exists { backupOnce(url) }
        return writeClaudeSettings(root, to: url)
    }

    static func removeClaudeCostHook() {
        let url = claudeSettingsURL
        guard var root = readClaudeSettings(), var hooks = root["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [Any], stop.contains(where: { isOurGroup($0) }) else { return }
        let remaining = stop.filter { !isOurGroup($0) }
        if remaining.isEmpty { hooks.removeValue(forKey: "Stop") } else { hooks["Stop"] = remaining }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        _ = writeClaudeSettings(root, to: url)
    }

    // MARK: Agent Island hooks (CONTRACTS §6.14)

    static let agentScriptName = "agent-hook.pl"
    /// Events that report status; `PermissionRequest` waits for the notch.
    static let agentStatusEvents = ["UserPromptSubmit", "PreToolUse", "Stop", "Notification"]

    static var agentScriptURL: URL {
        AppDataStore.directory.appendingPathComponent("hooks", isDirectory: true).appendingPathComponent(agentScriptName)
    }

    static var agentHooksInstalled: Bool {
        guard let root = readClaudeSettings(), let hooks = root["hooks"] as? [String: Any],
              let permission = hooks["PermissionRequest"] as? [Any] else { return false }
        return permission.contains { isAgentGroup($0) }
    }

    /// Writes the script and adds our groups for PermissionRequest (waits up to `timeout` + 30 s) and the status
    /// events. Other hooks stay; a one-time backup is written next to the file.
    @discardableResult
    static func installAgentHooks(timeout: Int) -> Bool {
        guard writeScript(agentScript, to: agentScriptURL) else { return false }
        let url = claudeSettingsURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard var root = exists ? readClaudeSettings() : [:] else {
            logger.error("Claude settings unreadable, not installing the agent hooks")
            return false
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let script = "\"\(agentScriptURL.path)\""
        var permission = (hooks["PermissionRequest"] as? [Any] ?? []).filter { !isAgentGroup($0) }
        permission.append(["hooks": [["type": "command", "command": "\(script) permission",
                                      "timeout": timeout + 30]]] as [String: Any])
        hooks["PermissionRequest"] = permission
        for event in agentStatusEvents {
            var list = (hooks[event] as? [Any] ?? []).filter { !isAgentGroup($0) }
            list.append(["hooks": [["type": "command", "command": "\(script) status", "timeout": 5]]] as [String: Any])
            hooks[event] = list
        }
        root["hooks"] = hooks
        if exists { backupOnce(url) }
        return writeClaudeSettings(root, to: url)
    }

    static func removeAgentHooks() {
        let url = claudeSettingsURL
        guard var root = readClaudeSettings(), var hooks = root["hooks"] as? [String: Any] else { return }
        var changed = false
        for event in ["PermissionRequest"] + agentStatusEvents {
            guard let list = hooks[event] as? [Any], list.contains(where: { isAgentGroup($0) }) else { continue }
            let remaining = list.filter { !isAgentGroup($0) }
            if remaining.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = remaining }
            changed = true
        }
        guard changed else { return }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        _ = writeClaudeSettings(root, to: url)
    }

    private static func isAgentGroup(_ group: Any) -> Bool {
        guard let dict = group as? [String: Any], let list = dict["hooks"] as? [Any] else { return false }
        return list.contains { item in
            ((item as? [String: Any])?["command"] as? String)?.contains("/hooks/" + agentScriptName) == true
        }
    }

    private static func writeScript(_ text: String, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return true
        } catch {
            logger.error("script write failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    /// Perl (ships with macOS; JSON::PP is core). `permission`: hands the request to DynaNotch and waits for Allow /
    /// Deny / Terminal; prints Claude's decision JSON, or nothing (Claude then asks in the terminal) when DynaNotch
    /// isn't running, Agent Island is off, the user picks Terminal or the timeout passes. `status`: records what the
    /// session is doing and returns at once. Always exits 0. `DYNANOTCH_AGENT_DIR` redirects the folder for tests.
    static let agentScript = #"""
    #!/usr/bin/perl
    # DynaNotch Agent Island: Claude Code permission requests and session status in the notch. Installed by DynaNotch.
    use strict; use warnings; use JSON::PP; use Time::HiRes qw(sleep time); use File::Path qw(make_path);
    my $mode = shift // 'status';
    if ($mode eq 'check') { print "ok\n"; exit 0; }       # installer / test sanity check
    my $raw = do { local $/; <STDIN> } // '';
    my $in = eval { decode_json($raw) } || {};
    my $dir = $ENV{DYNANOTCH_AGENT_DIR} || "$ENV{HOME}/Library/Application Support/DynaNotch/agent";
    sub slurp { my $f = shift; open(my $h, '<', $f) or return undef; local $/; my $t = <$h>; close $h; return $t; }
    sub put { my ($f, $t) = @_; open(my $h, '>', "$f.tmp") or return; print $h $t; close $h; rename("$f.tmp", $f); }
    my $pid = slurp("$dir/app.pid") // '';
    $pid =~ s/\s+//g;
    exit 0 unless $pid =~ /^\d+$/ && kill(0, $pid);        # DynaNotch not running or Agent Island off
    my $json = JSON::PP->new->canonical;
    if ($mode eq 'permission') {
      make_path("$dir/requests", "$dir/answers");
      my $id = sprintf('%d-%d', time() * 1000, $$);
      my $timeout = slurp("$dir/timeout") // 60; $timeout =~ s/\s+//g; $timeout = 60 unless $timeout =~ /^\d+$/;
      put("$dir/requests/$id.json", $json->encode({ id => $id, session => $in->{session_id} // '', cwd => $in->{cwd} // '',
        tool => $in->{tool_name} // '', input => (ref($in->{tool_input}) eq 'HASH' ? $in->{tool_input} : {}), createdAt => time() }));
      my ($answer, $end) = ('', time() + $timeout);
      while (time() < $end) {
        my $a = slurp("$dir/answers/$id");
        if (defined $a) { ($answer = $a) =~ s/\s+//g; last; }
        last unless kill(0, $pid);
        sleep(0.15);
      }
      unlink("$dir/requests/$id.json", "$dir/answers/$id");
      if ($answer eq 'allow') {
        print '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}';
      } elsif ($answer eq 'deny') {
        print '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from DynaNotch"}}}';
      }
      exit 0;
    }
    make_path("$dir/status");
    my $session = $in->{session_id} // 'unknown'; $session =~ s/[^A-Za-z0-9._-]//g;
    put("$dir/status/$session.json", $json->encode({ session => $session, cwd => $in->{cwd} // '',
      event => $in->{hook_event_name} // '', tool => $in->{tool_name} // '',
      input => (ref($in->{tool_input}) eq 'HASH' ? $in->{tool_input} : {}), at => time() }));
    exit 0;
    """#

    private static func isOurGroup(_ group: Any) -> Bool {
        guard let dict = group as? [String: Any], let list = dict["hooks"] as? [Any] else { return false }
        return list.contains { item in
            ((item as? [String: Any])?["command"] as? String)?.contains("/hooks/" + costScriptName) == true
        }
    }

    private static func readClaudeSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeSettingsURL) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeClaudeSettings(_ root: [String: Any], to url: URL) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            logger.info("Claude settings updated: \(url.path, privacy: .private)")
            return true
        } catch {
            logger.error("Claude settings write failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private static func backupOnce(_ url: URL) {
        let backup = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".dynanotch-backup")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? FileManager.default.copyItem(at: url, to: backup)
    }

    private static func writeCostScript() -> Bool {
        let url = costScriptURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try costScript.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return true
        } catch {
            logger.error("cost script write failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    /// Perl (ships with macOS, JSON::PP is core). Reads the Stop hook JSON from stdin, sums the transcript's usage for
    /// the last reply (assistant entries after the last real prompt) and the whole session, prices it like
    /// `ModelPricing`, and posts `dynanotch://notify`. Always exits 0 so it never blocks Claude Code.
    static let costScript = #"""
    #!/usr/bin/perl
    # DynaNotch: Claude Code Stop hook — shows the cost of the last reply in the notch. Installed by DynaNotch.
    use strict; use warnings; use JSON::PP;
    my $in = do { local $/; <STDIN> } // '';
    my $hook = eval { decode_json($in) } || {};
    my $path = $hook->{transcript_path} or exit 0;
    open(my $fh, '<', $path) or exit 0;
    my %price = (opus => [15, 75, 18.75, 1.5], sonnet => [3, 15, 3.75, 0.3], haiku => [1, 5, 1.25, 0.1], fable => [15, 75, 18.75, 1.5]);
    sub cost { my ($model, $u) = @_; my $p = $price{sonnet};
      for my $f (qw(opus sonnet haiku fable)) { if (index(lc($model // ''), $f) >= 0) { $p = $price{$f}; last } }
      return (($u->{input_tokens} // 0) * $p->[0] + ($u->{output_tokens} // 0) * $p->[1]
            + ($u->{cache_creation_input_tokens} // 0) * $p->[2] + ($u->{cache_read_input_tokens} // 0) * $p->[3]) / 1e6; }
    my ($session, $reply, $tokens) = (0, 0, 0); my %seen;
    while (my $line = <$fh>) {
      my $e = eval { decode_json($line) } or next;
      my $type = $e->{type} // '';
      if ($type eq 'user') {
        my $c = $e->{message}{content};
        my $prompt = !ref($c) || (ref($c) eq 'ARRAY' && grep { ref($_) eq 'HASH' && ($_->{type} // '') eq 'text' } @$c);
        if ($prompt && !$e->{isMeta}) { $reply = 0; $tokens = 0; }
      } elsif ($type eq 'assistant' && ref($e->{message}{usage}) eq 'HASH') {
        my $key = ($e->{message}{id} // '') . ':' . ($e->{requestId} // '');
        next if $key ne ':' && $seen{$key}++;
        my $u = $e->{message}{usage}; my $c = cost($e->{message}{model}, $u);
        $session += $c; $reply += $c;
        $tokens += ($u->{input_tokens} // 0) + ($u->{output_tokens} // 0) + ($u->{cache_creation_input_tokens} // 0) + ($u->{cache_read_input_tokens} // 0);
      }
    }
    close($fh);
    exit 0 if $reply <= 0;
    sub tok { my $n = shift; return $n >= 1e6 ? sprintf('%.1fM', $n / 1e6) : $n >= 1e3 ? sprintf('%.1fK', $n / 1e3) : $n; }
    sub enc { my $s = shift; utf8::upgrade($s); utf8::encode($s); $s =~ s/([^A-Za-z0-9._~-])/sprintf('%%%02X', ord($1))/ge; return $s; }
    my $body = sprintf("Reply \$%.2f \x{00B7} %s tokens \x{00B7} session \$%.2f", $reply, tok($tokens), $session);
    my $url = 'dynanotch://notify?title=' . enc('Claude Code') . '&body=' . enc($body) . '&symbol=sparkles';
    if ($ENV{DYNANOTCH_HOOK_DRY_RUN}) { print "$url\n"; exit 0; }
    system('/usr/bin/open', '-g', $url);
    exit 0;
    """#
}
