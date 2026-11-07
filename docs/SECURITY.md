# Security model

DynaNotch runs as you, unsandboxed, with Accessibility and other permissions you grant it. Anything already running
as you on this Mac can do what DynaNotch can; that boundary is macOS's, not ours. What DynaNotch must stop is
**outside input** turning into actions: web pages, mail, documents and other apps that open `dynanotch://` links,
release feeds, and data written by Claude Code hooks.

## `dynanotch://` links (`URLHookPolicy`, `URLHookGate`)

Any web page can try to open a custom URL (browsers ask once, then may remember "always allow").

- **Public:** `notify`, `tab`, `expand`, `collapse`, `settings`, `timer`, `whatsnew`, `simulate`, `pin`, `unpin`,
  `batteries`. Harmless: they show something or open the panel. `tab` / `pin` only reach `URLHookPolicy.publicTabs`
  (Mirror would switch the camera on; Clipboard, Notes, Reminders, Calendar, Shelf, AI Usage show private data).
  `timer` takes 0 < minutes ≤ 1440 only. At most 8 public links per 10 s (`HookRateLimiter`). Notification text is
  clamped (120 / 400 characters) and the Open button names the site it goes to.
- **Everything else needs `token=<secret>`**: `set`, `ui/*` (synthetic clicks, shortcuts), `agent/*` (Claude Code
  answers), `update/*` (feed, install), `state`, `snapshot*`, `alchemy`, `shelf`, `convert`, `voice`, …
- The secret is 32 random bytes from `SecRandomCopyBytes`, new at every launch, written to
  `~/Library/Application Support/DynaNotch/test-token` (0600; the folder is 0700). Compared in constant time.
  Scripts read it (`scripts/ui-regression.sh` → `u()`); pages and documents can't.
- `notify?open=` accepts only `http`/`https` links: a notification anyone can post must never open a local file or
  app. Snapshot names are reduced to `[A-Za-z0-9._-]` (`SafeFileName`). `agent/install-test` only writes to files in
  the temporary folder.

## Updates (`UpdateTrust`)

The ad-hoc signature proves nothing (anyone can sign with our identifier), so trust comes from where the file is:

- The zip must be `https://github.com/tanim-ics/dyna-notch/releases/download/…` and GitHub must publish its SHA-256
  (`digest`), which the download must match before it is unpacked. Otherwise nothing is installed.
- Release notes are fetched only from the same place; the fallback release page opens only on that repository.
- The feed override exists for tests and needs the token.

## Claude Code (Agent Island)

- What you approve is what runs: `ApprovalText.sanitize` drops zero-width, bidi-override and control characters,
  collapses whitespace padding, and keeps both ends of a long command (the card truncates in the middle).
- Allow / Deny / Terminal ignore clicks for 1 s after a request appears (clickjacking: a card popping up under a
  click already on its way).

- Requests come from files the hook script writes; IDs must look like `<ms>-<pid>` (`AgentRequest.isValidID`), and an
  answer is written only for a request that is pending on disk. Only a click in the notch (or a tokened test hook)
  answers.
- Hook scripts get Claude's JSON on stdin, pass arguments as lists (no shell), and URL-encode what they send.

## Other notes

- Data (clipboard history, notes, snapshots) lives in `~/Library/Application Support/DynaNotch`, 0700.
- Clipboard: concealed / transient items and password managers are never recorded (`clipboardIgnoredApps`).
- Network: HTTPS, keyless public APIs only, no cookies (`docs/DECISIONS.md` §16).
- Not covered: malware already running as you, a compromised GitHub account, physical access.

## Pentest log

| Date | Finding | Severity | Fix |
|---|---|---|---|
| 2026-11-07 | Every test hook reachable from web pages (settings, clicks, Claude Code answers, update feed) | Critical | Per-launch token |
| 2026-11-07 | Updater trusted any URL + forgeable ad-hoc signature | High | GitHub repo + published SHA-256 only |
| 2026-11-07 | `notify?open=file://` could run an app/script on click; snapshot path traversal | Medium | http/https only; `SafeFileName` |
| 2026-11-07 | `timer/1e300` crashed the app (Int conversion trap) from any web page | High (DoS) | `timerMinutes` bounds; formatters clamp |
| 2026-11-07 | `tab/mirror` / `pin/mirror` turned the camera on from any web page; private tabs shown on demand | High (privacy) | `publicTabs` allowlist |
| 2026-11-07 | Agent Island: padded / bidi-spoofed commands hid what you approved | High | `ApprovalText.sanitize`, middle truncation |
| 2026-11-07 | Agent Island: request appearing under a click got answered | Medium | 1 s arming delay |
| 2026-11-07 | Notification flood / huge text / phishing links | Low | Rate limit, clamping, host on the button |

Residual (accepted): the token travels in `open` arguments, which other local users can see in `ps` for a moment
(they still can't open URLs in your session); data at rest relies on FileVault; anything running as you is trusted.
