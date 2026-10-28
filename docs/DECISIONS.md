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

README.md is the owner's short user guide (install = `./build.sh` or the Homebrew cask); keep it brief and put design detail here instead.

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

## 13. Owner decisions (2026-10-26, Homebrew)
1. Offer a Homebrew install. The repo is its own tap (`Formula/dynanotch.rb`, HEAD-only, builds from source with
   `build.sh --skip-tests --no-install`). Not a cask: casks need a notarised download, which is a non-goal.
2. The adapter dylib's install name is `@rpath/libMediaRemoteAdapter.dylib` and the formula sets `preserve_rpath`;
   otherwise Homebrew rewrites the dylib ID after install, re-signs it and breaks the app bundle's seal.
3. SwiftPM needs `--disable-sandbox` inside Homebrew's sandbox; build.sh takes it from `DYNANOTCH_SWIFTPM_FLAGS`.

## 14. Owner decisions (2026-10-27, lock screen)
1. Lock and unlock sounds plus an unlock island, built on the public `com.apple.screenIsLocked` / `screenIsUnlocked`
   distributed notifications.
2. **The private-SkyLight non-goal is lifted for lock-screen widgets only:** weather and connected-device batteries on
   the lock screen. The window joins a private SkyLight space (`SLSSpaceCreate` / `SLSSpaceSetAbsoluteLevel` /
   `SLSShowSpaces` / `SLSSpaceAddWindowsAndRemoveFromSpaces`, all via `dlopen`/`dlsym`, nil-guarded). Fallback: when a
   symbol is missing or a call fails, nothing is drawn on the lock screen; sounds and the unlock island still work.
   Other private-API features (Face Unlock …) stay out.

## 15. Owner decisions (2026-10-28, Homebrew cask)
1. Homebrew 7 refuses formulas from untrusted taps, so the HEAD-only formula (§13) is replaced by a cask, as Notchy
   ships: `brew install --cask tanim-ics/dyna-notch/dynanotch` (the full name trusts the cask). Supersedes §13.1.
2. The cask downloads `DynaNotch-<version>.zip` from the GitHub release `v<version>`, built by `scripts/release.sh`
   (ad hoc, stable identifier requirement, arm64 — every notched Mac is Apple silicon).
3. Not notarised, so the cask's `postflight_steps` strip `com.apple.quarantine` from the installed app; without it
   Gatekeeper blocks the first launch.
