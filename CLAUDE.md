# CLAUDE.md — DynaNotch 🏝️

> A native **Dynamic Island for macOS**, modelled on [Alcove](https://tryalcove.com/) (v2) and
> [Notchy](https://notchy.dev/) (v3: the tabbed notch panel — music + lyrics, timers, clipboard, shelf, notes, system, AI usage).
> Personal use: built from source on the owner's Mac (Apple Silicon, macOS 15 Sequoia+, Xcode 16+).
> **Status: v3.4 (§2e P2) built and user-tested 2026-10-26 on top of v3–v3.3.** This file is the single source of truth.
> Contracts in §6 are binding: if you need to change one, change it here first.

---

## 1. Product goals

1. **Feel like Alcove**: a black island that merges with the hardware notch, grows with fluid spring animations into live activities, and opens into a rich panel on hover.
2. **Now Playing that works on macOS 15.4+** for every app that reports to the system (Spotify, Apple Music, browsers, YouTube Music PWA, Podcasts …), with artwork, live progress, scrubbing and controls.
3. **Replace the system HUDs** for volume and brightness with notch HUDs.
4. **Live Activities** for charging, low battery, Bluetooth devices (AirPods …), Focus, and upcoming calendar events.
5. **Never get in the way**: click-through everywhere except the island itself, hidden in full-screen apps, zero Dock icon, low CPU.

6. **Be a whole notch workspace like Notchy** (v3): a tabbed panel — Home, Now Playing (+ synced lyrics, output switcher),
   Timer (countdown / Pomodoro / stopwatch), Clipboard history, File shelf, Notes & To-Do, System monitor, AI usage — plus
   quick toggles (Keep Awake, mic mute, pin, lock screen) and a global hotkey.

Non-goals: Lock-screen widgets / Face Unlock (private SkyLight APIs), mirroring other apps' notifications (no public API — we
offer a `dynanotch://notify` URL instead), Ask-AI / teleprompter / terminal / HomeKit, App Store/notarised distribution,
Intel-specific tuning, licensing/trial.

---

## 2. Alcove feature parity (reference: tryalcove.com, reviews checked 2026-10-16)

| Alcove feature | DynaNotch v2 | Notes |
|---|---|---|
| Island merges with notch, fluid transitions | ✅ | `NotchShape` with concave "ears", spring animations, fake notch on non-notch displays |
| Hover / click to expand | ✅ | configurable hover delay, haptic tick |
| Now Playing (art, title, artist, controls, progress) | ✅ | MediaRemote via `/usr/bin/perl` adapter; AppleScript fallback |
| Multiple album-art styles, artwork-tinted glow | ✅ | rounded / circle (spins while playing); glow from artwork colour |
| Live audio visualiser in compact island | ✅ | animated bars tinted with artwork colour |
| Track-change "sneak peek" | ✅ | title/artist drops below the notch for ~2.8 s |
| Scrubbing | ✅ | drag the progress bar (sends `seek`) |
| Volume / brightness HUD replacing system HUD | ✅ | CGEventTap on media keys (needs Accessibility); observe-only fallback |
| HUD styles | ✅ | compact (sideways) / expanded (bar below notch) |
| Charging & low-battery activities | ✅ | IOPowerSources |
| Bluetooth device activity (AirPods battery) | ✅ | IOBluetooth connect/disconnect, battery when exposed |
| Focus activity | ✅ (best-effort) | reads `~/Library/DoNotDisturb/DB/*.json`; needs Full Disk Access |
| Calendar (expanded view + upcoming-event activity) | ✅ | EventKit |
| Battery widget in expanded view | ✅ | |
| Swipe gestures | ✅ | 2-finger swipe ←/→ skips track, ↑ dismisses / collapses |
| Multi-display | ✅ | notch screen, main screen, or follow mouse |
| Hide in full screen | ✅ | |
| Launch at login, menu-bar icon toggle | ✅ | SMAppService |
| Lock-screen widgets | ❌ | out of scope (private APIs) |

### 2b. Notchy feature parity (reference: notchy.dev/features + /demo, checked 2026-10-26)

Notchy lists 131 feature guides; we take the ones that belong in a notch and need no private/paid services.

| Notchy feature | DynaNotch v3 | Notes |
|---|---|---|
| Tabbed panel (Home, ⋯ tabs, quick toggles) | ✅ | tab icons left of the notch, toggles right; last tab remembered |
| Home tab: music, weather, timer, month calendar, Up Next | ✅ | |
| Now Playing + **synced lyrics** (LRCLIB) | ✅ | lyrics tab view + optional lyric line under the notch (`.lyrics` presentation) |
| Podcast ±15 s skips, playback speed | ✅ (skips) | seek ±15 s buttons; speed not exposed by MediaRemote adapter → skipped |
| Audio output switcher | ✅ | CoreAudio default output device menu |
| Focus timer: countdown presets, custom, Pomodoro, stopwatch | ✅ | compact `.timer` presentation while running, finished activity + sound |
| Clipboard history (search, pin, images, colours, links) | ✅ | NSPasteboard polling 0.5 s; concealed/transient types ignored |
| Clean links (strip tracking params) | ✅ | `LinkCleaner` |
| Paste as plain text / paste on click | ✅ | click = copy + ⌘V into frontmost app (needs Accessibility) |
| File drop shelf, drag out, AirDrop | ✅ | drag files onto the island → Shelf tab; `NSSharingService` AirDrop |
| Quick notes + To-Do list | ✅ | UserDefaults (JSON) |
| System monitor (CPU, memory, network, disk) | ✅ | host_statistics, getifaddrs, volume capacity |
| Battery health (cycles, capacity) | ✅ | AppleSmartBattery registry, shown in System tab |
| AI usage: Claude Code 5-hour block / today / week, Codex limits | ✅ | parses `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions/**/rollout-*.jsonl` locally |
| Long-command / Claude Code notification islands | ✅ | `open -g "dynanotch://notify?title=…&body=…&symbol=…"` (works from hooks) |
| Weather | ✅ | Open-Meteo (no key); location = city setting or CoreLocation |
| Keep Awake | ✅ | IOPMAssertion toggle |
| Mic mute + Caps Lock indicator | ✅ | CoreAudio input mute; modifier-flag polling (no permission) |
| Camera / mic in-use guard | ✅ | CoreMediaIO / CoreAudio "running somewhere" → privacy activity |
| Download progress | ✅ (start/finish) | watches ~/Downloads for .download/.crdownload/.part |
| Lock screen button | ✅ | `SACLockScreenImmediate` (dlopen) → fallback `pmset displaysleepnow` |
| Pill shape on non-notch displays | ✅ | `NonNotchStyle.pill` floats a capsule 6 pt below the top edge |
| Global hotkey | ✅ | ⌃⌥N toggles panel, ⌃⌥V opens Clipboard (Carbon `RegisterEventHotKey`, no permission) |
| Notification mirroring, Face Unlock, lock-screen widgets, Ask AI, teleprompter, terminal, HomeKit, stocks | ❌ | out of scope |


### 2c. Notchy status board — done vs due (updated 2026-10-26 from the owner's Notchy screenshots)

Notchy's panel header: **current-tab pill + "⋯" tab menu (⌘1–⌘9)** on the left; on the right a **battery pill** (opens a
device-battery popover: Mac with health · cycles · °C, mouse, keyboard, AirPods), timer, camera mirror, volume/output,
keep awake, **"⋯" actions menu**, pin, lock. Expanded panel = translucent **glass**. First launch = onboarding tip cards
(icon, title, text, page dots, Skip · ‹ · Next).

| Area | Notchy feature | DynaNotch | Notes |
|---|---|---|---|
| Panel | Tab pill + ⋯ tab menu with ⌘1–⌘9 | ✅ v3.1 | replaces the row of 8 tab icons |
| Panel | Glass (translucent, blurred) expanded panel | ✅ v3.1 | `IslandMaterial` .glass (default) / .black; compact island stays black to merge with the notch |
| Panel | Battery pill + device-battery popover | ✅ v3.1 | Mac (health, cycles, temperature) + Bluetooth devices (AirPods L/R/case, mice, keyboards) |
| Panel | ⋯ actions: Start/Reset Stopwatch, Start Pomodoro, Capture Screenshot, Pick a Color, Mute Microphone | ✅ v3.1 | screenshot = `screencapture -i -c` (area → clipboard); colour = `NSColorSampler` → clipboard |
| Panel | Volume / output quick button | ✅ v3.1 | output-device menu in the header |
| Onboarding | First-launch "hello" + tip cards | ✅ v3.1 | iPhone-style handwritten *hello* (stroke animation), then Notchy-style tips under the notch |
| Tabs | Home, Now Playing (+lyrics), Timer, Shelf, Clipboard, Notes (+To-Do), AI Usage, System ("Activity") | ✅ v3 | |
| Tabs | Calendar (full month + events) | 🟡 partial | month + Up Next live on Home; no dedicated tab |
| Tabs | Focus | 🟡 partial | Focus *activity* only; switching Focus needs Shortcuts |
| Tabs | Calculator, Emoji, Quick Search, Translate, Launcher | ✅ v3.2 | Translate = Quick Search engine `tr` |
| Tabs | Reminders | ✅ v3.2 | EventKit reminders |
| Tabs | Shortcuts | ✅ v3.2 | `shortcuts list/run` CLI |
| Tabs | Mirror (camera preview) | ✅ v3.2 | AVFoundation; own camera use doesn't trigger the privacy activity |
| Tabs | Apps & Updates, Stocks, Notifications, Terminal, Cuely (teleprompter) | ❌ out of scope | private APIs, paid data or non-goals (§1) |
| Tabs | Home Controls | ⏳ due (§2e P3) | not HomeKit: Notchy filters Apple Shortcuts — reuse ShortcutsService |
| Actions | Record Whole Screen / Record Area | ⏳ due | `screencapture -v` / ScreenCaptureKit |
| Actions | Identify Song, Clean Keyboard, Clean Screen | ⏳ due | ShazamKit needs entitlement; keyboard lock needs event tap |
| Other | Ask About the Screen, Extra Brightness (XDR) | ❌ out of scope | |
| Other | Desktop widgets | ⏳ due (§2e P3) | desktop-level `NSPanel`s — public API, so no longer out of scope |


### 2d. Notchy settings audit + to-do list (from the owner's screen recording, 2026-10-26)

Notchy's Settings window: sidebar with a search field and grouped, colour-iconed pages — **General · Appearance ·
Behavior · Popups · Calls & Messages · All Tools** | Notch: **Tabs · Home · Lock Screen · Knock** | Media & Info: **Now
Playing · Calendar · Stocks · Activity · AI Usage** | Productivity: **Timer · Clipboard · Quick Search · Files & Utilities ·
Screenshots · Cuely · Terminal** | Desktop: **Windows & Spaces · Pointer · Typing Sounds · Desktop Pet** | Your Mac: **Face
Unlock · Displays · Battery & Fans · Connectivity · Caffeine** | System: **License · Permissions · About**. Every page ends
with "Restore Defaults".

Legend: ✅ done (v3.2 shipped 2026-10-26) · ⏳ later · ❌ out of scope.

