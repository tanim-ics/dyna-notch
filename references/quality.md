# Quality pass

**Measure** (no sudo): `scripts/measure.sh <App> 60` → avg CPU %, idle wake-ups/s, POWER, RSS; `sample <App> 8` → top
frames in our code; record scenario (idle / main use case / settings open). Repeat after every fix.

**Usual offenders → fixes**
- Per-frame UI loops for decoration → Core Animation repeating animations.
- Timers stored in views → one shared ticker; tear down window content on close.
- Polling → OS events: file-system sources (DispatchSource), audio/camera property listeners, workspace/space
  notifications; schedule redraws at known future moments (e.g. next lyric line) instead of fixed rates.
- Remaining polls: add `tolerance`, pause when feature off / user away / tap already provides the signal.

**Sanitizers**: build `-sanitize=thread` and `-sanitize=address` into separate scratch dirs, swap the binary into a copy
of the app, launch via the OS launcher with the runtime inserted, drive every scenario, quit, read `log_path` reports.

**Accessibility**: label every icon-only control (reuse tooltip text), container label for custom surfaces, keyboard
reachability, respect Reduce Motion; then a VoiceOver walk by a human.

**Health** for dogfooding: crash/hang reports split installed vs test builds, top log errors, idle numbers.

**Scorecard**: before/after table, what changed, bugs found, tests added, not done + why. Commit it.
