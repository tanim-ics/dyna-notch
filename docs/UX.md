# DynaNotch — UX spec

> Moved out of CLAUDE.md on 2026-10-26 (verbatim). CLAUDE.md links here; update this file when the facts change.

## 7. UX spec
- **Idle**: invisible on notch Macs (black on black). Non-notch: fake notch (toggle). Hover: island grows slightly (`scaleEffect 1.06`, top anchor) before expanding.
- **Compact Now Playing**: artwork (22 pt, style-aware) left, visualiser right (tinted with artwork accent), only while playing or within `pausedLingerSeconds` after pause.
- **Peek**: on track change, show title (semibold 13) + artist (11, 60 % white) under the notch row for 2.8 s.
- **HUD compact**: left icon (speaker.wave.N / speaker.slash / sun.max), right slim bar + percent. **HUD expanded style**: icon · bar · percent in a row below the notch.
- **Charging**: bolt + "Charging"/"On battery" left, percent + battery glyph (green / red ≤ 20 %) right.
- **Bluetooth**: device symbol left, name or battery % right ("Connected"/"Disconnected").
- **Focus**: mode symbol left, "On"/"Off" right (tinted indigo).
- **Calendar**: calendar glyph left, "in 5 min" right; peek-like title row.
- **Expanded (600 × ~190)**: header row inside the notch height: left app badge/title "Now Playing", right gear (opens settings) — kept clear of the physical notch. Body: Now-Playing card (artwork 92 pt with glow, title, artist, scrubbable progress with times, prev · play/pause · next, source app icon) + right column (date, next ≤ 3 events, battery level). Empty state: "Nothing playing" with a music.note glyph.
- Motion: springs, content transitions `.opacity.combined(with: .scale(scale: 0.92, anchor: .top))` + slight blur; respect `accessibilityReduceMotion` (use `.easeInOut(0.2)` instead).
- Every interaction ≤ 1 gesture; no modal alerts.
- **v3 panel (640 × notch.h + 190)**: header row inside the notch height — tab icons left of the notch (selected = white 12 % capsule),
  quick toggles right (Keep Awake, mic, pin, lock, settings). Tabs: Home (mini player, month calendar, weather, timer, Up Next) ·
  Now Playing (player + ±15 s + output menu | synced lyrics auto-scrolling, tap a line to seek) · Timer (Standard presets 1/2/3/5/10/25 +
  custom, Pomodoro with session dots, Stopwatch) · Clipboard (search, rows with kind icon / thumbnail, pin, delete; click pastes,
  ⌥-click pastes plain text) · Shelf (drop files anywhere on the island, drag out, AirDrop, reveal) · Notes (scratch text + to-dos) ·
  System (CPU sparkline, memory, network, disk, battery health) · AI Usage (Claude 5 h block / today / week; Codex limits).
- **Compact timer**: ring + remaining time (orange countdown, green break, blue stopwatch). **Lyrics**: compact now-playing row plus the
  current lyric line under the notch. **Notification** activity: peek-like title/body under the notch.
- Dragging files towards the notch opens the panel on the Shelf tab. Esc closes the panel; a pinned panel ignores mouse-leave and outside
  clicks. ⌃⌥N toggles the panel, ⌃⌥V opens Clipboard (both focus the panel for typing).
