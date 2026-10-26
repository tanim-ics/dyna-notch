# DynaNotch 🏝️

A Dynamic Island for your Mac's notch, inspired by [Alcove](https://tryalcove.com/) and [Notchy](https://notchy.dev/).
Hover over the notch to open a panel with your music, timers, clipboard, files, notes and more.

## Install

You need macOS 14 or later and Xcode (or the Command Line Tools: `xcode-select --install`).

```bash
cd ~/Desktop/dyna-notch
./build.sh
```

That's it: it tests, builds, installs DynaNotch to `/Applications` and starts it.
Run the same command again to update after pulling changes.

Want a DMG to copy to another Mac? Use `./build.sh --dmg`.

## What it does

- **Now Playing** from any app (Spotify, Apple Music, browsers…): artwork, controls, scrubbing and **synced lyrics**.
- **Volume & brightness HUDs** that replace the big grey system ones.
- **Live activities**: charging, low battery, AirPods, Focus, upcoming events, downloads, camera/mic in use, Caps Lock.
- **Panel tabs**: Home · Now Playing · Timer · Clipboard · Shelf · Notes · System · AI Usage.
  - **Timer**: quick countdowns, Pomodoro, stopwatch, shown live in the notch.
  - **Clipboard**: history you can search; click an item to paste it.
  - **Shelf**: drag files onto the notch, drag them out later.
  - **AI Usage**: your Claude Code and Codex usage, read from local files.
- **Quick buttons**: battery pill (your Mac, AirPods, mouse and keyboard batteries), sound output, Keep Awake,
  actions menu (stopwatch, Pomodoro, screenshot, colour picker, mute mic), pin open, lock screen.
- **Glass panel** that blurs your desktop (or plain black: Settings → Panel), and an iPhone-style *hello* on first launch.

## Using it

| Do this | To |
|---|---|
| Hover over the notch | Open the panel |
| Move away / press Esc | Close it |
| Drag files to the notch | Put them on the Shelf |
| Two-finger swipe ← / → | Next / previous track |
| ⌃⌥N | Open or close the panel |
| ⌃⌥V | Open the clipboard |
| ⌘1 – ⌘9 | Switch tabs while the panel is open |

Settings, **Keep Awake** and **Simulate** (preview every activity) are in the menu-bar icon.

## Permissions

macOS asks the first time a feature needs something. Only one needs a manual step:

- **Accessibility**: needed for the volume/brightness HUD and click-to-paste.
  Turn on DynaNotch in System Settings → Privacy & Security → Accessibility, then quit and reopen DynaNotch.

Optional: **Calendar** (events), **Location** (weather; or type a city in Settings), **Full Disk Access** (Focus activity).

## Troubleshooting

- **Accessibility keeps resetting after rebuilds.** In the Accessibility list remove the old DynaNotch with "–" and
  add it again. To fix it for good, create a free "Apple Development" certificate in Xcode → Settings → Accounts;
  `build.sh` uses it automatically.
- **Build fails with odd cache errors.** Run `rm -rf .build build && ./build.sh`. Logs are in `build/logs/`.
- **No music showing.** Play something, then check `log stream --predicate 'subsystem == "com.tanim.dynanotch"'`.
- **Island missing on an external display.** Settings → General → "Show island on" → Main display or Follow mouse.
  It also hides in full-screen apps by default.

## Extras

Send yourself a notch notification from any script, e.g. a Claude Code hook:

```bash
open -g "dynanotch://notify?title=Build&body=Done&symbol=hammer.fill"
```

Other URLs: `dynanotch://tab/<name>`, `dynanotch://timer/<minutes>`, `dynanotch://timer/stop`.

## Uninstall

Quit DynaNotch from the menu-bar icon, then:

```bash
rm -rf /Applications/DynaNotch.app ~/Library/Application\ Support/DynaNotch
defaults delete com.tanim.dynanotch
```

## For developers

`swift build` compiles, `swift test` runs the unit tests, `scripts/check.sh` runs every check.
Design, architecture and conventions are in [CLAUDE.md](CLAUDE.md).

© 2026 Tanim Rayhan
