# DynaNotch 🖥️

A Dynamic Island–style floating notch for macOS — inspired by [Alcove](https://tryalcove.com/).
Sits at the top-center of your screen (overlapping the hardware notch on notch-equipped Macs), expands on hover, and shows live music, volume HUDs and notifications.

---

## Quick Start

```bash
cd ~/Desktop/dyna-notch
bash build_dmg.sh          # builds the app + creates DynaNotch.dmg + installs + launches
```

> First build takes 2–4 minutes. Subsequent builds are much faster.

**DMG location:** `~/Desktop/dyna-notch/DynaNotch.dmg`

To install manually: double-click `DynaNotch.dmg` → drag **DynaNotch** → **Applications**.

---

## Features

| Feature | Description |
|---|---|
| Dynamic Island pill | Floating black pill at top-center of screen, above the menu bar |
| Expand on hover | Spring-animated expansion reveals full content |
| Now Playing | Album art · title · artist · progress bar · play/pause/skip |
| Equalizer bars | Animated bars in the collapsed pill while music plays |
| Volume HUD | Auto-pops when system volume changes, shows percentage |
| Notifications | App notifications rendered inside the notch |
| Swipe to dismiss | Drag down on the expanded notch to collapse it |
| Menu bar icon | Pill icon → Settings · Quit |
| Settings panel | Launch at login · HUD toggles · collapse duration |

---

## Architecture

```
DynaNotch/
│
├── App/
│   ├── DynaNotchApp.swift              ← @main entry; mounts Settings scene
│   └── AppDelegate.swift               ← Hides Dock icon (LSUIElement),
│                                          creates menu bar icon + NotchWindowController
│
├── Window/
│   ├── NotchPanel.swift                ← Custom NSPanel subclass
│   │                                      • borderless + nonactivatingPanel style
│   │                                      • Window level: statusBar + 2 (above menu bar)
│   │                                      • transparent background, no shadow, not movable
│   │                                      • canJoinAllSpaces so it persists across Spaces
│   │
│   └── NotchWindowController.swift     ← Positions the panel at top-center of main screen
│                                          • Reads screen.safeAreaInsets.top to detect notch
│                                          • Listens for screen-change notifications
│                                          • animateTo(size:) resizes panel with CAMediaTimingFunction
│
├── ViewModels/
│   ├── NotchViewModel.swift            ← Central state machine (ObservableObject)
│   │                                      • isExpanded: Bool  (drives all animations)
│   │                                      • activeContent: NotchContent enum
│   │                                        (.music | .notification | .hud | .none)
│   │                                      • setHovering(_:) — collapses after 1.8 s delay
│   │                                      • showHUD(_:) — expands for 2.2 s then collapses
│   │                                      • showNotification(_:) — expands for 4 s
│   │
│   ├── MusicViewModel.swift            ← MediaRemote private framework bridge
│   │                                      • Loads /System/Library/PrivateFrameworks/
│   │                                        MediaRemote.framework via CFBundleCreate
│   │                                      • MRMediaRemoteGetNowPlayingInfo — fetches track data
│   │                                      • MRMediaRemoteSendCommand — play/pause/skip
│   │                                      • Observes kMRMediaRemoteNowPlayingInfo
│   │                                        DidChangeNotification for live updates
│   │                                      • Timer interpolates progress between fetches
│   │
│   └── SystemEventsViewModel.swift     ← CoreAudio property listener
│                                          • Watches kAudioHardwareServiceDeviceProperty_
│                                            VirtualMasterVolume on default output device
│                                          • Triggers NotchViewModel.showHUD(.volume) on change
│
└── Views/
    ├── NotchContainerView.swift        ← Root SwiftUI view inside the panel
    │                                      • RoundedRectangle pill (cornerRadius 18→26)
    │                                      • onHover → NotchViewModel.setHovering
    │                                      • DragGesture (down > 30 pt) → collapse
    │                                      • Switches between CollapsedView / ExpandedView
    │                                      • EqualizerBarsView — 5 animated capsules
    │
    ├── MusicPlayerView.swift           ← Expanded music content
    │                                      • Album art (NSImage from MediaRemote artwork data)
    │                                      • Title + artist labels
    │                                      • NotchProgressStyle (custom ProgressViewStyle)
    │                                      • Play/pause · prev · next buttons with press animation
    │
    ├── HUDView.swift                   ← Volume / brightness / battery HUD
    │                                      • SF Symbol icon (adapts to volume level)
    │                                      • Colored capsule progress bar
    │                                      • Percentage label
    │
    ├── NotificationView.swift          ← Notification card
    │                                      • App icon · app name · title · body
    │
    └── SettingsView.swift              ← SwiftUI Form in Settings scene
                                           • Launch at login · music · volume HUD toggles
                                           • Collapse duration slider
```

---

## How the Window Sits Above the Menu Bar

macOS window levels (ascending):
```
Normal      =  0
Floating    =  3
Status bar  = 25   ← menu bar items live here
DynaNotch   = 27   ← statusBar + 2, appears above everything
```

The `NotchPanel` uses `NSWindow.Level(rawValue: CGWindowLevelForKey(.statusWindow) + 2)`.
On notch Macs, `screen.safeAreaInsets.top > 0`, so the panel height is set to cover the notch exactly. On non-notch Macs it floats as a pill just below the top edge.

---

## MediaRemote (Private Framework)

Apple doesn't expose a public API for reading Now Playing info from other apps.
DynaNotch (like Alcove, NotchNook, and many others) uses the private `MediaRemote.framework`:

```swift
// Load the framework
let bundle = CFBundleCreate(kCFAllocatorDefault,
    NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework"))

// Get a function pointer
let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo")
let fn  = unsafeBitCast(ptr, to: MRGetNowPlayingInfoFn.self)

// Call it
fn(.main) { info in
    let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String
    let art   = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
}
```

Commands sent via `MRMediaRemoteSendCommand`:
| Value | Action |
|---|---|
| 0 | Play |
| 2 | Toggle play/pause |
| 4 | Next track |
| 5 | Previous track |

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later (to build)

## Files in This Repo

```
dyna-notch/
├── DynaNotch/              ← All Swift source + assets
├── DynaNotch.xcodeproj/    ← Generated Xcode project
├── build/                  ← Created by build_dmg.sh (gitignore this)
├── DynaNotch.dmg           ← Final distributable (created by build_dmg.sh)
├── build_dmg.sh            ← One-command build + DMG + install + launch
├── generate_project.py     ← Regenerates DynaNotch.xcodeproj from scratch
└── README.md               ← This file
```
