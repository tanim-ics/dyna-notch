# CLAUDE.md — DynaNotch

A native Dynamic Island for macOS (SwiftUI in a borderless `NSPanel`), modelled on Alcove and Notchy. Personal build,
installed from source on the owner's Mac. **Version 3.2.0 · status: feature-complete through §2e P2, quality pass done
(see `SCORECARD.md`).**

This file holds what every change must respect. Reference material lives in `docs/`:

| Doc | What's in it | Update when |
|---|---|---|
| `docs/CONTRACTS.md` | Binding public APIs (Core types, services, settings, URL hooks) | **Before** changing an API — same commit |
| `docs/ROADMAP.md` | Feature-parity boards, gap list with priorities and ✅/⏳/❌ status | A feature lands or is dropped |
| `docs/UX.md` | Visual / motion spec | A screen's behaviour changes |
| `docs/DECISIONS.md` | Owner decisions and process log, dated | The owner decides something |
| `SCORECARD.md` | Performance, sanitizer and test results | After each quality pass |
| `README.md` | Short user guide (install = `./build.sh`) | User-visible behaviour changes |

Code comments citing "CLAUDE.md §2…" or "§6.x" refer to the section numbers kept in `docs/ROADMAP.md` (§2–§2e) and
`docs/CONTRACTS.md` (§6.1–§6.8). Process and lessons: the `app-dev-playbook` skill; project specifics:
`.claude/skills/dynanotch-dev`; history: `docs/RETRO.md`.

---

## 1. Product

**Goals:** an island that merges with the notch and opens into a tabbed panel (music + lyrics, timers, clipboard,
shelf, notes, calendar, system, AI usage …); system HUDs and live activities; Notchy feature parity where public APIs
allow. **Never get in the way:** click-through outside the island, hidden in full screen, no Dock icon, idle CPU ≈ 0.

**Non-goals:** private SkyLight APIs (lock-screen widgets, Face Unlock), mirroring other apps' notifications, paid or
keyed network services, App Store / notarised distribution, licensing. Network use is limited to keyless public APIs
(iTunes Search, LRCLIB, Open-Meteo); everything else stays on the Mac.

## 2. Quick start

| Task | Command |
|---|---|
| Test, build, sign, install, launch | `./build.sh` (`--skip-tests`, `--no-install`, `--dmg`, `--debug`) |
| Unit tests (Core, 224) | `swift test` |
| All checks (build, tests, parse, adapter, scripts, Info.plist) | `scripts/check.sh` — add `--ui` for the 94 UI checks against the running app |
| Health (crashes, hangs, log errors, idle energy) | `scripts/health.sh [days]` |
| Live log | `log stream --predicate 'subsystem == "com.tanim.dynanotch"'` |

Toolchain: macOS 27, Xcode 27, Swift 6.4 (Swift 5 language mode), deployment target macOS 14. SwiftPM only, no
`.xcodeproj`.

## 3. Architecture

```
Sources/
  DynaNotchCore/   pure Foundation logic: IslandEngine (state machine), IslandLayout (geometry), parsers, detectors,
                   calculators — platform-independent, unit-tested, builds on Linux
  DynaNotch/
    App/           AppDelegate (URL hooks), AppActions, settings / welcome / palette windows, StatusItem, UITestDriver
    Window/        NotchPanel, IslandWindowController (placement, click-through, hover, drags), HoverRegions, helpers
    Model/         AppSettings (UserDefaults-backed), IslandViewModel (owns the engine + timers)
    Services/      one `final class X { static let shared }` per system integration; publish on the main queue
    Views/         island, compact views, panel header, Tabs/<Name>Tab.swift, Settings/<pages>, Alerts/
Adapter/           MediaRemote helper loaded into /usr/bin/perl (Now Playing on macOS 15.4+)
Tests/             XCTest for DynaNotchCore      scripts/   check, ui-regression, health, check_plist
```

- **Data flow:** services → (Combine) → `IslandViewModel` → `@Published presentation` → SwiftUI. Views send intents
  back to the view model; cross-cutting actions (shortcuts, knock, palette) go through `AppActions`.
- **Presentation priority:** expanded > live activity > hidden (full screen / user hide) > peek > timer (if preferred)
  > lyrics > now playing > timer > idle. Decided by `IslandEngine` (pure, tested).
- **Window:** one transparent `NotchPanel` at the top centre, level `.mainMenu + 3`, `.nonactivatingPanel`,
  `constrainFrameRect` returns the rect unchanged. Canvas = `vm.canvasSize` (≥ 720×320); resized only when panel-size
  settings change, never during animations. Click-through by toggling `ignoresMouseEvents` from pointer hit-tests
  (global + local mouse monitors; fast safety poll only while needed).
- **Data on disk:** `~/Library/Application Support/DynaNotch/` (clipboard, history, snapshots …); settings in
  UserDefaults `dn.<property>` (listed in `SettingsKey.all`), app data `dn.data.*`.

## 4. Engineering rules (binding)

**Concurrency** — no `async`/`await`, `Task {}`, `actor`, `@MainActor`, `@Sendable`, `nonisolated`. GCD + Combine +
completion handlers; UI state is mutated on the main queue only.

