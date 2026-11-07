# Security model

DynaNotch runs as you, with Accessibility and other permissions you grant it. The goal: nothing **outside** the
app — web pages, mail, documents, other apps, other processes, release feeds, files you drop, Claude Code hooks —
can turn into an action you didn't take, read your data, or borrow those permissions.

Every change that adds an input (a hook, a download, a file type, a socket message) updates this file and adds the
attack to `scripts/ui-regression.sh` (definition of done, CLAUDE.md §5).

## 1. The process can't be hijacked (hardened runtime)

- Signed with `--options runtime` and the few entitlements in `Packaging/DynaNotch.entitlements` (Apple Events for
  Music / Spotify, camera, microphone, calendars, location). Library validation stays on.
- Effect: `DYLD_INSERT_LIBRARIES`, unsigned libraries and debugger attach are refused, so no other program can run
  code inside DynaNotch and use its permissions. Verified: an injected library loads into an unhardened copy and is
  blocked in the real build.
- Test-only environment switches (`DYNANOTCH_DMG_AUTOCONFIRM`, `…_INSTALL_DIR`, `…_AGENT_DIR`, `…_ZSHRC`,
  `…_CLAUDE_SETTINGS`) work only in debug builds (`DebugEnvironment`).

## 2. `dynanotch://` links and the control socket

Any web page can try to open a custom URL. Links therefore only reach **public** hooks (`URLHookPolicy`):
`notify`, `tab`, `expand`, `collapse`, `settings`, `timer`, `whatsnew`, `simulate`, `pin`, `unpin`, `batteries`.

- `tab` / `pin` only reach harmless tabs (`publicTabs`); Mirror (camera), Clipboard, Notes, Reminders, Calendar,
  Shelf and AI Usage don't open from a link. `timer` takes 0 < minutes ≤ 1440. At most 8 links per 10 s.
- Notifications: text clamped (120 / 400), `open=` http/https only, the Open button names the site.
- Everything else (settings, synthetic clicks, Claude Code answers, update feed, state, snapshots, Drop Alchemy …)
  only arrives through `LocalControlServer`: `~/Library/Application Support/DynaNotch/control.sock`, mode 0600 in a
  0700 folder, accepting only connections from your own user ID (`getpeereid`). There is no secret to leak.
  Scripts: `printf 'dynanotch://state\n' | nc -U "$SOCK"` (`scripts/ui-regression.sh` → `u()`).
- Snapshot names are reduced to `[A-Za-z0-9._-]`; `agent/install-test` only writes inside the temporary folder.

## 3. Updates

An update installs only when **all** of these hold (`UpdateTrust`, `ReleaseSignature`):

1. The zip and its `.sig` come from `https://github.com/tanim-ics/dyna-notch/releases/download/…`.
2. The zip matches the SHA-256 GitHub publishes for it.
3. The zip carries a valid **Ed25519 signature by the release key**. The private key lives only in the owner's login
   Keychain (`scripts/release-key.sh`, service `com.tanim.dynanotch.release-signing`); the app holds the public key.
   Taking over the GitHub account is not enough to ship an update. **Back that Keychain item up**: without it no
   future release can be signed.
4. The unpacked app passes `codesign --verify --strict --deep` against the requirement: identifier only for ad-hoc
   builds; with a Developer ID, Apple's chain **and the same team ID** (`codeRequirement(bundleID:teamID:)`).

## 4. Untrusted files are decoded in a sandbox

Drop Alchemy (images, PDFs → cutout, text, smaller copy, PNG / JPEG) runs in `DynaNotchWorker`, a separate hardened
process started under `sandbox-exec` with `WorkerSandbox.profile`. Paths are passed as parameters, never pasted into
the profile. Inside: no network, no `fork` / other programs, writes only to its scratch folder and its Vision cache,
reads no file contents in your home folder except the input, and no TCC, pasteboard, Apple Events, Keychain,
Accessibility or window-server services. Verified from inside: reading `~/.zshrc` or the clipboard history, writing
to the Desktop and opening a network connection all fail. If `sandbox-exec` ever disappears, the worker still runs
out of process.

## 5. Claude Code (Agent Island)

- What you approve is what runs: `ApprovalText.sanitize` drops zero-width, bidi-override and control characters,
  collapses whitespace padding and keeps both ends of a long command (middle truncation).
- Allow / Deny / Terminal ignore clicks for 1 s after a request appears (clickjacking).
- Request IDs must be `<ms>-<pid>`; an answer is written only for a request pending on disk.
- Hook scripts read Claude's JSON on stdin, pass arguments as lists (no shell) and URL-encode what they send.

## 6. Data at rest and privacy

