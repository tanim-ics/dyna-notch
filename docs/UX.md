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
- **Floating pill size** (2026-10-26): the resting pill is **Pill Width** wide (default and minimum = the MacBook's camera
  notch width, 185 pt without a notch; max 420) and **Pill Height** tall (default 36 pt — a little thicker than the 32 pt
  notch; 28–44). Compact activities add their side columns to that width; the corner radius stays capsule-like
  (`min(h/2, bottom + 6)`). The open panel's header row is as tall as the pill (÷ content scale). Sizes are on screen: Closed Pill Size, relabelled
  **Pill Content Size**, now scales only the icons and text inside the pill, never its outline.
- **Show On** (Behavior, menu picker): Built-in · Main · External · Follow Mouse (one island moves to the pointer's display)
  · **Every Display** (2026-10-27): the primary island where Built-in puts it plus one island per other display, each
  in that display's shape (Notch / Floating pill), hovering and opening on its own. Activities and notifications show on
  all of them; sounds and edge glow happen once; shortcuts act on the island under the pointer; Hide hides all.

### Lock screen (2026-10-27, CONTRACTS §6.11)
- **Widgets while locked** (owner feedback 2026-10-27: on the main display, centred under the clock, in the clock's
  typeface, Notchy-style icons): a 760 × 150 pt window on the main display, centred, top at 34 % of the screen height.
  Two cards side by side (white 14 %, 1 pt white 20 % border, 24 pt continuous corners, 112 pt tall, 14 pt apart):
  **weather**: multicolour SF Symbol 40 pt, temperature in SF Pro 40 pt semibold, then "Place · Sky · H … L …" 13 pt
  semibold at 70 % white; **batteries**: up to four 50 pt rings (5 pt stroke, green, red at ≤ 20 %, a bolt on top
  when charging) with the device glyph inside and the level below in 13 pt semibold. All text is SF Pro, white
  92 %, with a soft shadow, like the system clock. A card with no data is left out; no data at all → transparent.
- It appears on lock and disappears on unlock with no animation (the lock screen's own transition covers it).
- **Unlocked popup:** the compact toggle activity with a green open lock on the left and "Unlocked" on the right, for
  the usual short activity time, on every island.
- **Sounds:** Lock = Pop and Unlock = Purr by default. They are listed both on the Lock Screen page and in Popups → Alert
  Sounds.
