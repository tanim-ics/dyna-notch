# DynaNotch — owner decisions & process log

> Moved out of CLAUDE.md on 2026-10-26 (verbatim). CLAUDE.md links here; update this file when the facts change.

## 8. Team process (agentic)

| Role | Owns |
|---|---|
| Tech lead (orchestrator) | this file, `Package.swift`, contracts, integration, final review |
| Core engineer | `Sources/DynaNotchCore`, `Tests/` — must pass `swift test` on Linux |
| Systems engineer | `Sources/DynaNotch/Services`, `Adapter/` |
| App engineer | `Sources/DynaNotch/App`, `Window`, `Model` |
| UI engineer | `Sources/DynaNotch/Views` |
| Release engineer | `build.sh`, `Packaging/`, `scripts/`, `README.md` |
| Compiler-reviewers ×2 | read every app file as `swiftc` would against the macOS 15 SDK; report and fix type errors, missing imports, API misuse, contract drift |

v3 (2026-10-26): the tech lead wrote Core + tests + model/window/app integration and service skeletons; one systems agent filled the
v3 services and one UI agent built the panel tabs/settings in parallel, each building with its own `--scratch-path` and owning
disjoint folders.

README.md is the owner's short user guide (install = `./build.sh`); keep it brief and put design detail here instead.

Definition of done: `scripts/check.sh` passes on Linux (core build, ≥ 40 unit tests green, every app file passes `swiftc -parse`), two independent compile reviews clean, and on the Mac `./build.sh` produces and launches `DynaNotch.app`.

## 10. Owner decisions (2026-10-16)
1. Rebuild DynaNotch to match Alcove's feature set and feel ("exactly similar").
2. Front-end (SwiftUI island + settings) and back-end (system services) both rewritten; the perl/MediaRemote adapter from v1.x is kept as the Now Playing engine.
3. Build with SwiftPM + `build.sh` instead of the generated `.xcodeproj`.
4. Out of scope for v2: lock-screen widgets, third-party notification mirroring, file shelf.

## 11. Owner decisions (2026-10-26)
(v3.1, later the same day) Apple-designer polish: glass panel, Notchy header with menus, connected-device batteries,
iPhone-style "hello" on first launch. Keep §2c as the living done/due board — update it whenever a feature lands.

1. Build DynaNotch "like Notchy" (notchy.dev): visit the site, take its features, develop, test and fix everything.
2. v3 adds the Notchy panel features listed in §2b (file shelf is now **in** scope); paid/AI/teleprompter/face-unlock features stay out.
3. Network use is limited to free, keyless public APIs (iTunes Search, LRCLIB, Open-Meteo); everything else stays on the Mac.

## 12. Owner decisions (2026-10-26, after v3.2)
1. The floating pill must also be available on the MacBook's notch display (`notchDisplayStyle`, pill floats below the notch).
2. The hello greeting is a pop-up under the notch, not a full-screen takeover.
3. Permissions must survive rebuilds (stable ad-hoc designated requirement in `build.sh`).
4. Settings must be intuitive: follow the Settings UX rules in §2e for every page and every new setting.
5. §2e is the living gap list from the Notchy recording; pick work from it by priority (P1 first) and flip rows to ✅.
