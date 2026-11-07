# Security model

DynaNotch runs as you, unsandboxed, with Accessibility and other permissions you grant it. Anything already running
as you on this Mac can do what DynaNotch can; that boundary is macOS's, not ours. What DynaNotch must stop is
**outside input** turning into actions: web pages, mail, documents and other apps that open `dynanotch://` links,
release feeds, and data written by Claude Code hooks.

## `dynanotch://` links (`URLHookPolicy`, `URLHookGate`)

Any web page can try to open a custom URL (browsers ask once, then may remember "always allow").

- **Public:** `notify`, `tab`, `expand`, `collapse`, `settings`, `timer`, `whatsnew`, `simulate`, `pin`, `unpin`,
  `batteries`. Harmless: they show something or open the panel.
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

- Requests come from files the hook script writes; IDs must look like `<ms>-<pid>` (`AgentRequest.isValidID`), and an
  answer is written only for a request that is pending on disk. Only a click in the notch (or a tokened test hook)
  answers.
- Hook scripts get Claude's JSON on stdin, pass arguments as lists (no shell), and URL-encode what they send.

## Other notes

- Data (clipboard history, notes, snapshots) lives in `~/Library/Application Support/DynaNotch`, 0700.
- Clipboard: concealed / transient items and password managers are never recorded (`clipboardIgnoredApps`).
- Network: HTTPS, keyless public APIs only, no cookies (`docs/DECISIONS.md` §16).
- Not covered: malware already running as you, a compromised GitHub account, physical access.