| Page | Notchy setting / feature | Status |
|---|---|---|
| Settings window | Grouped sidebar with coloured icons + search, Restore Defaults per page | ✅ |
| General | Open at Login | ✅ |
| General | Hello Intro toggle + ▶ replay | ✅ |
| General | Time format System / 12-hour / 24-hour | ✅ |
| General | Menu-bar items per tool, Hide Menu Bar Icons, Language picker | ⏳ |
| General | Recovery: Emergency Shortcut, Restart, Force Quit | ✅ Restart DynaNotch; rest ⏳ |
| Appearance | Pill vs Notch shape per display | 🟡 one global non-notch style ✅; per display ⏳ |
| Appearance | Glass Surfaces + Panel Translucency slider | ✅ |
| Appearance | Material presets: Graphite, Onyx, Carbon, Frost, Satin, Mist, Clear | ✅ |
| Appearance | Clock on the closed pill (non-notch displays) | ✅ |
| Appearance | Panel width, Fixed / Fit content, max height | ⏳ |
| Appearance | Monochrome interface, Color-coded levels, panel font / text size | ✅ colour-coded levels; rest ⏳ |
| Appearance | Animation style Calm / Snappy / Bouncy + speed, Reduce Motion, Haptics | ✅ |
| Appearance | Notifications-only mode, Minimal layout | ⏳ |
| Behavior | Expand on hover ✅ · Default tab (Previous / fixed) · Open on current activity · Auto-collapse delay ✅ · Idle timeout | ✅ |
| Behavior | Show on All / Built-in / Main / External ✅ (3 modes) · Invisible until hover · Hide in full screen ✅ | ✅ |
| Behavior | Keyboard shortcuts per tab, recorder UI | ⏳ (fixed ⌃⌥N / ⌃⌥V ✅) |
| Popups | Notification duration slider · Volume / Brightness / Caps Lock / Focus popups ✅ · Camera guard ✅ | ✅ |
| Popups | Focus-mode shortcuts, per-category alert sounds | ⏳ |
| Calls & Messages | Call controls, meeting calls, iMessage, mirror app notifications | ❌ (no public API) |
| Tabs | Enable/reorder tabs ✅ · favourites · tab labels · header-button toggles | ✅ header-button toggles; favourites / labels ⏳ |
| Tabs | **Calculator, Emoji, Quick Search, Launcher, Shortcuts, Reminders, Mirror (camera)** | ✅ |
| Tabs | Translate | ✅ as a Quick Search engine (`tr`, Google Translate) |
| Tabs | Stocks, Home Controls, Apps & Updates, Terminal, Cuely, Notifications | ❌ |
| Home | Card grid editor (columns, add/remove cards) | ⏳ |
| Home | Weather city / location ✅ · Saved links · Colour tools (pick + format + history) | ✅ colour format + history; saved links ⏳ |
| Lock Screen / Knock / Face Unlock / Pointer / Typing Sounds / Desktop Pet | | ❌ |
| Now Playing | Island ✅ · peek on hover · synced lyrics ✅ · lyrics timing offset · lyrics on pill ✅ | ✅ lyrics offset; peek on hover ⏳ |
| Calendar | Lead time ✅ · **Full-screen meeting alert with Join button** · keep until joined | ✅ (alert once per event, Join / Dismiss) |
| Activity | Screen Time (time per app today) | ✅ System tab rail |
| Activity | Click / keystroke / mouse-distance tracking, rings | ⏳ |
| AI Usage | Tab ✅ · compact layout · agent permission islands (Claude Code hooks) | ⏳ |
| Timer | Presets ✅ · Pomodoro lengths ✅ · Continue automatically · Pomodoro stats (today / streak / total) | ✅ |
| Timer | **Break reminders: Look away (20-20-20), Stand up, Drink water** | ✅ |
| Timer | Focus sounds, distraction blocking, mascot | ⏳ |
| Clipboard | History limit 40/100/200/500 · keep after quit ✅ · ignored apps (password managers) · paste with 1–9 · auto-clear | ✅ |
| Quick Search | Built-in engines (Google, DuckDuckGo, Bing, Perplexity, YouTube, GitHub, Wikipedia, Maps, Amazon) + shortcuts (`gh foo`) + custom engines | ✅ built-ins + shortcuts; custom engines ⏳ |
| Files & Utilities | Download finished ✅ · drive mounted (eject) · long-command islands (via notify URL ✅) | ✅ |
| Screenshots | Capture area ✅ · screenshot to shelf | ✅ |
| Windows & Spaces | Snap windows to the notch, space change island | ⏳ |
| Battery & Fans | Status / health / cycles / temperature ✅ · **battery history chart (24 h / 7 d)** · low-battery threshold · full-charge island | ✅ |
| Battery & Fans | Charge limit, fan control, low power mode | ❌ (needs root helper) |
| Connectivity | Device batteries ✅ · **accessory low / fully charged alerts** · connect alerts ✅ | ✅ |
| Permissions | One page listing every permission with status + "Open System Settings" | ✅ |
| About | Version · **Export / Import settings** · Reset all settings · Replay feature tour ✅ | ✅ |
| License | Trial / purchase | ❌ (personal build) |


### 2e. Notchy recording audit #2 — full gap list (2026-10-26, 32 sidebar pages, 209 s recording)

Source: `notchy screen recording.mov` in the repo root (Notchy 2.0.0 Settings, every page). This table lists what §2b–§2d
did **not** already cover, plus bugs the owner reported. Priority: **P1** = next round (cheap, high value, public API),
**P2** = after that, **P3** = nice-to-have. ✅ = done, ⏳ = due, ❌ = out of scope (reason given).

**Owner-reported bugs (2026-10-26)** — all ✅ this round:
| Bug | Fix |
|---|---|
| ⋯ tab menu showed "⌃⌥⇧⌘ Space" for tabs 10+ | ✅ only tabs 1–9 get ⌘-numbers; the rest are listed after a divider with no shortcut |
| Floating pill unavailable on the MacBook (notch) display | ✅ new `notchDisplayStyle` (Notch / Floating pill): the pill floats just below the camera notch; visual shape picker in Appearance |
| Calendar (and every permission) asked again on each launch | ✅ ad-hoc signature had a cdhash requirement that changed every build; `build.sh` now signs with `designated => identifier "com.tanim.dynanotch"` |
| Hello was a full-screen takeover | ✅ now an island pop-up that grows out of the notch (hello → welcome → tips) and shrinks back |
| Settings hard to scan | ✅ Notchy-style rows: page subtitle, icon + title + description per row, dimmed dependants, −/+ sliders, Suggestions card, Restore… per page |
| Tab menu items Launcher…System did nothing | ✅ those items sit below the panel, so picking one left the pointer outside and the panel collapsed (and "open on current activity" then reset the tab). The panel now holds while its menus track + 3 s grace until the pointer returns; a tab you picked wins over "open on current activity" for 10 min |
| Pill / Notch choice only applied after relaunch | ✅ the window controller observes both shape settings and re-applies + repositions at once (verified by clicking the real Settings card) |
| Settings content overlapped the title bar | ✅ standard (non-transparent) title bar; page header scrolls inside the Form |

**v3.4 (P2) status (2026-10-26):** every P2 row below is ✅ except tab labels / favourites, saved clipboard lists +
snippets, the accessory battery sparkline and a separate clock date-format picker (⏳). Notes in the Status column say
what could not be tested live. Owner-visible fixes found in the integration pass: palette listed two identical "Open
Calendar" rows (the Calendar.app action is now "Open Calendar App"), keyboard-opened panels collapsed after any settings
write, Esc in the palette/Settings collapsed the island.

**Settings UX rules (binding for every new setting):** page = large title + one-line subtitle · row = coloured icon +
title + one grey sentence that states the effect *and its cost* ("Needs Accessibility", "Uses the network") · dependants
dimmed, never hidden · sliders show the value with −/+ · segmented control for 2–4 options · destructive buttons red with
inline confirm · every page ends with "Restore Defaults — nothing else changes" · status read-outs inline · say where data
lives ("Stays on this Mac").

