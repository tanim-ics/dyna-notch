# Lessons (newest first) — symptom → cause → rule

Read at the start of every project. Add one line per lesson in Phase 8; merge duplicates; delete what proved wrong.

## From DynaNotch (macOS notch app, 2026-10)

- 8 % CPU while music played → two 30 fps SwiftUI `TimelineView(.animation)` loops for decorative motion → animate with
  Core Animation layers (render server), never per-frame SwiftUI.
- Wake-ups climbed per Settings page visited (25/s) → `Timer.publish(...).autoconnect()` stored in View structs → one
  shared ticker publisher; drop window content on close.
- Idle wake-ups 22/s → polling everywhere (0.2–1.5 s) → listeners/notifications first; remaining polls get tolerance and
  stop when the feature is off or the user is away. Measure with `top -stats cpu,idlew,power` before and after.
- Empty "Settings" window appeared on quit/relaunch → SwiftUI placeholder `Settings {}` scene opened by ⌘, / window
  restoration → redirect it to the real window, replace the app-menu command, `isRestorable = false`.
- Sanitizer build crashed at launch → binary started from a shell makes the shell the TCC-responsible process
  (missing usage strings) → launch with `open -n -a App --env DYLD_INSERT_LIBRARIES=…`.
- Permissions re-prompted after every rebuild → ad-hoc signature's cdhash requirement changes per build → sign with a
  stable designated requirement (`identifier "<bundle id>"`).
- `check.sh` never finished on macOS → bash 3.2 can't parse `"$("` inside a heredoc in `$( … )`, and a hard-coded
  version check was stale → keep embedded scripts in their own files; check formats, not literal versions; run the
  check script on the real dev machine, not only in CI/Linux.
- Five agents "failed" with nothing written → usage/rate limit mid-wave → contract + stubs must already compile; on
  restart check stubs/locks/build, resume agents by message, back up the tree first; fewer agents when budget is low.
- Keyboard-opened panel closed instantly → "pointer left" logic ran on any settings write → only auto-collapse after the
  pointer actually entered and left; regression-test keyboard-opened UI.
- Menu items "did nothing" → choosing a menu item below the panel moved the pointer out and the panel collapsed →
  hold the panel while its menus track + grace period; test menus with a pick-next-item hook.
- Two identical "Open Calendar" rows in the palette → action titles collided with tab titles → give actions that leave
  the app an explicit suffix ("… App"); scan palettes/menus for duplicate titles in review.
- Hover-to-open untestable via screenshots → use the app's own pointer hit-testing (named hover regions) so the
  scripted pointer exercises the same path as the real mouse.
- Snapshot tests flaky with live data (music, weather, clock) → assert state JSON + "renders non-trivially" instead of
  pixel-exact goldens; reserve goldens for static screens.
- A feature "done" by an agent wasn't tried in the app → "built and compiles" ≠ done → definition of done requires a
  user-level test with an observed result, noted per item.
- 1,200-line CLAUDE.md nobody could scan → history, contracts and roadmap mixed with rules → CLAUDE.md = rules +
  index (≤ 200 lines); contracts / roadmap / decisions / UX in `docs/`.