**Code** — `final class` by default; no force unwraps (except `static let` resources); `os.Logger(subsystem:
"com.tanim.dynanotch", category:)`, never `print`; every file imports what it uses; pure logic goes to Core with tests;
private APIs only via `dlopen`/`dlsym`, nil-guarded, with a fallback; never write bare `FocusState` in SwiftUI files
(`DynaNotchCore.FocusState` / `@SwiftUI.FocusState`); Core files import CoreGraphics under `#if canImport(CoreGraphics)`.

**Energy** — no per-frame SwiftUI loops (`TimelineView(.animation)`) for decorative motion: use Core Animation layers
(`Views/LayerAnimations.swift`). Never store `Timer.publish(…).autoconnect()` in a View (use a shared ticker such as
`SettingsTicker`). Prefer system notifications / listeners to polling; any remaining poll gets a `tolerance` and stops
when its feature is off or the user is away. Budget: idle ≤ 0.2 % CPU and ≤ 4 wake-ups/s (`scripts/health.sh`).

**Privacy & permissions** — every TCC-protected API needs its usage string in `Packaging/Info.plist`
(`scripts/check_plist.py` enforces the list); never trigger a permission prompt at launch for a feature the user
hasn't used; say where data lives in the UI ("Stays on this Mac").

**Settings UX** — page = title + one-line subtitle; row = coloured icon + title + one grey sentence stating the effect
*and its cost*; dependants dimmed, never hidden; sliders show the value with −/+; segmented control for 2–4 options;
destructive actions red with inline confirm; every page ends with "Restore Defaults"; changes apply live.

**Signing** — `build.sh` signs ad hoc with a stable designated requirement (`identifier "com.tanim.dynanotch"`) so
permissions survive rebuilds. Don't change it.

## 5. Testing — definition of done

A change is done when **all** of these hold:

1. `swift test` green; new pure logic has Core tests.
2. `scripts/check.sh --ui` green (installs nothing — run `./build.sh` first).
3. The feature was **used like a user** in the installed app through the test hooks below, and the result was seen
   (state assertion or snapshot), including its edge cases (permission denied, empty state, feature off).
4. `docs/ROADMAP.md` row flipped, `docs/CONTRACTS.md` updated if an API changed.
5. No energy regression: `scripts/health.sh 0` idle numbers within budget.

**Test hooks** (no Accessibility needed; implemented in `AppDelegate` / `App/UITestDriver.swift`):

| Hook | Does |
|---|---|
| `dynanotch://state` | writes `Snapshots/state.json` (presentation, tabs, cards, palette, hotkeys, test-ID frames …) |
| `dynanotch://snapshot/<name>` · `snapshot-settings/<page>` · `snapshot-welcome/<name>` · `snapshot-palette/<name>` | renders our own window to `Snapshots/<name>.png` (shell screen capture is not permitted) |
| `dynanotch://ui/pointer?x=&y=` | simulated pointer in island-canvas points (no query = real pointer) |
| `dynanotch://ui/click?window=island\|settings\|palette\|welcome\|dmg&id=<uiTestID>` | real mouse events into our window (`&x=&y=`, `&alt=1`) |
| `dynanotch://ui/menu?item=<title>` | the next menu that opens picks that item |
| `dynanotch://ui/action?name=<HotKeyAction>` · `?knock=` · `?tab=` | as if the shortcut / knock / tab shortcut fired |
| `dynanotch://set?dn.<key>=<value>` | change a setting through AppSettings |
| `dynanotch://tab/<tab>` · `pin/<tab>` · `unpin` · `expand` · `collapse` · `simulate/<demo>` · `notify?…` · `timer/<min>` | drive the island |

Tag every new interactive control with `.uiTestID("…")`; add a check to `scripts/ui-regression.sh` for every new
screen. Sanitizers: build with `-Xswiftc -sanitize=thread|address --scratch-path .build-tsan`, copy the binary into a
copy of the app and launch with `open -n -a <copy> --env DYLD_INSERT_LIBRARIES=<toolchain libclang_rt.*_osx_dynamic.dylib>`
(a binary started from a shell makes the shell the TCC-responsible app and macOS kills it).

## 6. Working agreements

- **Contract first:** new settings, Core types and service APIs are written into `docs/CONTRACTS.md` (and stubbed so
  the app builds) before parallel work starts.
- **Parallel agents** (only when the work is large): disjoint file ownership written into the contract, one
  `--scratch-path .build-<role>` each, and the app lock for install + UI tests (`source scripts/applock.sh`) so only
  one agent drives the installed app at a time. Agents report per item: what was built, the user test run, the result.
- **Budget:** prefer doing small and medium work inline; spawn agents only for independent, large slices.
- **Git:** commit only when the owner asks; one descriptive commit per finished slice; never push.
- **Owner data:** tests must not touch the owner's real files beyond reversible checks (restore settings, volume,
  clipboard; test hook installers against copies; never run Uninstall).
- **Learning loop:** at the end of each feature round, record what went wrong and the fix in the relevant doc, and
  feed reusable lessons back into the `app-dev-playbook` skill (`~/.claude/skills/app-dev-playbook`).