| Page | Missing feature | Pri | Status | How (public API) |
|---|---|---|---|---|
| General | Suggestions card (missing permissions → Allow) + red badge on the sidebar row | P1 | ✅ | permission checks of the Permissions page |
| General | "Show in DynaNotch" toggle for `dynanotch://notify` + Copy Example Link | P1 | ✅ | `settings.notifyActivity` + pasteboard |
| General | Emergency shortcut (quit/relaunch) + Force Quit button | P2 | ✅ | Carbon hotkey ⌃⌥⌘Q · `exit(0)` |
| General | Menu-bar items per tool | P3 | ⏳ | extra `NSStatusItem`s with popovers |
| General | Hide Menu Bar Icons (Bartender-style) | — | ❌ | fragile spacer trick; macOS 26 menu-bar management conflicts |
| Appearance | Closed Pill Size (scale %) + Pill Height Adjustment (pt) | P1 | ✅ | scale `IslandLayout` sizes; offset added to `topInset` |
| Appearance | Clock options: time / date / both, date format, show with activities | P2 | ✅ time / date / both + with activities; separate date-format picker ⏳ | `DateFormatter` templates |
| Appearance | Panel width, Fixed / Fit Content, max height, Compact / Default buttons | P2 | ✅ | (was §2d ⏳) parameterise `IslandLayout.expandedWidth/ContentHeight` |
| Appearance | Custom panel fill (colour / gradient) · pill colour "Same as Panel" | P2 | ✅ | `ColorPicker` → hex in settings → `IslandGlass` |
| Appearance | Monochrome interface · panel font + text size with live preview row | P3 | ⏳ | environment font scale |
| Appearance | Notifications-only mode · Minimal layout (scale, visible tabs / header buttons) | P3 | ⏳ | second tab/button list |
| Appearance | Hide the hardware notch (black menu-bar strip + rounded top corners) | P3 | ⏳ | click-through `.statusBar` window per notch screen |
| Behavior | Screen Sharing Privacy (island hidden from captures/shares) | P1 | ✅ (turning it off swaps in a fresh panel: `.none` can't be undone on a window) | `NSWindow.sharingType = .none` |
| Behavior | Hide While Mirroring | P1 | ✅ | `CGDisplayIsInMirrorSet` |
| Behavior | Full-screen apps: All / only the app playing media | P1 | ✅ | compare frontmost bundle with NowPlaying bundle |
| Behavior | Auto Collapse toggle (separate from delay) | P1 | ✅ | gate `collapseDelay` |
| Behavior | Show On: All / Built-in / Main / External (4 modes, ours has 3) | P2 | ✅ | `ScreenLocator` |
| Behavior | Hide if menus overlap the island | P3 | ⏳ | AX menu-bar item frames (Accessibility) |
| Behavior | Hide in Mission Control | P3 | ⏳ | heuristic `CGWindowListCopyWindowInfo` |
| Behavior | Shortcut recorder chips (reset ⟲ / clear ✕) + per-tab shortcuts | P2 | ✅ | Carbon `RegisterEventHotKey` per binding |
| Behavior | Hide shortcut (⌥Space) · Command Palette (⌃⌥K: tabs, actions, settings) | P2 | ✅ | Carbon hotkeys + SwiftUI palette in the panel |
| Behavior | Launcher Wheel (radial app menu under the notch, ⌃⌥L) | P3 | ⏳ | LauncherService + radial overlay |
| Behavior | Siri on the notch | — | ❌ | no public API |
| Popups | Quiet popups during Focus | P1 | ✅ (keeps low battery, timer finished, camera/mic) | gate HUD/activity posts on `FocusService.state.isActive` |
| Popups | Feature-alert overview rows linking to each page | P1 | ✅ | settings navigation |
| Popups | Alert sounds per category with ▶ preview | P2 | ✅ | `NSSound(named:)` system sounds |
| Popups | Feature tips (one per day, never during Focus) | P3 | ⏳ | notify island |
| All Tools | Searchable feature-card grid with a toggle per feature | P2 | ✅ | new Settings page bound to existing toggles |
| Tabs | Tab labels (Selected / All / None), tabs beside the notch, favourites | P2 | ⏳ | header layout settings |
| Tabs | Quick Settings tab (chosen switches in the notch) | P2 | ✅ | new `PanelTab.quickSettings` |
| Tabs | Shelf retention (until cleared / 1 h / 1 day / 1 week) | P1 | ✅ | ShelfService prune |
| Tabs | Header buttons: Stopwatch, Pomodoro, Volume, Caffeine, Scan QR Code, Ports, System Stats | P2 | ✅ (Scan QR decode tested offline; live area capture not run) | QR = `screencapture -i` + `CIDetector(ofType: .qrCode)`; Ports = `lsof -iTCP -sTCP:LISTEN` |
| Tabs | Reminders: natural-language due dates ("tomorrow 9") | P2 | ✅ (parser tested on sample phrases; typing in the tab not scripted) | `NSDataDetector(.date)` |
| Tabs | Sound Mixer (per-app volume) | P3 | ⏳ | Core Audio process taps (macOS 14.4+) — heavy |
| Home | Card grid editor + cards: World Clock, Network, Device Batteries, Sunrise & Sunset, Saved Links, Colors, Coding Agents, Bluetooth connect | P2 | ✅ all 13 cards (Saved Links / Bluetooth connect not clicked in tests) | sunrise/sunset = Open-Meteo `daily=sunrise,sunset` |
| Home | Desktop widgets (clock, weather, now playing, batteries) | P3 | ⏳ | desktop-level `NSPanel` |
| Knock | Modifier-key knock (tap ⌃ 1–3×) → action palette | P2 | ✅ (simulated taps; a physical knock needs Accessibility) | global `.flagsChanged` monitor |
| Knock | Chassis knock | — | ❌ | accelerometer is private |
| Lock Screen | Unlock island + sound when you come back | P3 | ⏳ | `com.apple.screenIsUnlocked` distributed notification |
| Now Playing | Show track info on hover / always / never; peek on hover | P1 | ✅ peek on hover; always/never picker ⏳ | (peek was §2d ⏳) |
| Now Playing | Media keys always drive the current player; stop Music.app auto-opening; default music app | P1 | ✅ (media keys need Accessibility); default-app picker ⏳ | MediaKeyTap consumes play/next/prev; terminate `com.apple.Music` launched < 2 s after a key |
| Now Playing | Desktop Lyrics floating panel | P2 | ✅ (window checked; content not rendered in tests) | click-through `NSPanel` with LyricsService line |
| Now Playing | Listening history + bookmarks | P2 | ✅ | JSON ledger from `trackChanged` |
| Now Playing | Music.app love / shuffle / repeat / app volume | P3 | ⏳ | AppleScript |
| Now Playing | Audio-reactive visualiser | P3 | ⏳ | Core Audio process tap + permission |
| Now Playing | NetEase lyrics, browser speed control | — | ❌ | non-keyless API · JS injection |
| Calendar | Join Meeting / Open Calendar shortcuts, "only meetings with a join link" | P1 | ✅ ⌃⌥J / ⌃⌥C (not yet tested live: needs Calendar access) | `MeetingLink` + Carbon hotkeys |
| Calendar | Per-calendar toggles | P1 | ✅ (not yet tested live: needs Calendar access) | filter `EKCalendar.calendarIdentifier` |
| Calendar | Dedicated Calendar tab: month + add / edit / delete events + due reminders | P2 | ✅ | EventKit `EKEvent` save/remove |
| Calendar | Next meeting in the menu bar | P2 | ✅ (not seen live: no upcoming events) | `NSStatusItem` title |
| Activity | Clicks / keystrokes / mouse distance + rings / floating orb | P3 | ⏳ | (was §2d ⏳) listen-only event tap, Input Monitoring |
| AI Usage | Limit / run-out warnings, menu-bar readout, hide personal info | P2 | ✅ | AIUsageService thresholds |
| AI Usage | Session cost summary after each Claude reply (Stop hook) | P2 | ✅ installer (tested on copies; never installed into the real ~/.claude/settings.json) | hook → `dynanotch://notify` with cost from ClaudeUsageParser |
| AI Usage | Approve / deny agent prompts from the notch | P3 | ⏳ | PermissionRequest hook ↔ local socket |
| AI Usage | Ollama running models | P3 | ⏳ | `localhost:11434/api/ps` (local only) |
| Timer | Controls on hover (pause / +1 min / stop) on the compact timer | P1 | ✅ | hover overlay in `CompactTimerView` |
| Timer | Repeat timer, repeat alarm until dismissed, Pomodoro-only mode | P2 | ✅ | TimerEngine flags |
| Timer | Focus sounds (rain, brown noise) | P3 | ⏳ | bundled loops + `AVAudioPlayer` |
| Clipboard | Capture sound · tracking links: strip vs "offer a clean copy" | P1 | ✅ capture sound + "offer a clean copy" (v3.4) | `NSSound` · LinkCleaner mode |
| Clipboard | Copy twice to open (⌘C ⌘C) · paste-as-plain-text shortcut | P2 | ✅ | pasteboard changeCount timing · Carbon hotkey |
| Clipboard | Saved named lists + snippets | P2 | ⏳ | Codable lists in App Support |
| Quick Search | Custom engines with "start from an example" (Kagi, Stack Overflow, Reddit, npm, HN, ChatGPT) | P2 | ✅ | (was §2d ⏳) `SearchEngine` list in settings |
| Files | App install offer when a .dmg mounts (copy .app to /Applications) | P2 | ✅ | DriveMonitor + `FileManager.copyItem` |
| Files | Long-command islands: one-click zsh hook installer | P2 | ✅ installer (tested on a copy of ~/.zshrc; not installed for real) | preexec/precmd snippet → `dynanotch://notify` |
| Files | Keystroke HUD | P3 | ⏳ | listen-only event tap (Input Monitoring) |
| Files | Dictation | P3 | ⏳ | on-device `SFSpeechRecognizer` |
| Screenshots | Save-to folder · record screen / area | P1 | ✅ (recording needs Screen Recording permission; `ScreenRecorder` runs `screencapture -v`) | `screencapture <path>` · `screencapture -v` |
| Screenshots | Annotate after capture, watermark | P3 | ⏳ | Core Image / custom editor |
| Displays | Per-display brightness incl. Extra Dim; refresh-rate switch | P3 | ⏳ | gamma tables (`CGSetDisplayTransferByTable`), `CGDisplaySetDisplayMode`; DDC best-effort |
| Battery | Unplug island with time left · full-charge level (80–100 %) | P1 | ✅ | `BatteryInfo.minutesToEmpty` |
| Battery | 30-day history range · battery in the menu bar | P2 | ✅ | BatteryHistory already keeps 30 days |
| Battery | Battery drain warnings (app using lots of CPU on battery) · screen-edge glow on alerts | P2 | ✅ (drain warnings not seen live: Mac on AC power) | `proc_pid_rusage` sampling · edge window |
| Connectivity | Wi-Fi row · accessory battery sparkline · network traffic history | P2 | ✅ Wi-Fi / network row + traffic history; accessory sparkline ⏳ | CoreWLAN (Location) · samples · getifaddrs ledger |
| Caffeine | Keep Awake for 15 m / 30 m / 1 h / 2 h / 4 h / until a time / until stopped | P1 | ✅ menu on the cup button ("until a time" ⏳) | KeepAwakeService timer + menu on the header button |
| Caffeine | Awake with lid closed | — | ❌ | needs admin `pmset disablesleep` |
| Permissions | Grouped (Required / Features / Advanced), "Still not working?" help, copy diagnostics | P1 | ✅ | `PermissionDiagnostics.report()` |
| About | Clear caches with sizes · Uninstall (remove data, login item, hooks) · What's New | P2 | ✅ (Uninstall never run in tests) | App Support sizes; `SMAppService.unregister` |
| About | Updates, crash reports, iCloud sync, Insights / Wrapped | — | ❌ | personal unsigned build |
| Calls & Messages, Stocks, Cuely, Terminal, Face Unlock, Pointer, Typing Sounds, Desktop Pet, Lock-screen widgets | | — | ❌ | private APIs / paid data / non-goals (unchanged) |

---

## 3. Tech stack (final)

| Layer | Choice |
|---|---|
| Language | Swift 5 language mode (compiled by the Swift 6 toolchain in Xcode 16) |
| UI | SwiftUI hosted in a borderless `NSPanel` (AppKit for windowing) |
| Build | **Swift Package Manager** (`Package.swift`) + `build.sh` that assembles `DynaNotch.app`. No `.xcodeproj` (open `Package.swift` in Xcode if wanted) |
| Min OS | macOS 14.0 (deployment target); owner runs 15+ |
| Now Playing | `Adapter/MediaRemoteAdapter.m` → `libMediaRemoteAdapter.dylib`, loaded into `/usr/bin/perl` (Apple-signed, still entitled to MediaRemote after 15.4); JSON lines over stdout, commands over stdin |
| System APIs | CoreAudio, IOKit.ps, IOBluetooth, EventKit, DisplayServices (private, `dlopen`), CGEventTap, ServiceManagement, CoreMediaIO, CoreLocation, Carbon (hotkeys), NSPasteboard |
| Network (optional, cached) | iTunes Search (artwork), LRCLIB (lyrics), Open-Meteo (weather + geocoding). Nothing else leaves the Mac. |
| Tests | XCTest for `DynaNotchCore` (runs on macOS **and Linux**) |

---

## 4. Repository layout

```
dyna-notch/
├─ Package.swift                 # DynaNotchCore (lib), DynaNotch (exe, macOS only), DynaNotchCoreTests
├─ build.sh                      # one command: test → build → bundle → sign → install → launch (`--dmg` adds a DMG)
├─ build_dmg.sh                  # = build.sh --dmg
├─ Adapter/MediaRemoteAdapter.m  # ObjC helper loaded into /usr/bin/perl
├─ Packaging/
│  ├─ Info.plist                 # literal values (no $(VAR) substitution)
│  ├─ libMediaRemoteAdapter.dylib  # prebuilt universal fallback if clang is unavailable
│  └─ make_icon.swift            # renders AppIcon.icns at build time (non-fatal)
├─ Sources/
│  ├─ DynaNotchCore/             # Foundation-only, platform-independent, 100 % unit-tested
│  └─ DynaNotch/                 # the app (AppKit + SwiftUI)
│     ├─ App/                    # DynaNotchApp, AppDelegate, StatusItemController, SettingsWindowController
│     ├─ Window/                 # NotchPanel, NotchHostingView, IslandWindowController, ScreenLocator
│     ├─ Model/                  # AppSettings, IslandViewModel
│     ├─ Services/               # v2: NowPlaying, Volume, Brightness, MediaKeyTap, Battery, Bluetooth, Focus, Calendar, Fullscreen,
│     │                          #     Artwork, Permissions, LaunchAtLogin
│     │                          # v3: Timer, Clipboard, Shelf, Notes, Lyrics, Weather, SystemMonitor, AIUsage, AudioDevice,
│     │                          #     KeepAwake, PrivacyMonitor, CapsLockMonitor, DownloadsMonitor, HotKey, ScreenLock
│     └─ Views/                  # Island*, Compact*, Expanded* (PanelHeader), Tabs/<Name>Tab.swift, Settings/*
├─ Tests/DynaNotchCoreTests/
├─ scripts/check.sh              # Linux/macOS: core build + tests + syntax parse of app sources
├─ CLAUDE.md
└─ README.md                     # owner guide
```

---

## 5. Architecture

```
 Services (GCD/Combine, no UI)         Model                      Window / Views
 ┌──────────────────────┐   publish   ┌──────────────────┐ @Published ┌──────────────────────┐
 │ NowPlayingService    ├────────────►│                  ├───────────►│ IslandRootView       │
 │ VolumeService        │             │ IslandViewModel  │            │  NotchShape + content│
 │ BrightnessService    │  events     │  (owns           │◄───────────┤  ExpandedView, …     │
 │ MediaKeyTap ─handler─┼────────────►│   IslandEngine)  │  intents   └──────────▲───────────┘
 │ BatteryService       │             │                  │                       │
 │ BluetoothService     │             └───────▲──────────┘            ┌──────────┴───────────┐
 │ FocusService         │                     │ hover / swipe / screen│ IslandWindowController│
 │ CalendarService      │                     └───────────────────────┤  NotchPanel (fixed    │
 │ FullscreenDetector   │                                             │  canvas, click-through)│
 └──────────────────────┘                                             └───────────────────────┘
                 DynaNotchCore: IslandEngine, IslandLayout, NotchMetrics, parsers, detectors (pure)
```

### Window strategy (important)
- **One transparent `NotchPanel`** pinned to the top-centre of the target screen. Its canvas is `vm.canvasSize` =
  `IslandLayout.canvasSize(panelWidth:panelMaxHeight:notchHeight:)` — at least the static `IslandLayout.canvasSize`
  (720×320, which the `dn.sh` x=360 test helpers assume) and larger only when Settings → Appearance asks for a wider/taller
  panel (v3.4). The window is resized **only when those settings change, never during animations**; SwiftUI animates the
  island inside it. This avoids the AppKit/SwiftUI layout-recursion crashes of v1.
- Level `.mainMenu + 3`, `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, borderless + `.nonactivatingPanel`, `hasShadow = false`, transparent. **Override `constrainFrameRect(_:to:)` to return the rect unchanged**, otherwise macOS pushes the window below the menu bar.
- **Click-through**: `ignoresMouseEvents` is toggled by the window controller. A global + local `.mouseMoved` monitor (plus a 0.2 s safety poll) checks whether the cursor is inside the island's screen rect (`IslandLayout.screenRect`, inflated by 4 pt). Inside → `ignoresMouseEvents = false`, `vm.setHovering(true)`. Outside → `true`, `vm.setHovering(false)`.
- `NotchHostingView.acceptsFirstMouse` → `true` so the first click on a button works.
- A global `.leftMouseDown` outside the island while expanded collapses it.
- Two-finger swipes: local `.scrollWheel` monitor (only fires while the cursor is over the island).

### State
- `IslandEngine` (Core, pure value type) holds activities, expanded/peek/suppressed flags and decides the `IslandPresentation`. The view model wraps it, owns timers, and republishes `presentation`.
- Presentation priority: `expanded` > live activity (highest priority, HUDs show even when suppressed) > `hidden` (full screen) > `peek` > `timer` (if `prefersTimerOverMusic`) > `lyrics` > `nowPlaying` > `timer` > `idle`.

---

## 6. Contracts (binding)

### 6.1 DynaNotchCore (module `DynaNotchCore`, everything `public`, Foundation only)

```swift
// Geometry.swift
public struct NotchMetrics: Equatable {
    public var width: CGFloat; public var height: CGFloat; public var hasPhysicalNotch: Bool
    public init(width: CGFloat, height: CGFloat, hasPhysicalNotch: Bool)
    public static let fallback: NotchMetrics            // 185 × 32, no physical notch
    /// physical notch if safeAreaTop > 0: height = safeAreaTop, width = screenWidth - leftAux - rightAux
    /// (when both aux widths given and result in 80...400) else 185.
    /// No notch: width 185, height = max(24, menuBarHeight).
    public static func compute(screenWidth: CGFloat, safeAreaTop: CGFloat, leftAuxWidth: CGFloat?,
                               rightAuxWidth: CGFloat?, menuBarHeight: CGFloat) -> NotchMetrics
}

// Activities.swift
public enum HUDKind: String, Equatable, Hashable, CaseIterable { case volume, brightness }
public enum BluetoothDeviceKind: String, Equatable, Hashable, CaseIterable {
    case airpods, airpodsPro, airpodsMax, headphones, speaker, keyboard, mouse, trackpad, gamepad, generic
    public var symbolName: String          // SF Symbols: "airpods", "airpodspro", "airpodsmax", "headphones", "hifispeaker.fill", "keyboard", "computermouse", "rectangle.and.hand.point.up.left", "gamecontroller.fill", "dot.radiowaves.left.and.right"
    public static func classify(name: String, majorClass: UInt32, minorClass: UInt32) -> BluetoothDeviceKind
}
public enum ActivityCategory: String, Equatable, Hashable { case hud, power, bluetooth, focus, calendar }
public enum ActivityKind: Equatable {
    case hud(HUDKind, level: Double, muted: Bool)
    case charging(level: Double, isCharging: Bool, pluggedIn: Bool)
    case lowBattery(level: Double)
    case bluetooth(name: String, device: BluetoothDeviceKind, battery: Int?, connected: Bool)
    case focus(name: String, symbol: String, enabled: Bool)
    case calendar(title: String, minutesUntil: Int)
    public var category: ActivityCategory   // charging & lowBattery → .power
    public var defaultDuration: TimeInterval // hud 1.6, charging 3.0, lowBattery 4.0, bluetooth 3.5, focus 2.5, calendar 6.0
    public var priority: Int                 // hud 100, lowBattery 90, charging 80, bluetooth 70, focus 60, calendar 50
}
public struct LiveActivity: Equatable, Identifiable {
    public let id: UUID; public var kind: ActivityKind; public var postedAt: Date; public var expiresAt: Date
    public init(id: UUID = UUID(), kind: ActivityKind, postedAt: Date, expiresAt: Date)
}

// IslandEngine.swift
public enum IslandPresentation: Equatable { case hidden, idle, nowPlaying, peek, activity(LiveActivity), expanded
    public var isCompactLike: Bool  // nowPlaying, peek, activity
}
public enum SwipeDirection: String, Equatable { case left, right, up, down }
public struct IslandEngine: Equatable {
    public init()
    public private(set) var activities: [LiveActivity]
    public var isExpanded: Bool                 // default false
    public var isNowPlayingActive: Bool         // default false
    public var isSuppressed: Bool               // full-screen hide, default false
    public private(set) var peekUntil: Date?
    /// Same category replaces the existing activity **keeping its id** (no re-transition for HUD updates).
    @discardableResult public mutating func post(_ kind: ActivityKind, now: Date, duration: TimeInterval? = nil) -> LiveActivity
    public mutating func dismissCurrent(now: Date)
    public mutating func dismissAll()
    public mutating func startPeek(now: Date, duration: TimeInterval)
    public mutating func cancelPeek()
    public mutating func prune(now: Date)       // drop expired activities and finished peek
    public func currentActivity(now: Date) -> LiveActivity?   // highest priority, ties → newest postedAt
    public func presentation(now: Date, showNowPlayingCompact: Bool) -> IslandPresentation
    public func nextDeadline(now: Date) -> Date?  // earliest future expiresAt / peekUntil
}

// IslandLayout.swift
public enum HUDStyle: String, Equatable, Hashable, CaseIterable { case compact, expanded }
public struct IslandRadii: Equatable { public var top: CGFloat; public var bottom: CGFloat; public init(top: CGFloat, bottom: CGFloat) }
public enum IslandLayout {
    public static let canvasSize: CGSize            // 720 × 320
    public static let expandedWidth: CGFloat        // 600
    public static let expandedContentHeight: CGFloat // 156 (added below notch height)
    public static func sideWidth(for p: IslandPresentation, hudStyle: HUDStyle) -> CGFloat
    public static func size(for p: IslandPresentation, notch: NotchMetrics, hudStyle: HUDStyle) -> CGSize
    public static func radii(for p: IslandPresentation, hudStyle: HUDStyle) -> IslandRadii
    /// Rect in canvas coordinates, origin top-left, island centred horizontally at y = 0.
    public static func canvasRect(for size: CGSize) -> CGRect
    /// AppKit screen coordinates (origin bottom-left): (midX - w/2, maxY - h, w, h).
    public static func screenRect(for size: CGSize, screenFrame: CGRect) -> CGRect
    /// Panel frame for the canvas pinned to top-centre of `screenFrame`.
    public static func panelFrame(screenFrame: CGRect) -> CGRect
}
```
Size rules (`top` = ear radius, included in width): `idle` = notch.w + 2·top × notch.h · `nowPlaying` side 44 · `peek` side 110, height notch.h + 36 · activity sides: hud compact 72, hud expanded-style: side 60 and height notch.h + 34 · charging/lowBattery 64 · bluetooth 84 · focus 72 · calendar 96 · compact height = notch.h · `expanded` = max(expandedWidth, notch.w + 2·top + 160) × (notch.h + expandedContentHeight) · `hidden` = .zero.
Compact width = notch.w + 2·top + 2·side. Radii: idle (6, 9), nowPlaying/activity compact (6, 11), peek & hud-expanded (8, 16), expanded (14, 28), hidden (6, 9).

```swift
// NowPlaying.swift
public struct NowPlayingSnapshot: Equatable {
    public var title: String; public var artist: String; public var album: String
    public var duration: Double; public var elapsed: Double; public var timestamp: Date
    public var playbackRate: Double; public var isPlaying: Bool
    public var bundleIdentifier: String?        // parentBundle if non-empty else bundle
    public var artworkIdentifier: String?; public var artworkData: Data?
    public init(title: String = "", artist: String = "", album: String = "", duration: Double = 0, elapsed: Double = 0,
                timestamp: Date = Date(), playbackRate: Double = 0, isPlaying: Bool = false,
                bundleIdentifier: String? = nil, artworkIdentifier: String? = nil, artworkData: Data? = nil)
    public static let empty: NowPlayingSnapshot
    public var isEmpty: Bool                    // title empty
    public var trackKey: String                 // title + "\u{1F}" + artist + "\u{1F}" + album
    public func elapsed(at now: Date) -> Double // playing: elapsed + Δt·(rate > 0 ? rate : 1), clamped to 0...duration (if duration > 0)
    public func progress(at now: Date) -> Double // 0...1, 0 if duration <= 0
}
public enum AdapterMessage: Equatable { case ready, nowPlaying(NowPlayingSnapshot), empty, error(String), unknown }
public enum AdapterParser {
    /// Parses one JSON line from the adapter. Keys: type ("ready"|"nowPlaying"|"error"), empty, title, artist, album,
    /// duration, elapsed, rate, timestamp (unix seconds), playing, bundle, parentBundle, artworkId, artwork (base64), message.
    /// Tolerates NSNull, numbers-as-strings, missing keys, garbage (→ .unknown).
    public static func parse(line: String) -> AdapterMessage
}

// Formatting.swift
public enum Format {
    public static func time(_ seconds: Double) -> String         // "0:00", "3:07", "1:02:03"; NaN/neg/inf → "0:00"
    public static func percent(_ level: Double) -> String        // clamps 0...1 → "0%"..."100%"
    public static func relativeMinutes(_ minutes: Int) -> String // <=0 "now", "in 5 min", "in 1 h", "in 1 h 20 min"
    public static func clockRange(start: Date, end: Date, calendar: Calendar = .current, locale: Locale = .current) -> String
}

// MediaKeys.swift
public enum MediaKey: Int, Equatable { case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7,
    play = 16, next = 17, previous = 18, fast = 19, rewind = 20, illuminationUp = 21, illuminationDown = 22 }
public struct MediaKeyEvent: Equatable {
    public let rawKeyCode: Int; public let key: MediaKey?; public let isDown: Bool; public let isRepeat: Bool
    /// NSEvent.data1 of a systemDefined (subtype 8) event: code = (d >> 16) & 0xFFFF, flags = d & 0xFFFF,
    /// down = ((flags & 0xFF00) >> 8) == 0x0A, repeat = flags & 0x1 == 1
    public init(data1: Int)
}
public enum LevelStepper {
    public static let step: Double = 1.0 / 16.0; public static let fineStep: Double = 1.0 / 64.0
    /// moves to the next multiple of the step in the given direction, clamped 0...1
    public static func step(_ level: Double, up: Bool, fine: Bool) -> Double
}
public struct LevelReading: Equatable { public var level: Double; public var muted: Bool; public init(level: Double, muted: Bool) }

// Power.swift
public struct BatteryInfo: Equatable {
    public var level: Double; public var isCharging: Bool; public var isPluggedIn: Bool
    public var minutesToEmpty: Int?; public var minutesToFull: Int?
    public init(level: Double, isCharging: Bool, isPluggedIn: Bool, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil)
}
public enum PowerEvent: Equatable { case pluggedIn(BatteryInfo), unplugged(BatteryInfo), lowBattery(BatteryInfo, threshold: Int) }
public struct PowerEventDetector {
    public init(thresholds: [Int] = [20, 10])
    /// First call only records state (no events). Plug state change → plugged/unplugged.
    /// Crossing a threshold downward while not plugged in → lowBattery once; re-armed when plugged in or level > threshold + 5.
    public mutating func update(_ info: BatteryInfo) -> [PowerEvent]
}

// Bluetooth.swift
public struct BluetoothEvent: Equatable {
    public var address: String; public var name: String; public var kind: BluetoothDeviceKind
    public var battery: Int?; public var connected: Bool
    public init(address: String, name: String, kind: BluetoothDeviceKind, battery: Int?, connected: Bool)
}

// Focus.swift
public struct FocusState: Equatable { public var modeIdentifier: String?; public var name: String; public var symbol: String
    public var isActive: Bool { modeIdentifier != nil }
    public init(modeIdentifier: String?, name: String, symbol: String)
    public static let inactive: FocusState }
public enum FocusParser {
    /// Assertions.json → data[0].storeAssertionRecords[0].assertionDetails.assertionDetailsModeIdentifier (nil when no records)
    public static func activeModeIdentifier(assertionsJSON: Data) -> String?
    /// ModeConfigurations.json → data[0].modeConfigurations[id].mode.{name,symbolImageName}; falls back to known ids
    /// (default→"Do Not Disturb"/"moon.fill", sleep→"Sleep"/"bed.double.fill", driving→"Driving"/"car.fill",
    /// work→"Work"/"briefcase.fill", personal→"Personal"/"person.fill", reading→"Reading"/"book.fill",
    /// fitness→"Fitness"/"figure.run", gaming→"Gaming"/"gamecontroller.fill", mindfulness→"Mindfulness"/"brain.head.profile",
    /// otherwise "Focus"/"moon.fill") matched by substring of the lowercased identifier.
    public static func state(assertionsJSON: Data, configurationsJSON: Data?) -> FocusState
}

// Calendar.swift
public struct CalendarItem: Equatable, Identifiable {
    public var id: String; public var title: String; public var start: Date; public var end: Date
    public var isAllDay: Bool; public var location: String?; public var colorHex: String?
    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil, colorHex: String? = nil)
}
public struct CalendarAlertTracker {
    public init()
    /// Timed (non all-day) events with now < start <= now + lead·60 that were not returned before.
    public mutating func due(events: [CalendarItem], now: Date, leadMinutes: Int) -> [CalendarItem]
}
public enum CalendarFilter {
    /// Not ended, sorted by start (all-day first for today), max `limit`.
    public static func upcoming(_ items: [CalendarItem], now: Date, limit: Int) -> [CalendarItem]
}