- **Encrypted with a Secure Enclave key** (`Vault`, `SealedFile`): clipboard history and its images, notes and
  to-dos (moved out of the preferences plist), recent searches, listening history, screen time, battery, traffic and
  camera / mic logs. AES-256-GCM, file header `DNV1`; the key comes from a P-256 key agreement with a key that never
  leaves this Mac's chip — no certificate, Keychain or prompt. Older plain files are encrypted at launch.
  Copies of the folder (backups, Time Machine, cloud sync, another Mac) are unreadable. A restored folder on a new
  Mac starts fresh (unreadable files are kept as `*.locked`); **Settings → About → Export Notes** moves notes.
  Without a Secure Enclave (some Intel Macs) files stay plain.
- Folder 0700, files 0600; the clipboard history is also excluded from backups.
- **Skip Secrets** (Clipboard, on by default, `SecretDetector`): private keys, access tokens (AWS, GitHub, GitLab,
  Slack, OpenAI, Anthropic, Stripe, Google, npm, JWT, bearer), `password=` / `api_key:` values, URLs with a password,
  card numbers (Luhn) and IBANs (mod 97) are never saved. One-time codes and random-looking tokens leave after
  2 minutes. Long text is only checked for keys and tokens.
- Defaults: **Screen Sharing Privacy** on (the island and panel never appear in shares or recordings), clipboard
  **Auto-Clear** after 1 day, optional **Clear on Lock**. Existing choices are kept.
- Logs: names, titles, paths, URLs, error texts are `.private` (hidden from other admins and sysdiagnose reports);
  only enum values, counts and versions are public.

## 7. Developer ID and notarisation (ready, unused — the owner decided against a paid account)

- `build.sh` prefers a "Developer ID Application" identity and adds a secure timestamp.
- `scripts/release.sh` signs with `RELEASE_IDENTITY` (or that identity) and, with `NOTARY_PROFILE`
  (`xcrun notarytool store-credentials`), notarises and staples.
- The updater then pins the team ID (§3.4). The cask's quarantine stripping can go once releases are notarised.

## 8. Keeping it that way

- `swift test` includes `FuzzTests` (≈ 6,000 hostile inputs per run across every parser that sees outside input;
  `DYNANOTCH_FUZZ_ITERATIONS=100000` for a long run — 400,000 inputs, no crash, on 2026-11-07).
- `.github/workflows/ci.yml`: build, unit + fuzz tests on every push (read-only token, no secrets).
- `scripts/sanitize.sh`: Address and Thread Sanitizer builds driven through a scripted session; any report fails.
- Pentest after each feature round; each attack becomes a check in `scripts/ui-regression.sh`.

## Out of scope

Malware already running as you (it can edit your files and settings directly), a compromised Mac or Apple account,
physical access, and bugs inside macOS itself.

## Pentest log

| Date | Finding | Severity | Fix |
|---|---|---|---|
| 2026-11-07 | Every test hook reachable from web pages (settings, clicks, Claude Code answers, update feed) | Critical | Public-hook allowlist + private control socket |
| 2026-11-07 | Updater trusted any URL + forgeable ad-hoc signature | High | GitHub + SHA-256 + Ed25519 release signature |
| 2026-11-07 | No hardened runtime: injected code could use DynaNotch's permissions | High | Hardened runtime, minimal entitlements |
| 2026-11-07 | `timer/1e300` crashed the app from any web page | High (DoS) | Bounds; formatters clamp |
| 2026-11-07 | `tab/mirror` turned the camera on from a web page; private tabs on demand | High (privacy) | `publicTabs` |
| 2026-11-07 | Agent Island: padded / bidi-spoofed commands hid what you approved | High | `ApprovalText.sanitize` |
| 2026-11-07 | Image / PDF decoding in the app process (a decoder exploit = all permissions) | Medium | Sandboxed worker |
| 2026-11-07 | Test env switches in release builds (auto-install DMGs, redirect hook files) | Medium | Debug-only |
| 2026-11-07 | `notify?open=file://` could run an app; snapshot path traversal | Medium | http/https only; `SafeFileName` |
| 2026-11-07 | Agent Island: request appearing under a click got answered | Medium | 1 s arming delay |
| 2026-11-07 | Secret token visible in `ps` via `open` arguments | Low | Replaced by the control socket |
| 2026-11-07 | Notification flood / huge text / phishing links | Low | Rate limit, clamping, host on the button |
| 2026-11-07 | Notes / to-dos / recent searches in the plain, backed-up preferences plist | Medium (privacy) | Encrypted files |
| 2026-11-07 | Clipboard history kept passwords, keys and card numbers copied from anywhere | Medium (privacy) | Skip Secrets |
| 2026-11-07 | 68 log values (titles, paths, names, errors) public in the system log | Low (privacy) | `.private` |

Residual: clipboard thumbnails are still decoded in the app (ImageIO); the release key was passed to `security` as an
argument once when it was created (milliseconds, single-user Mac); malware running as you can still ask the Secure
Enclave to decrypt (out of scope, as for every app).
