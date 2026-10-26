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