// ColorMath.swift
public struct RGB: Equatable { public var r: Double; public var g: Double; public var b: Double; public init(r: Double, g: Double, b: Double) }
public enum ColorMath {
    /// Saturation-weighted average, then brightness lifted to >= 0.55 (HSB) so it reads on black. Empty → white.
    public static func accent(fromPixels pixels: [RGB]) -> RGB
    public static func hsb(_ c: RGB) -> (h: Double, s: Double, b: Double)
    public static func rgb(h: Double, s: Double, b: Double) -> RGB
}

// Settings.swift
public enum DisplayMode: String, Equatable, Hashable, CaseIterable { case notchOrMain, main, followMouse
    public var title: String }  // "Built-in (notch) display", "Main display", "Follow mouse"
public enum ArtworkStyle: String, Equatable, Hashable, CaseIterable { case rounded, circle; public var title: String }
public enum VisualizerStyle: String, Equatable, Hashable, CaseIterable { case bars, none; public var title: String }
public enum SettingsKey { public static let … }   // one String constant per AppSettings property, same name
```

### 6.2 App (module `DynaNotch`) — classes, singletons and published API

**Concurrency rule (critical, we cannot compile on the owner's Mac before shipping):** no `async`/`await`, no `Task {}`, no `actor`, no explicit `@MainActor`/`@Sendable`/`nonisolated` in our code. Use GCD (`DispatchQueue.main.async`) and Combine (`Timer.publish`, `sink`). UI state is only mutated on the main thread. Prefer completion-handler APIs (e.g. `requestFullAccessToEvents(completion:)`).

```swift
// Model/AppSettings.swift — UserDefaults-backed, every property `@Published var x: T { didSet { persist } }`
final class AppSettings: ObservableObject { static let shared: AppSettings
  // General
  showMenuBarIcon: Bool = true; displayMode: DisplayMode = .notchOrMain; hideInFullscreen: Bool = true
  showOnNonNotchDisplays: Bool = true; hapticFeedback: Bool = true; hasCompletedOnboarding: Bool = false
  // Island
  expandOnHover: Bool = true; hoverDelay: Double = 0.15; collapseDelay: Double = 0.35; clickToExpand: Bool = true
  gesturesEnabled: Bool = true; expandedShowsCalendar: Bool = true; expandedShowsBattery: Bool = true
  // Now Playing
  nowPlayingEnabled: Bool = true; showCompactNowPlaying: Bool = true; showTrackPeek: Bool = true
  artworkStyle: ArtworkStyle = .rounded; visualizerStyle: VisualizerStyle = .bars; artworkGlow: Bool = true
  pausedLingerSeconds: Double = 15
  // HUD
  hudEnabled: Bool = true; replaceSystemHUD: Bool = true; hudStyle: HUDStyle = .compact
  volumeHUD: Bool = true; brightnessHUD: Bool = true
  // Live activities
  chargingActivity: Bool = true; lowBatteryActivity: Bool = true; bluetoothActivity: Bool = true
  focusActivity: Bool = true; calendarActivity: Bool = true; calendarLeadMinutes: Int = 5
  calendarEnabled: Bool = true
  func resetToDefaults()
}

