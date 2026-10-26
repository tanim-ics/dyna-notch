# DynaNotch quality pass — scorecard (2026-10-26)

Goal: feel and perform like a shipping Mac app; no new features. Measured on the owner's Mac (macOS 27, Apple
silicon), DynaNotch 3.2.0 installed build, 60 s windows with `top` (CPU, idle wake-ups, POWER) after the intro.

## Energy and CPU

| Scenario | Before | After |
|---|---|---|
| Music playing, compact island (lyrics / vinyl / visualiser) | 8.08 % CPU · 22.2 wake-ups/s · energy 9.08 | **0.13 % · 2.6/s · 0.20** |
| Idle, nothing playing | ~2.3 % CPU · ~3.7 wake-ups/s (spikes to 5 %) | **0.13–0.18 % · 2.7–3.6/s · 0.2–0.3** |
| Settings window open after visiting 6 pages | 25.4 wake-ups/s (and climbing per page) | **3.75/s** |
| Memory (RSS) | 146–157 MB | 135–214 MB (not addressed; varies with artwork / Settings) |

Notchy itself was not measured: it is no longer installed on this Mac. Its site claims "~0 % idle CPU"; we are at
0.13–0.18 %. Re-run `scripts/health.sh` next to Notchy once it is reinstalled for a true side-by-side.

## What changed (timers → events)

| Was | Now |
|---|---|
| Visualiser bars + spinning vinyl: SwiftUI `TimelineView(.animation)` at 30 fps | Core Animation layers with repeating animations (render server, no per-frame app work) |
| Lyric line under the notch redrawn 4×/s | Redraws only when the next line starts (`LRCParser.changeDates`, tested) |
| Brightness polled every 0.2 s | Stops while the media-key tap is active; otherwise 0.5 s, coalesced |
| Hover safety poll every 0.2 s, always | 0.2 s only while the pointer is on the island / panel open; 2 s otherwise |
| Downloads folder scanned every 1 s | File-system event source on the folder (+ 30 s safety poll) |
| Camera / mic polled every 1.5 s | CoreAudio + CoreMediaIO "running somewhere" listeners (+ 15 s safety poll) |
| Full-screen window-list scan every 1.5 s | App / Space notifications (+ 10 s safety poll) |
| Caps Lock 0.25 s, clipboard 0.5 s (no system notification exists) | 0.5 s each with tolerance so they wake together; clipboard skips while locked / asleep |
| Settings pages: a `Timer.publish` stored in each view (re-created, kept ticking) | One shared `SettingsTicker`; the window drops its content when closed |

## Bugs found

1. Settings timers leaked per page visited (25 wake-ups/s) — fixed.
2. `scripts/check.sh` could never finish on macOS: bash 3.2 can't parse the inline Info.plist heredoc, and the
   check still expected version 2.0.0 — fixed (`scripts/check_plist.py`, format-based version check, now also
   requires the camera / reminders / location usage strings).
3. Two default shortcuts are taken by another app on this Mac and never registered: ⌃⌥V (Clipboard) and Paste as
   Plain Text — owner action: rebind in Settings → Behavior → Keyboard Shortcuts.
4. Thread Sanitizer and Address Sanitizer runs (all 17 tabs, header cards, 13 activities, timer, palette,
   20 Settings pages): **no data races, no memory errors**.
5. No accessibility labels anywhere — 44 added (every icon-only control) plus a "DynaNotch" container.

## Tests added

- `scripts/ui-regression.sh` — **94 user-level checks** against the running app: every tab opens and renders, battery /
  sound cards open on hover and close on leave, every live activity, palette search + Esc, Hide, every Settings
  page renders. Run with `scripts/check.sh --ui` (or alone).
- `scripts/check.sh` passes end to end on macOS for the first time (build, 224 unit tests, swiftc -parse of 133
  files, adapter, shell syntax, Info.plist, UI regression).
- Core test `testLyricChangeDates`.
- `scripts/health.sh [days]` — crash / hang reports (installed vs test build), log errors, 30 s idle measurement.

## Not done (and why)

- **60 fps motion comparison with Notchy:** screen recording is not permitted from Claude's shell, and Notchy is not
  installed. To do: record both with ⌘⇧5 at 60 fps, same gestures.
- **Live VoiceOver walk-through:** labels are in the code; driving VoiceOver / Accessibility Inspector needs the owner
  (or Accessibility permission for the shell).
- **Dogfood week:** use DynaNotch daily, then run `scripts/health.sh 7` and paste the output back for review.
- Memory (135–214 MB) was not investigated.
