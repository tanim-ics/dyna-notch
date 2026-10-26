---
name: dynanotch-dev
description: >-
  Working on DynaNotch (this repo, the macOS notch app): build/install/test commands, the dynanotch:// test hooks,
  where contracts and the roadmap live, and the project's gotchas. Use for any change, bug fix or test run in this
  repository; follows the user's app-dev-playbook process.
---

# DynaNotch development

Process: follow `~/.claude/skills/app-dev-playbook` (phases, definition of done, retrospective). Rules: `CLAUDE.md`.

**Start of session:** read `CLAUDE.md`, then the relevant `docs/` file (`CONTRACTS.md` before touching an API,
`ROADMAP.md` to pick work). Check `git status` — commit only when the owner asks.

**Commands**
- `./build.sh --skip-tests` — build, sign, install to /Applications, relaunch (needed before any UI test)
- `swift test` · `scripts/check.sh --ui` (110 UI checks, needs the app running) · `scripts/health.sh [days]`
- Lock for install + UI tests when several agents run: `source scripts/applock.sh; applock <name> … appunlock`

**Testing like a user** (all through URL hooks, see the table in CLAUDE.md §5): `open -g "dynanotch://state"` then
read `~/Library/Application Support/DynaNotch/Snapshots/state.json`; `snapshot/<name>` renders the island; `pin/<tab>`
keeps the panel open while testing (the owner's real clicks otherwise close it); `ui/pointer`, `ui/click?id=`,
`ui/menu?item=`, `ui/action?name=`, `set?dn.<key>=`, `simulate/<demo>`. Restore any setting, volume or clipboard you
change. New controls get `.uiTestID`; new screens get a check in `scripts/ui-regression.sh`.

**Gotchas specific to this app**
- Concurrency rule: no async/await/actors/`@MainActor` — GCD + Combine only.
- Energy budget idle ≤ 0.2 % CPU / ≤ 4 wake-ups/s; decorative motion = Core Animation (`Views/LayerAnimations.swift`);
  Settings timers via `SettingsTicker`.
- Default tab, hello intro and other owner settings may differ from defaults — read them, don't assume.
- Two default shortcuts (⌃⌥V, paste plain text) are taken by another app on the owner's Mac.
- Notchy isn't installed on the owner's Mac; the reference recording is `notchy screen recording.mov` (gitignored).

**End of a round:** update `docs/ROADMAP.md`, `SCORECARD.md` if measured, add lessons to the playbook (Phase 8).