// Model/IslandViewModel.swift
final class IslandViewModel: ObservableObject {
  init(settings: AppSettings = .shared)
  @Published private(set) var presentation: IslandPresentation   // .idle initially
  @Published private(set) var notch: NotchMetrics                // .fallback initially
  @Published private(set) var isHovering: Bool
  var islandSize: CGSize { get }      // IslandLayout.size(for: presentation, notch:, hudStyle: settings.hudStyle)
  var radii: IslandRadii { get }
  func start()                        // wires services, starts them
  func setNotch(_ metrics: NotchMetrics)
  func setHovering(_ hovering: Bool)  // hover → expand after hoverDelay (if expandOnHover); leave → collapse after collapseDelay
  func tap()                          // clickToExpand: toggles expanded
  func expand(); func collapse()
  func swipe(_ direction: SwipeDirection)  // left = next track, right = previous, up = collapse / dismiss activity
  func setSuppressed(_ suppressed: Bool)
  func post(_ kind: ActivityKind)     // respects settings toggles
  func openSettings()                 // NotificationCenter.default.post(name: .dynaNotchOpenSettings, object: nil)
  func simulate(_ demo: DemoActivity) // debug menu: volume, brightness, charging, lowBattery, airpods, focus, calendar, peek
}
enum DemoActivity: String, CaseIterable { case volume, brightness, charging, lowBattery, airpods, focus, calendar, peek }
extension Notification.Name { static let dynaNotchOpenSettings = Notification.Name("DynaNotch.openSettings") }

// Services — all `final class`, `static let shared`, idempotent `start()`; callbacks on main queue
NowPlayingService: ObservableObject
  @Published private(set) var snapshot: NowPlayingSnapshot   // .empty
  @Published private(set) var artwork: NSImage?
  @Published private(set) var accentColor: NSColor            // .white
  @Published private(set) var appIcon: NSImage?
  @Published private(set) var appName: String
  @Published private(set) var source: NowPlayingSource        // enum NowPlayingSource: String { case none, mediaRemote, appleScript }
  let trackChanged: PassthroughSubject<NowPlayingSnapshot, Never>   // new non-empty trackKey
  func start(); func stop()
  func togglePlayPause(); func next(); func previous(); func seek(to seconds: Double)
VolumeService      let changes: PassthroughSubject<LevelReading, Never>; func start(); func read() -> LevelReading?
                   @discardableResult func setLevel(_ v: Double) -> Bool; @discardableResult func setMuted(_ m: Bool) -> Bool
BrightnessService  let changes: PassthroughSubject<Double, Never>; var isAvailable: Bool; func start()
                   func read() -> Double?; @discardableResult func setLevel(_ v: Double) -> Bool
MediaKeyTap        var handler: ((MediaKeyEvent, NSEvent.ModifierFlags) -> Bool)?  // return true = consume
                   @Published private(set) var isActive: Bool (ObservableObject); func start(); func stop()
BatteryService: ObservableObject   @Published private(set) var info: BatteryInfo?; let events: PassthroughSubject<PowerEvent, Never>; func start()
BluetoothService   let events: PassthroughSubject<BluetoothEvent, Never>; func start()
FocusService: ObservableObject     @Published private(set) var state: FocusState; @Published private(set) var isReadable: Bool
                   let changes: PassthroughSubject<FocusState, Never>; func start()
CalendarService: ObservableObject  @Published private(set) var upcoming: [CalendarItem]; @Published private(set) var access: CalendarAccess
                   enum CalendarAccess { case notDetermined, denied, granted }
                   let dueSoon: PassthroughSubject<CalendarItem, Never>; func start(); func requestAccess()
                   func colorFor(_ item: CalendarItem) -> Color  (SwiftUI)  // from colorHex, default .blue
FullscreenDetector: ObservableObject  @Published private(set) var isFullscreen: Bool; func start(screenProvider: @escaping () -> NSScreen?)
ArtworkLookup      func lookup(title: String, artist: String, completion: @escaping (NSImage?) -> Void)  // iTunes Search API, cached
Permissions (enum) static var accessibilityGranted: Bool; static func requestAccessibility(); static func openAccessibilitySettings()
                   static func openFullDiskAccessSettings(); static func openCalendarSettings(); static func openBluetoothSettings()
LaunchAtLogin (enum) static var isEnabled: Bool; @discardableResult static func setEnabled(_ on: Bool) -> Bool
NSImage extension  func dominantAccentColor() -> NSColor   // samples 12×12 bitmap → ColorMath.accent
```

### 6.3 Window & Views
- `NotchPanel: NSPanel` (see §5). `NotchHostingView<Content: View>: NSHostingView<Content>` (`acceptsFirstMouse` true).
- `IslandWindowController` (plain `NSObject` subclass, not `NSWindowController`): `init(viewModel:)`, `show()`, owns panel, monitors, screen selection (`ScreenLocator.targetScreen(mode:)`), calls `vm.setNotch` on screen change, `vm.setHovering`, `vm.swipe`, `vm.collapse`, `vm.setSuppressed(FullscreenDetector)`.
- `IslandRootView`: `@EnvironmentObject` `IslandViewModel`, `AppSettings`, `NowPlayingService`, `BatteryService`, `CalendarService`, `FocusService`. Fills canvas, island at top-centre, `NotchShape(topRadius:bottomRadius:)` (Animatable), spring `.spring(response: 0.42, dampingFraction: 0.82)` keyed on presentation & size.
- Compact layout: `HStack(spacing: 0) { leading.frame(width: side); Spacer(minLength: notch.width); trailing.frame(width: side) }` inside the ears (`.padding(.horizontal, radii.top)`), height `notch.height`.
- Settings window: own `NSWindow` + `NSHostingController(SettingsRootView)` (not the SwiftUI `Settings` scene), 720×520, sidebar tabs: General, Island, Now Playing, HUD, Live Activities, Calendar, About.

### 6.4 v3 additions (Notchy parity) — supersede §6.1–6.3 where they overlap

#### Core changes to existing types
```swift
// Activities.swift — new cases (existing ones unchanged)
public enum ActivityCategory { …, timer, notification, download, privacy, toggle }
public enum SensorKind: String, Equatable, Hashable, CaseIterable { case camera, microphone
    public var symbolName: String }           // "video.fill", "mic.fill"
case timerFinished(label: String)                                  // .timer         dur 6.0  prio 95
case notification(title: String, body: String, symbol: String)    // .notification  dur 4.5  prio 85
case download(name: String, finished: Bool)                        // .download      dur 3.5  prio 65
case sensor(SensorKind, active: Bool)                              // .privacy       dur 3.0  prio 88
case toggle(symbol: String, label: String, on: Bool)               // .toggle        dur 1.5  prio 98 (caps lock, mic mute, keep awake)

// IslandEngine.swift
public enum IslandPresentation { …, timer, lyrics }   // isCompactLike also true for timer, lyrics
public var isTimerActive: Bool = false
public var hasLyricLine: Bool = false                  // only honoured while isNowPlayingActive && showNowPlayingCompact
public var prefersTimerOverMusic: Bool = true
// priority: expanded > activity > hidden > peek > timer(if prefers) > lyrics > nowPlaying > timer > idle

// IslandLayout.swift
expandedWidth = 640, expandedContentHeight = 190
sides: timer 64 · lyrics 44 · timerFinished 96 · notification 110 · download 84 · sensor 72 · toggle 64
heights: lyrics = notch.h + 26 · notification = notch.h + 40 (peek-like) · others compact = notch.h
radii: lyrics & notification (8, 16), timer / other new activities (6, 11)
public enum NonNotchStyle: String, CaseIterable { case notch, pill; var title }   // in Settings.swift
public static let pillTopInset: CGFloat = 6         // pill floats this far below the screen top
/// `screenRect(for:screenFrame:topInset:)` — same as screenRect, shifted down by topInset (default 0).
```

#### New Core files
```swift
// Panel.swift
public enum PanelTab: String, Equatable, Hashable, CaseIterable, Codable {
    case home, nowPlaying, timer, clipboard, shelf, notes, system, aiUsage
    public var title: String     // "Home","Now Playing","Timer","Clipboard","Shelf","Notes","System","AI Usage"
    public var symbolName: String // "house.fill","music.note","timer","doc.on.clipboard","tray.full.fill","note.text","cpu","sparkles"
    /// Parses "home,timer" (unknown ids dropped, duplicates removed, order kept); empty → allCases.
    public static func parseList(_ s: String) -> [PanelTab]
    public static func serialize(_ tabs: [PanelTab]) -> String
}

// Timer.swift
public enum TimerMode: String, Equatable, Codable { case countdown, pomodoro, stopwatch }
public enum PomodoroPhase: String, Equatable, Codable { case work, shortBreak, longBreak; public var title: String } // "Focus","Short Break","Long Break"
public struct PomodoroConfig: Equatable { public var work, shortBreak, longBreak: TimeInterval; public var cyclesBeforeLongBreak: Int
    public init(work: TimeInterval = 1500, shortBreak: TimeInterval = 300, longBreak: TimeInterval = 900, cyclesBeforeLongBreak: Int = 4) }
