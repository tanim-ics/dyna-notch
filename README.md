# DynaNotch 🏝️

A native **Dynamic Island for macOS**, modelled on [Alcove](https://tryalcove.com/) and [Notchy](https://notchy.dev/).
A black island merges with the MacBook notch (or floats as a pill on displays without one), grows into live activities
with spring animations, and opens into a tabbed panel — music with synced lyrics, timers, clipboard history, a file shelf,
notes, a system monitor and your AI usage — when you hover over it.

Built from source for personal use. Version 3.0.0.

## Features

- **Island that merges with the notch**: fluid spring transitions, concave "ears", fake notch on external or older displays.
- **Hover or click to expand** into a 640 pt tabbed panel with configurable hover delay and a haptic tick.
- **Now Playing** for every app that reports to the system (Spotify, Apple Music, browsers, Podcasts, ...), working on
  macOS 15.4+: artwork, title, artist, live progress, scrubbing, previous / play-pause / next, source app icon.
- **Album-art styles** (rounded or spinning circle) with an artwork-tinted glow.
- **Live audio visualiser** in the compact island, tinted with the artwork colour.
- **Track-change sneak peek**: title and artist drop below the notch for a few seconds.
- **Volume and brightness HUD** that replaces the system HUD (compact or expanded style).
- **Live activities**: charging, low battery, Bluetooth devices (AirPods with battery), Focus mode, upcoming calendar events.
- **Expanded view widgets**: calendar (next events) and battery.
- **Swipe gestures**: two-finger swipe to skip tracks, swipe up to dismiss.
- **Multi-display**: notch screen, main screen, or follow the mouse.
- **Hidden in full-screen apps**, no Dock icon, optional menu-bar icon, launch at login.

### New in v3 (Notchy parity)

- **Tabbed panel**: Home · Now Playing · Timer · Clipboard · Shelf · Notes · System · AI Usage, plus quick toggles
  (Keep Awake, mic mute, pin open, lock screen, settings). Reorder or hide tabs in Settings > Panel.
- **Home**: mini player, month calendar, weather (Open-Meteo, your city or location), running timer, Up Next.
- **Synced lyrics** from LRCLIB in the Now Playing tab (tap a line to jump) and, optionally, the current line under the notch.
  ±15 s skip buttons and an audio output switcher.
- **Timer**: countdown presets (1–25 min) and custom, Pomodoro with breaks, stopwatch; shows live in the notch and chimes when done.
- **Clipboard history**: text, links (tracking parameters stripped), colours, images and files; search, pin, click to paste,
  ⌥-click to paste as plain text. Password-manager copies are ignored.
- **File shelf**: drag files onto the notch to park them, drag them out anywhere, AirDrop or reveal in Finder.
- **Notes & to-dos**, **System monitor** (CPU, memory, network, disk, battery health), **AI usage** (Claude Code 5-hour block,
  today and week; Codex limits — read locally from `~/.claude` and `~/.codex`).
- **More live activities**: timer done, downloads, camera / microphone in use, Caps Lock, mic mute, Keep Awake, and
  notifications you send yourself: `open -g "dynanotch://notify?title=Build&body=Done&symbol=hammer.fill"`.
- **Global hotkeys**: ⌃⌥N toggles the panel, ⌃⌥V opens the clipboard. Esc closes it.

Not included: lock-screen widgets / face unlock, mirroring other apps' notifications, Ask-AI, teleprompter.

## Requirements

- macOS 14 Sonoma or later (macOS 15 Sequoia recommended).
- Xcode 16 (recommended) or the Command Line Tools (`xcode-select --install`). With Command Line Tools only,
  the unit tests may be skipped because XCTest is not available; the app still builds.
- Apple Silicon is the tuned target; Intel Macs should work but are not tested.

## Quick start

```bash
cd ~/Desktop/dyna-notch
./build.sh
```

That single command runs the unit tests, builds the MediaRemote adapter and the app, assembles and signs
`build/DynaNotch.app`, creates `DynaNotch.dmg`, installs the app to `/Applications` (or `~/Applications`) and
launches it. Look for the island at the top of the screen and the DynaNotch icon in the menu bar.

Options:

| Flag | Effect |
|---|---|
| `--no-install` | Build only; do not install or launch |
| `--no-dmg` | Skip the DMG |
| `--debug` | Debug configuration (faster compile, slower app) |
| `--skip-tests` | Skip `swift test` |
| `--help` | Show usage |

Signing: `build.sh` uses `$SIGN_IDENTITY` if set, otherwise the first "Apple Development" certificate in your
keychain, otherwise ad-hoc signing. `./build_dmg.sh` still works and simply calls `./build.sh`.

## First-run permissions

| Permission | Why | Where |
|---|---|---|
| **Accessibility** | Lets the volume / brightness HUD intercept media keys and replace the system HUD. Without it DynaNotch only observes changes. | System Settings > Privacy & Security > Accessibility |
| **Calendar** | Upcoming events in the expanded view and the "event in 5 min" activity. Prompted on first launch. | System Settings > Privacy & Security > Calendars |
| **Bluetooth** | AirPods and other device connect / battery activities. Prompted on first use. | System Settings > Privacy & Security > Bluetooth |
| **Full Disk Access** (optional) | The Focus activity reads the Focus state from `~/Library/DoNotDisturb`. | System Settings > Privacy & Security > Full Disk Access |
| **Location** (optional) | Weather for where you are. Type a city in Settings > Weather & AI instead to skip it. | System Settings > Privacy & Security > Location Services |
| **Downloads folder** (optional) | The download activity watches `~/Downloads` for browser downloads. Turn it off in Settings > Live Activities. | Prompted on first use |

Accessibility also enables **click to paste** from the clipboard history.

After granting Accessibility, quit DynaNotch from the menu-bar icon and open it again if the HUD does not take over.

## Gestures

| Gesture | Action |
|---|---|
| Hover over the island | Expand (after the hover delay) |
| Move the pointer away | Collapse |
| Click | Toggle expanded |
| Click outside the island | Collapse |
| Two-finger swipe left | Next track |
| Two-finger swipe right | Previous track |
| Two-finger swipe up | Dismiss the current activity / collapse |
| Drag the progress bar | Scrub |
| Drag files to the notch | Open the Shelf and drop them |
| ⌃⌥N / ⌃⌥V | Toggle the panel / open Clipboard |
| Esc | Close the panel |

All of these can be tuned or disabled in Settings > Island.

## Menu bar

The menu-bar icon offers **Toggle Island**, **Settings...** (Cmd-,), **Simulate** and **Quit DynaNotch**.
**Simulate** triggers every activity on demand so you can see them without plugging things in:
Volume HUD, Brightness HUD, Charging, Low Battery, AirPods Connected, Focus On, Upcoming Event, Track Peek, Timer,
Lyrics, Notification, Download, Camera In Use and Caps Lock. **Keep Awake** toggles caffeinate mode.

### URL scheme

| URL | Effect |
|---|---|
| `dynanotch://notify?title=…&body=…&symbol=…&duration=…` | Show a notification island (SF Symbol name, 1–30 s) |
| `dynanotch://tab/<home\|nowPlaying\|timer\|clipboard\|shelf\|notes\|system\|aiUsage>` | Open the panel on a tab |
| `dynanotch://timer/<minutes>` | Start a countdown |
| `dynanotch://expand`, `collapse`, `settings`, `simulate/<demo>`, `snapshot/<name>` | Scripting / debugging |

Claude Code hook example (`~/.claude/settings.json` → `hooks.Stop`):
`open -g "dynanotch://notify?title=Claude%20Code&body=Finished&symbol=sparkles"`.

The menu-bar icon can be hidden in Settings > General. To get it back, open DynaNotch again from `/Applications`;
the settings window appears.

## Troubleshooting

**Now Playing stays empty.**
Start some music, then watch the logs:

```bash
log stream --predicate 'subsystem == "com.tanim.dynanotch"' --level debug
```

Adapter errors show up there (for example the MediaRemote framework could not be loaded). Make sure the adapter
was compiled (look for "Building MediaRemote adapter ... OK" in the `./build.sh` output; the log is at
`build/logs/adapter.log`). If compilation failed, `build.sh` falls back to the prebuilt
`Packaging/libMediaRemoteAdapter.dylib`; installing the Command Line Tools (`xcode-select --install`) and rebuilding
usually fixes it. DynaNotch falls back to AppleScript for Music and Spotify if MediaRemote is unavailable.

**The build fails with strange module or cache errors.**
Clear the SwiftPM cache and rebuild:

```bash
rm -rf .build build
./build.sh
```

Full logs for every step are in `build/logs/`.

**macOS asks for Accessibility again after every rebuild.**
With ad-hoc signing every build has a new signature, so macOS treats it as a different app. In
System Settings > Privacy & Security > Accessibility, select the old DynaNotch entry, remove it with the "–" button,
then add or enable the new one. To avoid this permanently, create a free "Apple Development" certificate
(Xcode > Settings > Accounts > your Apple ID > Manage Certificates > +). `build.sh` picks it up automatically.

**The island is not visible on an external display.**
Settings > General > "Show island on": choose "Main display" or "Follow mouse". Also check that
"Show on displays without a notch" is on.

**The island disappears.**
It hides in full-screen apps by default (Settings > General > "Hide in full screen apps").

**"DynaNotch is damaged" or Gatekeeper warnings when opening the DMG on another Mac.**
The app is not notarised. Run `xattr -dr com.apple.quarantine /Applications/DynaNotch.app`.

## Architecture

Two Swift targets plus a small Objective-C helper:

- **DynaNotchCore** (Foundation only, unit-tested on macOS and Linux): the island state machine (`IslandEngine`),
  layout and geometry, Now Playing / Focus / calendar parsers, power-event detection, formatting.
- **DynaNotch** (AppKit + SwiftUI): system services publish events into `IslandViewModel`, which drives a SwiftUI
  island hosted in a single fixed-size, transparent, click-through `NSPanel` pinned to the top of the screen.
- **MediaRemote adapter** (`Adapter/MediaRemoteAdapter.m`): since macOS 15.4 third-party apps can no longer read
  Now Playing directly, so this dylib is loaded into Apple's signed `/usr/bin/perl`, which still can. It streams JSON
  lines on stdout and accepts commands on stdin.

See [CLAUDE.md](CLAUDE.md) for the full design, contracts and conventions.

## Project layout

```
dyna-notch/
├─ Package.swift                 # SwiftPM: DynaNotchCore, DynaNotch (macOS), DynaNotchCoreTests
├─ build.sh                      # test, build, bundle, sign, DMG, install, launch
├─ build_dmg.sh                  # alias for build.sh
├─ Adapter/MediaRemoteAdapter.m  # Now Playing helper loaded into /usr/bin/perl
├─ Packaging/
│  ├─ Info.plist                 # app Info.plist (literal values)
│  ├─ libMediaRemoteAdapter.dylib  # prebuilt fallback adapter
│  └─ make_icon.swift            # renders the app icon at build time
├─ Sources/
│  ├─ DynaNotchCore/             # pure logic
│  └─ DynaNotch/                 # App, Window, Model, Services, Views
├─ Tests/DynaNotchCoreTests/
├─ scripts/check.sh              # fast checks (Linux and macOS)
└─ CLAUDE.md                     # design document
```

## Development

| Command | Purpose |
|---|---|
| `./build.sh` | Everything: test, build, bundle, sign, DMG, install, launch |
| `./build.sh --no-install --no-dmg` | Just produce `build/DynaNotch.app` |
| `swift build` | Compile only |
| `swift test` | Run the core unit tests |
| `scripts/check.sh` | Build + tests + syntax checks of every source, script and the Info.plist |
| `open Package.swift` | Work in Xcode (run the `DynaNotch` scheme; note it runs outside an app bundle) |
| `log stream --predicate 'subsystem == "com.tanim.dynanotch"' --level debug` | Live logs |

Build outputs (`.build/`, `build/`, `DynaNotch.dmg`) are git-ignored.

© 2026 Tanim Rayhan
