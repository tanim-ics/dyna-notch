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

### Updates

DynaNotch checks GitHub for a new version once a day. When there is one, an **Update** button appears in the panel
header (and "Update to …" in the menu-bar menu). It plays a short story of the new features; **Update Now** downloads
the new version, checks it, swaps the app and restarts it — settings and permissions stay. After an update the new
version shows its What's New story once; replay it from the menu bar or Settings → About, where you can also turn the
daily check off.

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
- **Copy progress**: while Finder copies files, the pill turns into a green progress bar with the name, percent and
  time left (Settings → Popups → File Copies).
- **Smart Copy**: copy "€42", "5 mi", "3pm PST" or "0x1F" and the notch shows it converted; click it to copy the
  result (Settings → Clipboard → Smart Copy).
- **Drop Alchemy**: drop a picture or PDF on the Shelf's zones to cut out the subject, copy its text, shrink it or
  make a PNG — on your Mac, the new file lands next to the original.
- **Camera & mic**: the popup says which app is recording, a small dot stays on while the camera or mic is on, and
  Settings → Popups lists recent use. **Meeting Meter** shows a call timer in the pill and a recap afterwards.
- **Focus**: during a Pomodoro, opening Slack & co. shakes the island and nudges you back; focus sounds (rain,
  brown noise, fireplace) play from the Timer tab and can follow your Pomodoro (Settings → Timer → Focus).
- **Mac Vitals**: a heads-up when your Mac runs hot, memory gets tight, the disk is almost full or an app keeps a
  core busy; click it to open Activity Monitor.
- **Daily Wrap**: at 18:00 on weekdays a card sums up your day — time at the Mac, Pomodoros, commits, your
  most-played song and Claude Code cost (Settings → Activity).
- **Voice Notes**: give "Voice Note" a shortcut (Behavior) or a knock, then say a note, "remind me to …" or
  "timer 10". Recognised on your Mac only.
- **Agent Island**: when Claude Code asks for permission, the notch shows the command with Deny · Terminal · Allow,
  and the pill shows what Claude is doing. Install the hooks once in Settings → AI Usage.
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
- **Island missing on an external display.** Settings → Behavior → Show On → **Every Display** (the default: an island
  on each display; switch single displays off in the list below it) or **Follow Mouse** (one island that moves to the
  display you're using). Also turn on Appearance → "Show on Displays Without a Notch", or the resting pill stays hidden
  there. An app in real full screen hides that display's island (Behavior → Hide in Full Screen).
- **Acting on a popup.** Rest the pointer on a notification to read all of it; it stays until you move away. Click
  **Open** to go where it points (Calendar tab, Downloads, a link from `notify?open=`) or **Dismiss** to close it.
- **Accessibility is on but General still asks for it.** An older build is listed: select DynaNotch in System Settings →
  Privacy & Security → Accessibility, remove it with −, then click Allow… in DynaNotch again.
  It also hides in full-screen apps by default.

## Extras

Send yourself a notch notification from any script, e.g. a Claude Code hook:

```bash
open -g "dynanotch://notify?title=Build&body=Done&symbol=hammer.fill"
```

Add `&open=https://…` to give the popup an **Open** button. Only `notify`, `tab`, `timer` and a few other harmless
links work from outside; see `docs/SECURITY.md`.

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