public struct TimerState: Equatable {
    public var mode: TimerMode; public var phase: PomodoroPhase?; public var label: String
    public var duration: TimeInterval          // target; 0 for stopwatch
    public var startedAt: Date?                // nil = paused
    public var accumulated: TimeInterval       // elapsed before the current run
    public var completedWorkSessions: Int
    public var isRunning: Bool
    public func elapsed(at: Date) -> TimeInterval
    public func remaining(at: Date) -> TimeInterval   // max(0, duration - elapsed); stopwatch → elapsed
    public func progress(at: Date) -> Double          // 0...1 (stopwatch → 0)
    public func displayTime(at: Date) -> String       // Format.time(remaining) ("0:00" floor; ceil seconds for countdowns)
}
public enum TimerEvent: Equatable { case countdownFinished(label: String); case phaseFinished(from: PomodoroPhase, to: PomodoroPhase) }
public struct TimerEngine: Equatable {
    public init(config: PomodoroConfig = PomodoroConfig())
    public var config: PomodoroConfig
    public private(set) var state: TimerState?          // nil = idle
    public var isActive: Bool                            // state != nil
    public mutating func startCountdown(seconds: TimeInterval, label: String, now: Date)
    public mutating func startPomodoro(now: Date)        // phase .work
    public mutating func startStopwatch(now: Date)
    public mutating func pause(now: Date); public mutating func resume(now: Date); public mutating func toggle(now: Date)
    public mutating func reset()
    public mutating func addTime(_ seconds: TimeInterval, now: Date)   // countdown/pomodoro only
    public mutating func skipPhase(now: Date) -> TimerEvent?           // pomodoro only, auto-starts next phase
    /// Countdown done → state nil + .countdownFinished. Pomodoro phase done → next phase starts at the finish time
    /// (work → short/long break by completedWorkSessions % cycles; break → work) + .phaseFinished. Else nil.
    public mutating func tick(now: Date) -> TimerEvent?
    public func nextDeadline(now: Date) -> Date?          // finish time of the running countdown/phase
}

// Clipboard.swift
public enum ClipKind: String, Equatable, Codable { case text, link, color, image, file }
public struct ClipItem: Equatable, Identifiable, Codable {
    public var id: UUID; public var kind: ClipKind; public var text: String; public var date: Date
    public var pinned: Bool; public var sourceApp: String?; public var imageFile: String?   // file name in the app's clip image dir
    // .image items: `text` = content hash (dedupe key); .file items: `text` = paths joined by "\n"
    public init(id: UUID = UUID(), kind: ClipKind, text: String, date: Date, pinned: Bool = false, sourceApp: String? = nil, imageFile: String? = nil)
}
public enum ClipClassifier {
    public static func kind(for text: String) -> ClipKind   // http(s)/www URL (single token) → link, #RGB/#RRGGBB(AA) → color, else text
    public static func preview(_ text: String, max: Int = 200) -> String  // trims, collapses whitespace runs to one space
}
public enum LinkCleaner {
    /// Removes utm_*, fbclid, gclid, dclid, gbraid, wbraid, msclkid, mc_cid, mc_eid, igshid, igsh, yclid, _hsenc, _hsmi,
    /// mkt_tok, ref_src, ref_url, si (only on youtu.be / youtube.com / open.spotify.com); keeps order of the rest;
    /// drops a trailing "?" when nothing remains. Non-URLs returned unchanged.
    public static func clean(_ text: String) -> String
}
public struct ClipboardHistory: Equatable, Codable {
    public init(limit: Int = 50)
    public var limit: Int
    public private(set) var items: [ClipItem]          // newest first, pinned items first
    /// Same text (or same image file) already present → moved to top (keeps pin). Whitespace-only text ignored.
    /// Evicts oldest unpinned beyond limit; returns evicted items (so the app can delete image files).
    @discardableResult public mutating func add(_ item: ClipItem) -> [ClipItem]
    public mutating func remove(id: UUID) -> ClipItem?
    public mutating func togglePin(id: UUID)
    @discardableResult public mutating func clear(keepPinned: Bool = true) -> [ClipItem]
    public func search(_ query: String) -> [ClipItem]  // case/diacritic-insensitive substring; empty → items
}

// Lyrics.swift
public struct LyricLine: Equatable { public var time: TimeInterval; public var text: String; public init(time:text:) }
public enum LRCParser {
    /// "[mm:ss.xx]text", several tags per line, [offset:+/-ms] honoured, metadata tags skipped, sorted by time.
    public static func parse(_ lrc: String) -> [LyricLine]
    public static func currentIndex(at time: TimeInterval, in lines: [LyricLine]) -> Int?   // last line with time <= t
}
public enum LRCLibParser {   // https://lrclib.net/api/get?track_name=&artist_name=&album_name=&duration=
    /// → (synced lines, plain text). nil on garbage. instrumental → ([], "")
    public static func parse(_ data: Data) -> (synced: [LyricLine], plain: String)?
}

// AIUsage.swift
public struct TokenUsage: Equatable { public var input, output, cacheCreation, cacheRead: Int
    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0)
    public var total: Int; public static func + (l, r) -> TokenUsage; public static let zero }
public struct UsageEntry: Equatable { public var timestamp: Date; public var model: String; public var usage: TokenUsage
    public var dedupeKey: String?   // message.id + ":" + requestId
    public init(timestamp:model:usage:dedupeKey:) }
public enum ClaudeUsageParser { public static func parse(line: String) -> UsageEntry? }  // type=="assistant" lines with message.usage
public enum ModelPricing {   // USD per million tokens (input, output, cache write, cache read)
    /// family by substring: "opus" 15/75/18.75/1.5, "sonnet" 3/15/3.75/0.3, "haiku" 1/5/1.25/0.1, "fable" 15/75/18.75/1.5, else sonnet
    public static func cost(model: String, usage: TokenUsage) -> Double
}
public struct UsageBlock: Equatable { public var start: Date; public var end: Date; public var lastActivity: Date
    public var usage: TokenUsage; public var cost: Double; public var entryCount: Int
    public func isActive(now: Date) -> Bool }      // now < end && now - lastActivity < 5h
public enum UsageAggregator {
    /// ccusage-style: dedupe by key, sort, block starts at the UTC hour floor of its first entry, lasts `duration`;
    /// a new block starts when an entry is >= end or > duration after the previous entry.
    public static func blocks(_ entries: [UsageEntry], duration: TimeInterval = 18000) -> [UsageBlock]
    public static func activeBlock(_ entries: [UsageEntry], now: Date) -> UsageBlock?
    public static func summary(_ entries: [UsageEntry], from: Date, to: Date) -> (usage: TokenUsage, cost: Double, count: Int)
}
public struct RateWindow: Equatable { public var usedPercent: Double; public var windowMinutes: Int?; public var resetsAt: Date?
    public init(usedPercent:windowMinutes:resetsAt:) }
public struct CodexRateLimits: Equatable { public var primary: RateWindow?; public var secondary: RateWindow?; public var observedAt: Date }
public enum CodexUsageParser {
    /// event_msg / token_count lines with payload.rate_limits.{primary,secondary}.{used_percent, window_minutes,
    /// resets_at (unix s) | resets_in_seconds (relative to the line's timestamp)}.
    public static func parse(line: String) -> CodexRateLimits?
}

// Weather.swift
public enum TemperatureUnit: String, Equatable, Hashable, CaseIterable { case celsius, fahrenheit; public var title: String; public var symbol: String } // "°C","°F"
public struct WeatherSnapshot: Equatable { public var temperature: Double; public var high: Double; public var low: Double
    public var code: Int; public var isDay: Bool; public var locationName: String; public var fetchedAt: Date
    public var symbolName: String { WeatherCode.symbol(code:isDay:) }; public var summary: String { WeatherCode.summary(code:) } }
public enum WeatherCode { public static func symbol(code: Int, isDay: Bool) -> String; public static func summary(code: Int) -> String } // WMO codes
public enum OpenMeteoParser {
    /// forecast?current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto
    public static func parse(_ data: Data, locationName: String, now: Date) -> WeatherSnapshot?
    /// geocoding-api.open-meteo.com/v1/search?name=…&count=1 → (lat, lon, name)
    public static func parseGeocoding(_ data: Data) -> (latitude: Double, longitude: Double, name: String)?
}

// SystemStats.swift
public struct CPUTicks: Equatable { public var user, system, idle, nice: UInt64; public init(user:system:idle:nice:) }
public enum SystemMath {
    public static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double   // 0...1, 0 when no delta
    public static func rate(previous: UInt64, current: UInt64, interval: TimeInterval) -> Double  // bytes/s, counter wrap → 0
}
extension Format {
    public static func bytes(_ count: Double) -> String       // "0 B","512 B","1.5 KB","12 MB","1.2 GB" (1000-based, 1 decimal < 10)
    public static func rate(_ bytesPerSecond: Double) -> String // bytes + "/s"
    public static func tokens(_ n: Int) -> String              // "950", "12.3K", "4.5M"
    public static func countdown(_ seconds: TimeInterval) -> String   // "2h 05m", "14m", "<1m"
    public static func currency(_ usd: Double) -> String       // "$0.00" two decimals
}

// Downloads.swift
public enum DownloadNames {
    public static func isPartial(_ name: String) -> Bool        // .download .crdownload .part .partial .opdownload
    public static func finalName(_ partial: String) -> String   // strips the partial extension (Safari "x.zip.download")
}
public struct DownloadTracker { public init()
    /// First call seeds only. Returns partial files that appeared and final names whose partial vanished while the final exists.
    public mutating func update(_ names: Set<String>) -> (started: [String], finished: [String]) }

// Notify.swift
public struct NotchNotification: Equatable { public var title: String; public var body: String; public var symbol: String; public var duration: TimeInterval? }
public enum NotifyURL {
    /// dynanotch://notify?title=&body=&symbol=&duration= (title or body required; symbol default "bell.fill"; duration 1...30)
    public static func parse(_ url: URL) -> NotchNotification?
}

// Notes.swift
public struct TodoItem: Equatable, Identifiable, Codable { public var id: UUID; public var text: String; public var done: Bool; public var createdAt: Date
    public init(id: UUID = UUID(), text: String, done: Bool = false, createdAt: Date) }
public struct ShelfItem: Equatable, Identifiable, Codable { public var id: UUID; public var path: String; public var addedAt: Date
    public var name: String { (path as NSString).lastPathComponent }; public init(id: UUID = UUID(), path: String, addedAt: Date) }
public enum ShelfList { public static func adding(_ paths: [String], to items: [ShelfItem], now: Date) -> [ShelfItem] } // dedupe by path, new first
```

#### App additions (module `DynaNotch`)
```swift
// AppSettings — new @Published persisted properties (key "dn." + name, listed in SettingsKey.all)
nonNotchStyle: NonNotchStyle = .pill
panelTabs: String = "home,nowPlaying,timer,clipboard,shelf,notes,system,aiUsage"   // PanelTab.parseList
rememberLastTab: Bool = true; lastTab: String = "home"; hotkeysEnabled: Bool = true
lyricsEnabled: Bool = true; lyricsInCompact: Bool = true
pomodoroWorkMinutes: Int = 25; pomodoroShortBreakMinutes: Int = 5; pomodoroLongBreakMinutes: Int = 15; pomodoroCycles: Int = 4
timerSound: Bool = true; timerOverNowPlaying: Bool = true; showCompactTimer: Bool = true
clipboardEnabled: Bool = true; clipboardLimit: Int = 50; cleanLinks: Bool = true; pasteOnClick: Bool = true
shelfEnabled: Bool = true; shelfRemoveOnDragOut: Bool = false
weatherEnabled: Bool = true; weatherCity: String = ""; temperatureUnit: TemperatureUnit = .celsius
aiUsageEnabled: Bool = true
downloadActivity: Bool = true; privacyActivity: Bool = true; capsLockActivity: Bool = true; notifyActivity: Bool = true
var enabledTabs: [PanelTab]   // computed from panelTabs, filtered by the feature toggles (clipboard/shelf/aiUsage)

// IslandViewModel — additions
@Published var selectedTab: PanelTab                 // persisted to lastTab when rememberLastTab
@Published private(set) var isPinned: Bool           // pinned panel ignores mouse-leave collapse
func select(_ tab: PanelTab); func togglePin(); func open(tab: PanelTab)   // expand + select
func beginFileDrag()                                 // window controller: files dragged near the island → expand on Shelf
func notify(_ n: NotchNotification)
enum DemoActivity: …, timer, lyrics, notification, download, camera, capsLock

// New services — `final class`, `static let shared`, idempotent `start()`, main-queue publishing
TimerService: ObservableObject     @Published private(set) var engine: TimerEngine; var state: TimerState? { engine.state }
                                   let events: PassthroughSubject<TimerEvent, Never>; let tick: PassthroughSubject<Date, Never> (1 Hz while active)
                                   func startCountdown(minutes: Double, label: String); func startPomodoro(); func startStopwatch()
                                   func toggle(); func reset(); func addMinute(); func skipPhase(); func applyConfig(_ c: PomodoroConfig)
