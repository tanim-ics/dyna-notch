# DynaNotch 🏝️

A Dynamic Island for your Mac's notch, inspired by [Alcove](https://tryalcove.com/) and [Notchy](https://notchy.dev/).
Hover over the notch to open a panel with your music, timers, clipboard, files, notes and more.

## Install

You need macOS 14 or later on an Apple-silicon Mac (Xcode 16 or later only to build from source). Pick one of the two ways below.

### With Homebrew

```bash
brew tap tanim-ics/dyna-notch https://github.com/tanim-ics/dyna-notch.git
brew install --cask tanim-ics/dyna-notch/dynanotch
open -a DynaNotch
```

This downloads the ready-built app into `/Applications` (no Xcode needed). Update with
`brew upgrade --cask dynanotch`. Use the full name `tanim-ics/dyna-notch/dynanotch` the first time: Homebrew only
loads casks from taps you have trusted, and naming it in full trusts it.

DynaNotch is not notarised by Apple, so the cask removes the download quarantine after installing; otherwise macOS
refuses to open it.

### From the source folder

```bash
cd ~/Desktop/dyna-notch
./build.sh
```

That's it: it tests, builds, installs DynaNotch to `/Applications` and starts it.
Run the same command again to update after pulling changes.

Want a DMG to copy to another Mac? Use `./build.sh --dmg`.

Use only one of the two ways at a time, so there is a single DynaNotch in `/Applications`.

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
- **Floating pill** instead of the notch shape if you prefer (Settings → Appearance): set its width (never narrower than
  the MacBook's notch) and height with the Pill Width / Pill Height sliders.
- **Lock screen** (Settings → Lock Screen): weather and battery widgets under the clock on your main display while the
  Mac is locked, a sound when you lock and unlock, and an *Unlocked* popup when you come back. The lock-screen widgets use
  a private macOS feature, so a macOS update may switch it off; the sounds and popup keep working.
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

- **A permission keeps asking again after rebuilds.** Builds since v3.2 keep a stable code identity, so grants survive
  rebuilds. If an old grant is stuck, remove DynaNotch from that list in System Settings → Privacy & Security
  (or run `tccutil reset Calendar com.tanim.dynanotch`) and allow it once more.
- **Build fails with odd cache errors.** Run `rm -rf .build build && ./build.sh`. Logs are in `build/logs/`.
- **No music showing.** Play something, then check `log stream --predicate 'subsystem == "com.tanim.dynanotch"'`.
- **Island missing on an external display.** Settings → Behavior → Show On → **Every Display** (an island on each
  display) or **Follow Mouse** (one island that moves to the display you're using). Also turn on Appearance → "Show on
  Displays Without a Notch", or the resting pill stays hidden there.
- **Accessibility is on but General still asks for it.** An older build is listed: select DynaNotch in System Settings →
  Privacy & Security → Accessibility, remove it with −, then click Allow… in DynaNotch again.
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

If you installed with Homebrew, also run `brew uninstall --cask dynanotch && brew untap tanim-ics/dyna-notch`.

## For developers

`swift build` compiles, `swift test` runs the unit tests, `scripts/check.sh` runs every check.
Design, architecture and conventions are in [CLAUDE.md](CLAUDE.md).

© 2026 Tanim Rayhan
