# DynaNotch — feature parity & roadmap

> Moved out of CLAUDE.md on 2026-10-26 (verbatim). CLAUDE.md links here; update this file when the facts change.

§ numbers below are the historical section numbers that commits and comments refer to.

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
| Lock-screen widgets | ✅ (owner saw it on a real lock) | weather card + battery rings under the clock on the main display, via a private SkyLight space (owner lifted the non-goal, DECISIONS §14); fallback: nothing drawn |

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
| Lock Screen | Weather + battery widgets under the lock-screen clock · lock / unlock sounds · Unlocked popup | ✅ |
| Face Unlock / Pointer / Typing Sounds / Desktop Pet | | ❌ |
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
| Floating pill too thin, width not adjustable | ✅ default height 36 pt (was 32 / menu-bar height); Settings → Appearance → **Pill Width** (≥ the MacBook notch width) and **Pill Height** sliders, live; sizes are on screen, so Closed Pill Size became **Pill Content Size** (scales only the icons/text) and thick pills draw true capsule ends (`IslandLayout.pillMetrics`, CONTRACTS §6.9) |
| No island on external displays (2026-10-27) | ✅ Show On → **Every Display** (an island per display, each opens on its own, hide hides all, sounds once) or Follow Mouse; picker is now a menu with a per-choice description |
| General badge stayed after allowing Accessibility | ⏳ owner action: a stale Accessibility entry (an older build) — the suggestion now says to remove it with − and allow again |
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
| Behavior | Show On: All / Built-in / Main / External (4 modes, ours has 3) | P2 | ✅ | `ScreenLocator`; 2026-10-27: + **Every Display** (one island per display, `IslandScreensCoordinator`, CONTRACTS §6.10) next to Follow Mouse |
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
| Lock Screen | Unlock island + sound when you come back | P3 | ✅ | `com.apple.screenIsLocked` / `screenIsUnlocked` distributed notifications; Settings → Lock Screen |
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
| Calls & Messages, Stocks, Cuely, Terminal, Face Unlock, Pointer, Typing Sounds, Desktop Pet | | — | ❌ | private APIs / paid data / non-goals (unchanged) |
