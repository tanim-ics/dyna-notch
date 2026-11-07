# DynaNotch retrospective (2026-10-26)

- **Shipped:** v2 rewrite (SwiftPM, Alcove parity) → v3 tabbed panel (Notchy parity) → v3.1 glass/header/batteries/
  hello → v3.2 settings audit (7 new tabs, Notchy-style settings) → v3.3/3.4 gap lists P1 + P2 (shortcuts, palette,
  knock, calendar, Home grid, menu-bar readouts …) → quality pass. 224 unit tests, 94 UI checks, idle 0.13–0.18 % CPU.
- **Worked well:** pure Core + tests first; contract + compiling stubs before parallel agents; disjoint file ownership
  with separate build dirs; in-app test hooks (state.json, self-snapshots, UI driver) instead of screen capture;
  frame-by-frame review of the owner's Notchy recording; measuring before optimising.
- **Went wrong:**
  - First P2 wave produced nothing (all agents hit a usage limit) → restarted on the same contract; now: back up the
    tree and resume agents by message.
  - Uncommitted work piled up across v3.2–v3.4 → ask for a checkpoint commit per slice.
  - Agents marked items done without trying them in the app → definition of done = user-level test, per item.
  - Energy was never measured until the end (8 % CPU during playback, 25 wake-ups/s from leaked Settings timers) →
    measure from the first build; energy rules in CLAUDE.md.
  - `check.sh` had silently never worked on macOS (bash 3.2) → run every script on the real machine.
  - Hover, menus and keyboard-opened panels needed several owner bug reports → regression checks for them now exist.
  - CLAUDE.md grew to 1,200 lines → split into rules + docs/.
- **Do differently next time:** test hooks and the regression script in week one; energy budget from the first build;
  fewer, larger agent slices; checkpoint commits; a11y labels as controls are written.
- **Playbook updates made:** `app-dev-playbook` 1.0.0 created from this project (all lessons above in `LESSONS.md`).
- **Project skill:** `.claude/skills/dynanotch-dev/SKILL.md`.


## 2026-10-27 lock-screen strip
- First build put the SkyLight space at level 100: on screen when simulated, invisible on a real lock. Reference
  (Lakr233/SkyLightWindow) uses 400 and window level `Int32.max − 2`. Lesson: a simulated lock can't prove lock-screen
  visibility; compare private-API setups with a known working reference before shipping, and keep a diagnostic
  (`lockScreen.lastLock`) that survives the real event.
- macOS 27 SkyLight calls return 3 on success; check effects (window on-screen list), not return codes.

## 2026-11-01 Agent Island buttons (owner: "just to make a button work you making kinds of issues")
- Per-button gestures in the never-key island panel were unreliable under synthetic clicks; layered fixes (pointer
  regions, arm delay, scale mapping) each added a new failure and cost an hour. The fix that held was the simplest:
  the island's own tap reports where the click landed and the card's equal thirds decide the button.
- Most "bugs" were the test harness: frames read mid-animation, a stale state.json, a test pointer stored in screen
  coordinates, leftover background hooks. Lesson: when a UI test fails twice, check the harness first, and prefer
  the simplest geometry-based handling over cleverness. Stop and tell the owner before going past ~3 attempts.
- Known flaky (2026-11-01): "smart copy: click copies result" fails only inside the full `ui-regression.sh` run
  (171/174), passes alone 8/8 — island state left by an earlier section. Open item.

## 2026-11-02 In-app updates + What's New stories
- A new setting broke `SettingsTests.testSettingsKeys` (hard-coded key count 177): bump the count with every new key.
- `health.sh` right after `check.sh --ui` measured 62 wake-ups/s because the UI suite leaves the Settings window open
  after visiting all 23 pages; a fresh launch measured 2.1/s. Relaunch before the idle measurement. The growth with
  pages visited looks like the old per-page timer leak returning — open item.
- The self-update path can only be tested end to end with two releases; a locally served fake release (re-signed copy
  with a bumped version, `update/feed?url=`) exercised download → verify → swap → relaunch → story without GitHub.

## 2026-11-07 Display picker, Bluetooth noise, popups under the pointer
- **LG display had no island** although Every Display was on: `FullscreenDetector` treated any window filling a display
  as full screen, and on a display whose menu bar auto-hides a zoomed browser window does exactly that. Lesson: "covers
  the display" isn't "full screen"; also require that no other app has a window there (`FullscreenHeuristic`). A real
  full-screen app still hides the island on its display (owner's Brave), which is the setting working.
- **"Podcast" popup**: unclassified Bluetooth devices (a nearby phone) got the generic radio-waves icon. Filter by device
  class and debounce per address, in Core so it's testable.
- **Hover ate notifications**: hover-to-expand ran for every presentation. Popups now hold under the pointer; when adding
  a hover behaviour, decide per presentation kind.
- Test gap: settings rows far down a page can't be clicked by `ui/click` (off screen, `hit=nil`); test their effect
  through `set?` and assert on state. The "agent: copy restored" check compares bytes and fails when the installer
  rewrites the JSON copy with another key order — a flaky check, not a data change.

## 2026-11-07 Security pass
- Every test hook (settings, synthetic clicks, Claude Code answers, update feed) was reachable from any web page via
  `dynanotch://`. Lesson: a custom URL scheme is a public API; test hooks need a secret from the start. Fixed with a
  per-launch token file (docs/SECURITY.md); all test traffic goes through `u()`, so one line changed for the suite.
- The updater trusted an ad-hoc signature with our identifier, which anyone can produce. Trust the source (this repo's
  GitHub release over HTTPS) plus GitHub's published SHA-256 instead.
- Smart Copy's click check missed when the pill floats below the notch (`topInset`); UI test frames ignore `.offset`.