ClipboardService: ObservableObject @Published private(set) var history: ClipboardHistory; func start(); func stop()
                                   func copy(_ item: ClipItem); func paste(_ item: ClipItem, plainText: Bool)  // copy, then ⌘V if Accessibility
                                   func remove(_ item: ClipItem); func togglePin(_ item: ClipItem); func clear()
                                   func image(for item: ClipItem) -> NSImage?
ShelfService: ObservableObject     @Published private(set) var items: [ShelfItem]; func add(urls: [URL]); func remove(_ i: ShelfItem)
                                   func clear(); func url(for i: ShelfItem) -> URL; func airDrop(_ items: [ShelfItem]); func reveal(_ i: ShelfItem)
NotesService: ObservableObject     @Published var text: String (persisted, debounced); @Published private(set) var todos: [TodoItem]
                                   func addTodo(_ text: String); func toggle(_ t: TodoItem); func remove(_ t: TodoItem); func clearDone()
LyricsService: ObservableObject    @Published private(set) var lines: [LyricLine]; @Published private(set) var plain: String
                                   @Published private(set) var isLoading: Bool; func start()   // follows NowPlayingService.trackChanged, caches by trackKey
                                   func currentIndex(at elapsed: Double) -> Int?
WeatherService: ObservableObject   @Published private(set) var snapshot: WeatherSnapshot?; @Published private(set) var status: String
                                   func start(); func refresh()     // every 30 min; city → geocode, empty city → CoreLocation (one-shot)
SystemMonitorService: ObservableObject  @Published private(set) var cpu: Double; memoryUsed: UInt64; memoryTotal: UInt64
                                   netIn: Double; netOut: Double; diskFree: Int64; diskTotal: Int64; batteryCycles: Int?; batteryHealth: Double?
                                   func setActive(_ on: Bool)       // samples every 2 s only while the System/Home tab is visible
AIUsageService: ObservableObject   @Published private(set) var claudeBlock: UsageBlock?; claudeToday: (TokenUsage, Double)?
                                   claudeWeek: (usage: TokenUsage, cost: Double, count: Int)?; claudeMaxBlockTokens: Int; codex: CodexRateLimits?
                                   @Published private(set) var lastUpdated: Date?; func start(); func refresh()  // background queue, 60 s
AudioDeviceService: ObservableObject  struct AudioDevice: Identifiable, Equatable { id: UInt32; name: String; isOutput: Bool }
                                   @Published private(set) var outputs: [AudioDevice]; @Published private(set) var currentOutputID: UInt32?
                                   @Published private(set) var isMicMuted: Bool; func start(); func select(_ d: AudioDevice); func toggleMicMute()
KeepAwakeService: ObservableObject @Published private(set) var isOn: Bool; func toggle(); func set(_ on: Bool)
PrivacyMonitor                     let changes: PassthroughSubject<(SensorKind, Bool), Never>; func start()   // 1.5 s poll
CapsLockMonitor                    let changes: PassthroughSubject<Bool, Never>; func start()                // 0.25 s poll of NSEvent.modifierFlags
DownloadsMonitor                   let events: PassthroughSubject<(name: String, finished: Bool), Never>; func start()  // ~/Downloads, 1 s poll
HotKeyService                      func start(); var onTogglePanel: (() -> Void)?; var onClipboard: (() -> Void)?  // ⌃⌥N, ⌃⌥V
ScreenLock (enum)                  static func lock()
```

#### Views (v3)
- `ExpandedView` = `PanelHeader` (tab icons left of the notch gap, toggles right: Keep Awake `cup.and.saucer.fill`, mic, pin, lock, gear) + tab body.
  Notch gap only when `notch.hasPhysicalNotch`. Each tab view lives in `Views/Tabs/<Name>Tab.swift`: `HomeTab`, `NowPlayingTab`,
  `TimerTab`, `ClipboardTab`, `ShelfTab`, `NotesTab`, `SystemTab`, `AIUsageTab`.
- Compact views: `CompactTimerView` (ring + "12:34"), `LyricsCompactView` (artwork/visualiser row + current line, 12 pt, centred, 1 line),
  plus activity views for every new `ActivityKind` in `ActivityView`.
- The panel's text fields (clipboard search, notes, to-do) make the panel key on focus (`NSApp`-free: `panel.makeKey()` via
  `NotificationCenter` `.dynaNotchWantsKey`); Esc collapses.
- Settings panes added: **Panel** (tabs on/off & order, hotkeys, non-notch style), **Productivity** (timer, clipboard, shelf, notes),
  **Weather & AI** (city, unit, AI usage). Live Activities pane gains download / privacy / caps lock / notify toggles.

### 6.5 v3.1 additions (glass, header, device batteries, welcome)

```swift
// Core — DeviceBattery.swift
public enum DeviceKind: String, Equatable, Hashable, CaseIterable { case mac, mouse, keyboard, trackpad, headphones, airpods, gamepad, other
    public var symbolName: String }   // "laptopcomputer","computermouse.fill","keyboard.fill","rectangle.and.hand.point.up.left.fill",
                                      // "headphones","airpods.pro","gamecontroller.fill","dot.radiowaves.left.and.right"
public struct DeviceBattery: Equatable, Identifiable {
    public var id: String                 // bluetooth address, or "mac"
    public var name: String; public var kind: DeviceKind
    public var level: Int?                // 0...100 main/combined level
    public var left: Int?; public var right: Int?; public var caseLevel: Int?   // AirPods-style
    public var isCharging: Bool; public var detail: String?   // e.g. "Health 100% · 10 cycles · 34°C"
    public var displayLevel: Int?         // level ?? min(left, right) ?? caseLevel
}
public enum BluetoothProfilerParser {
    /// `system_profiler -json SPBluetoothDataType` → connected devices (device_connected), battery keys
    /// device_batteryLevelMain|Left|Right|Case ("86 %", NBSP tolerated), kind from device_minorType + name.
    public static func parse(_ data: Data) -> [DeviceBattery]
    public static func percent(_ s: String) -> Int?
}
public enum DeviceBatteryMerge {
    /// Merges sources by id (falls back to case-insensitive name); later sources fill nil levels only.
    public static func merge(_ sources: [[DeviceBattery]]) -> [DeviceBattery]   // sorted: mac first, then by name
}
public enum IslandMaterial: String, Equatable, Hashable, CaseIterable { case glass, black; public var title: String }

// App
DeviceBatteryService: ObservableObject  @Published private(set) var devices: [DeviceBattery]   // mac first
    func start(); func refresh()   // 60 s: system_profiler (background), Apple HID BatteryPercent (IOKit),
                                   // CoreBluetooth GATT 0x180F/0x2A19 for connected BLE peripherals; Mac from IOPS + AppleSmartBattery
QuickActions (enum)  static func captureScreenshot(); static func pickColor()   // colour hex → pasteboard
AppSettings: islandMaterial: IslandMaterial = .glass; hasSeenWelcome: Bool = false (key dn.hasSeenWelcome)
WelcomeController  show()   // borderless full-screen-ish window: animated handwritten "hello" → "Welcome to DynaNotch" → Get Started,
                            // then tip cards anchored under the notch. Menu "Show Welcome…", URL dynanotch://welcome.
Views: `HelloShape` (single-stroke cursive path, animated with .trim), `GlassBackground` (NSVisualEffectView .hudWindow,
behind-window, dark), `PanelHeader` = TabPill + TabMenu (⋯) | BatteryPill · timer · output · keep awake · ActionsMenu (⋯) · pin · lock.
```

### 6.6 v3.2 additions (Notchy settings audit, §2d)

```swift
// Core (all tested in V32Tests.swift)
Calculator.evaluate(_:) -> Double?; Calculator.format(_:) -> String          // safe recursive-descent parser
SearchEngine { id, name, shortcut, template("%@"), symbol; url(for:) }; QuickSearch.builtIn; QuickSearch.resolve(_:engines:defaultEngineID:)
EmojiEntry { character, name, group }; EmojiGroup (8); EmojiCatalog.all / search(_:)
BreakKind (lookAway, standUp, drinkWater); BreakScheduler.due(now:start:intervals:isQuiet:) / reset(now:)
PomodoroStats.recordSession(at:) / today(now:) / streak(now:) / total     (Codable)
BatterySample, BatteryHistory.append(_:) / samples(since:)                 (Codable, 5-min spacing, 30-day retention)
ScreenTimeLedger.record(app:name:from:to:) / top(on:limit:) / total(on:) / prune(keepDays:now:)   (Codable)
MeetingLink.detect(in: [String?]) -> URL?                                  // Zoom, Meet, Teams, Webex, Whereby, Slack, Discord
AccessoryAlert (.low / .full), AccessoryAlertDetector(lowThreshold:).update(_:)
MaterialPreset (graphite, onyx, carbon, frost, satin, mist, clear; tintWhite, tintOpacity, opacity(translucency:))
AnimationStyle (calm, snappy, bouncy; spring, response(speed:)); TimeFormat (system, h12, h24; template)
PanelTab += calculator, emoji, quickSearch, launcher, shortcuts, reminders, mirror

// AppSettings (+ SettingsKey "dn."+name)
materialPreset = .carbon; panelTranslucency = 1.0 (0…1); animationStyle = .calm; animationSpeed = 1.0 (0.5…2)
colorCodedLevels = false; closedPillClock = false; timeFormat = .system; helloIntro = false
defaultTab = "previous" ("previous" | PanelTab raw); openOnCurrentActivity = true; idleTimeout = 0 (s, 0 = never)
invisibleUntilHover = false; notificationDuration = 4.5 (1…15); lyricsOffset = 0 (s, −5…5)
pomodoroAutoContinue = true; breakLookAway = false; breakStandUp = false; standUpMinutes = 60; breakDrinkWater = false
drinkWaterMinutes = 45; lowBatteryThreshold = 20 (5…50); fullChargeActivity = false; accessoryAlerts = true
clipboardIgnoredApps = "<password-manager bundle ids>"; clipboardAutoClearMinutes = 0; pasteWithNumbers = true
meetingAlert = false; meetingAlertMinutes = 1; screenTimeEnabled = true; quickSearchEngine = "google"
launcherApps = "" (bundle ids, comma); colorFormat = "hex" (hex|rgb|hsl); driveActivity = true; screenshotToShelf = false
headerButtons = "battery,output,keepAwake,actions,pin,lock" (+ timer, screenshot, colorPicker, mic)
func restoreDefaults(_ keys: [String]); func exportJSON() -> Data; func importJSON(_ data: Data) -> Bool

// New services (skeleton → systems agent)
BreakReminderService.start(); PomodoroStatsService (@Published stats); BatteryHistoryService (@Published history)
ScreenTimeService (@Published ledger; func today(limit:) -> [(app, name, seconds)]); MeetingAlertController.start()
DriveMonitor.start(); ColorHistory (@Published colors: [String])
// New tab services (→ tabs agent)
LauncherService (pinned + running apps, search installed apps, launch); ShortcutsService (`shortcuts list|run`)
RemindersService (EventKit reminders: access, list, add, complete); CameraService (AVCaptureSession for Mirror)
```
v3.2 integration notes (2026-10-26):
- `HeaderButtonID` (Core, Panel.swift: battery, timer, output, keepAwake, mic, screenshot, colorPicker, actions, pin, lock;
  `parseList` / `serialize(Set)` in canonical order) drives `PanelHeader` from `settings.headerButtons`.
- `PanelTab.migrate(stored:known:)` + UserDefaults `dn.knownTabs` (not in `SettingsKey.all`): tabs added by an update are
  inserted once into an existing tab list (before System / AI Usage); tabs the user removed stay removed.
- Two-finger swipes act only on the compact island; while expanded, scrolling belongs to the tab lists.
- `CameraService.isOwnUse` suppresses the camera privacy activity while (and 4 s after) the Mirror tab uses the camera.
- `BatteryService.fullyCharged` → "Fully Charged" notification island (settings.fullChargeActivity).
- `notchDisplayStyle: NonNotchStyle = .notch` (key `dn.notchDisplayStyle`): `.pill` on a notch display makes the view model
  lay out with non-notch metrics (`notch` = effective, `screenNotch` = measured) and `topInset = notch height + pillTopInset`;
  `vm.isOnNotchDisplay` is the hardware fact. Settings → Appearance shows visual `ShapeChoiceRow` cards per display kind.
- v3.3 (P1 of §2e): settings `pillScale`, `pillHeightOffset`, `screenSharingPrivacy`, `hideWhileMirroring`, `fullscreenScope`
  (Core `FullscreenScope`), `autoCollapse`, `quietDuringFocus`, `peekOnHover`, `mediaKeysControlPlayer`,
  `preventMusicAutoLaunch`, `meetingOnlyWithLink`, `hiddenCalendars`, `calendarHotkeys`, `timerHoverControls`,
  `clipboardCaptureSound`, `shelfRetention` (Core `ShelfRetention`), `screenshotFolder`, `unplugActivity`, `fullChargeLevel`.
  Core `IslandLayout`: `timerControlsSize/Radii`, `unpluggedSide`, `pillScaleRange`, `scaled(_:by:)`;
  `ActivityKind.isQuietedDuringFocus`. App: `CalendarService.calendars` / `CalendarInfo` / `nextMeetingURL()`,
  `KeepAwakeService.keepAwake(for:)` + `until`, `ScreenRecorder`, `MusicLaunchGuard`, `PermissionDiagnostics`,
  `Permissions.screenRecordingGranted`, `.dynaNotchAppNotification` (services → island message, not gated by the notify
  toggle), `DemoActivity.unplug`. Test hooks: `dynanotch://ui/override?fullscreen=1&front=<bundle>&mirror=1&focus=1`,
  `dynanotch://ui/mediakey?code=16[&up=1]`. Never wait for builds with `pgrep -f "./build.sh"` inside a shell loop (it
  matches itself); use `pgrep -fl "^/bin/bash ./build.sh"`.
- Welcome (supersedes §6.5; owner request 2026-10-26: no buttons, slides, ends in the app):
  `WelcomeController.show(greetingOnly:)` opens one window pinned to the top centre (level `.mainMenu + 4`);
  `WelcomeView(notch:greetingOnly:handOffSize:closer:onHandOff:)` is a black island that springs out of the notch →
  hello draws (~3.3 s) → "Welcome to DynaNotch" (2.2 s, no button) → first launch only: `WelcomeSlidesView`, the tips as
  self-advancing slides (3.4 s each, push-from-right transition, Stories-style progress bar; click / → / space = next,
  ← = back, Skip) → **hand-off**: the island morphs to the real panel's size (`vm.expandedSize`), the controller opens
  the panel on Home underneath and fades the pop-up out; the panel collapses 3 s later unless hovered or pinned.
  Every ending (last slide, Skip, Esc) hands off. Test: `dynanotch://ui/click?window=welcome&id=welcome.slides|welcome.skip`.
- Shared helpers: `Services/WellbeingSupport.swift` (`AppDataStore` JSON in App Support / UserDefaults, `UserPresence`
  lock/sleep/idle), `Views/Tabs/QuickSearchTab.swift` (`PanelInputField`, `PanelPasteboard`, `CopiedBadge`),
  `Views/Alerts/MeetingAlertView.swift`. Settings window is 820×600 with grouped sidebar + search.

Ownership this round: tech lead = Core, Model, Window, App, PanelHeader/IslandRootView/ActivityView; **tabs agent** =
`Views/Tabs/{Calculator,Emoji,QuickSearch,Launcher,Shortcuts,Reminders,Mirror}Tab.swift`, SystemTab, and the four tab
services; **settings agent** = `Views/Settings/**`; **systems agent** = the remaining `Services/**` + `Views/Tabs/ClipboardTab.swift`
+ `Views/Alerts/**`.

### 6.7 v3.4 additions (§2e P2) — contract

Core `Workspace.swift` (tested in `V34Tests.swift`): `HotKeyAction` (togglePanel, clipboard, hide, commandPalette,
emergencyQuit, joinMeeting, openCalendar, pastePlainText, startPomodoro, toggleKeepAwake), `HotKeyBinding` (Carbon key code +
modifier mask, `display` "⌃⌥N"), `HotKeyMap` (settings string "action=code:mods;tab.timer=…", only diffs from `defaults`
stored, "key=" clears), `KnockKey`, `KnockAction` (+ "1=…,2=…" map), `KnockDetector` (press/release/interrupt/settle),
`HomeCard` (13 cards, `span`, `defaultList`, parse/serialize), `ClockContent`, `PanelSizing`, `TrackInfoMode`,
`AlertCategory` + `AlertSounds` ("timers=Glass,battery=None"), `SavedLink`, `JSONList`, `ListenEntry`/`ListeningHistory`,
`TrafficLedger`. `TimerEngine.repeatCountdown`. `WeatherSnapshot.sunrise/sunset`. `DisplayMode.external`.
`PanelTab` += `calendar`, `quickSettings`; `HeaderButtonID` += stopwatch, pomodoro, volume, scanQR, ports, systemStats.

Settings (AppSettings "MARK: v3.4"): clockContent, clockWithActivities, panelWidth (520–820), panelSizing, panelMaxHeight
(150–320), panelFillHex, pillMatchesPanel, trackInfoMode, desktopLyrics, edgeGlow, alertSounds, hotkeyBindings, knockEnabled,
knockKey, knockActions, copyTwiceToOpen, offerCleanCopy, customSearchEngines (JSON [SearchEngine]), homeCards, homeColumns
(2–4), worldClocks (TZ ids), savedLinks (JSON [SavedLink]), repeatTimer, repeatAlarm, pomodoroOnly, aiLimitWarnings,
aiLimitWarnPercent (50–95), aiMenuBarReadout, aiHidePersonalInfo, batteryInMenuBar, drainWarnings, dmgInstallOffer,
nextMeetingInMenuBar, listeningHistory, defaultMusicApp.

App: `AppActions.shared` (App/AppActions.swift) performs HotKeyAction / KnockAction / `toggleTab(_:)` for shortcuts, knocks,
the palette and Quick Settings; the view model registers itself and offers `togglePanelFromKeyboard()`, `openFocused(_:)`,
`toggleUserHidden()`/`isUserHidden`. `CommandPaletteController`, `KnockMonitor`, `HotKeyService.reload/suspend/resume`,
`ClipboardService.pasteCurrentAsPlainText()`, `TimerService.isAlarmRinging/stopAlarm()`, `KeepAwakeService.keepAwake(until:)`,
`AlertSoundPlayer.play(_:)/preview(_:)`, and in `Services/WorkspaceServices.swift`: `NetworkInfoService`, `TrafficService`,
`ListeningHistoryService`, `AppMaintenance`, `ShellHookInstaller`, `CodingAgentsService` (+`CodingAgentSession`),
`BluetoothConnectService` (+`PairedDevice`).

Ownership (v3.4 wave): **island agent** = Model/IslandViewModel.swift, Window/**, top-level Views/*.swift (not PanelHeader),
Core IslandLayout/IslandEngine · **input agent** = HotKeyService, KnockMonitor, ClipboardService, App/AppActions.swift,
App/CommandPalette*.swift, Views/Tabs/ClipboardTab.swift · **tabs agent** = Views/Tabs/** (not Clipboard), PanelHeader.swift,
CalendarService, CodingAgentsService, BluetoothConnectService (+ new tab helpers) · **services agent** = the rest of
Services/**, App/StatusItemController.swift, Views/Alerts/** · **settings agent** = Views/Settings/**. The tech lead owns
Core (except IslandLayout/Engine), AppSettings, AppDelegate, UITestDriver, CLAUDE.md. Installing + UI-testing the app is
serialised with the scratchpad `applock.sh` lock.

### 6.8 Header cards + Settings scene (2026-10-26, owner bug reports)
- `vm.headerCard: HeaderCard?` (`.battery`, `.sound`; `showsBatteries` kept as a computed alias). Header buttons open
  their card on **hover** (rest 0.18 s) or click; a hover-opened card closes 0.35 s after the pointer leaves button and
  card, a click-opened one stays until clicked again / elsewhere. Hit-testing: `Window/HoverRegions.swift`
  (`.hoverRegion("hover.battery" | "hover.sound" | "hover.card")`), queried by `IslandWindowController.updateHeaderHover`
  on every pointer move (so the scripted test pointer works too).
- Sound: `SoundButton` (glyph follows the volume) + `SoundCard` (live `VolumeSlider`, mute, output devices). Header
  buttons `.output` and `.volume` both show it, once. `OutputMenu` / `VolumeMenu` removed.
- The SwiftUI `Settings` scene is only a placeholder; macOS opens it by itself (⌘,, "Settings…", window restoration)
  as an empty "DynaNotch Settings" window. `SettingsSceneRedirect` closes it and opens `SettingsWindowController`
  (not during the first 3 s after launch, when it can only be a restored window); the app menu's "Settings… ⌘," is
  replaced to open the real window; the real window has `isRestorable = false`.
- Test hooks: state.json `headerCard`; `dynanotch://ui/appMenuSettings`, `dynanotch://ui/systemSettingsAction`.

---

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

---

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

---

## 9. Conventions
- Swift 5 mode, 4-space indent, `final class` by default, no force unwraps except `static let` resources, no `print` spam (use `os.Logger(subsystem: "com.tanim.dynanotch", category: …)`).
- Each app file starts with the imports it needs (`import AppKit`, `import SwiftUI`, `import Combine`, `import DynaNotchCore` …). Never rely on transitive imports.
- Domain logic that can be pure goes in Core and gets tests.
- Private APIs (MediaRemote, DisplayServices) are always loaded with `dlopen`/`dlsym` and every call is nil-guarded; the app must keep working when they are missing.
- Never write the bare type name `FocusState` in a file that imports SwiftUI (clashes with SwiftUI.FocusState); use `DynaNotchCore.FocusState`.
- `CalendarAccess` is nested in `CalendarService` (plus a top-level typealias); `NowPlayingSource` lives in its own file; `IslandViewModel` also exposes `settings` and `reduceMotion`.
- If a future Xcode reports main-actor isolation *errors* for the plain `NSObject` controllers, make them conform to `NSWindowDelegate` (inherits main-actor isolation) rather than adding `@MainActor` everywhere.
- Owner's toolchain (verified 2026-10-16): macOS 27.0.1, Xcode 27.0, Swift 6.4. With this SDK `import Foundation` does NOT bring CoreGraphics' Swift overlay: every Core file imports CoreGraphics under `#if canImport(CoreGraphics)`.
- `scripts/build_agent.sh` (run by the owner in Terminal) lets Claude run fixed build/test/log/screenshot commands via `.agent/request`; the app handles `dynanotch://simulate/<demo>|expand|collapse|settings` for scripted checks.
- Claude now runs directly on the owner's Mac (since 2026-10-26): build/test with `swift build` / `swift test` directly; the
  `.agent/request` relay is only needed from a sandbox. Shell `screencapture` is not permitted, so visual checks use
  `open "dynanotch://snapshot/<name>"` → `~/Library/Application Support/DynaNotch/Snapshots/<name>.png` (the app renders its own canvas).
- **Scripted UI tests (no Accessibility needed)** — `App/UITestDriver.swift` sends real mouse events into our own windows:
  `dynanotch://ui/pointer?x=&y=` (simulated pointer in island-canvas points; no query = real pointer),
  `dynanotch://ui/click?window=island|settings&id=<uiTestID>` (or `&x=&y=`, `&alt=1`),
  `dynanotch://ui/menu?item=<title>&delay=<s>&away=1` (the next menu that opens picks that item, pointer moves onto the menu),
  `dynanotch://set?dn.<key>=<value>` (changes settings through AppSettings like the UI), `dynanotch://state` →
  `Snapshots/state.json` (presentation, tabs, pill/inset, screen, test-ID frames, last menu result). Tag new controls with
  `.uiTestID("…")`. Every feature is tested this way, as a user would use it, before it is marked ✅.
- Settings pages render with `open "dynanotch://snapshot-settings/<SettingsPage raw>"` → `Snapshots/settings-<page>.png`;
  the welcome pop-up with `dynanotch://welcome` + `dynanotch://snapshot-welcome/<name>`.
- More URLs: `dynanotch://tab/<panelTab>`, `dynanotch://timer/<minutes>`, `dynanotch://notify?title=&body=&symbol=&duration=`
  (e.g. from a Claude Code `Notification`/`Stop` hook: `open -g "dynanotch://notify?title=Claude%20Code&body=Done&symbol=sparkles"`).
- Parallel agents must build with distinct `swift build --scratch-path <dir>` to avoid SwiftPM lock contention.
- Persistent app data lives in `~/Library/Application Support/DynaNotch/` (clipboard.json, Clips/, Snapshots/) and UserDefaults
  keys `dn.data.*` (notes, todos, shelf). Settings keys stay `dn.<property>`.
- Commands: `./build.sh` (test, build, install, launch), `./build.sh --dmg`, `./build.sh --no-install`, `swift test`, `scripts/check.sh`, logs: `log stream --predicate 'subsystem == "com.tanim.dynanotch"'`.

---

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
