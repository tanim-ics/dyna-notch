# macOS / SwiftUI / AppKit gotchas

- **TCC**: every protected API needs its Info.plist usage string or the app is killed on first use; the
  "responsible process" is whoever launched you — launch test builds with `open`, not from a shell.
- **Signing**: ad-hoc + stable designated requirement (`codesign -r='designated => identifier "<id>"'`) so grants
  survive rebuilds. Hardened runtime blocks DYLD_INSERT_LIBRARIES (sanitizers) — test builds without it.
- **Shell limits**: `screencapture` and synthetic events usually aren't permitted → in-app snapshots and UI driver.
- **Floating panels**: `NSPanel` `.nonactivatingPanel`, high level, `constrainFrameRect` passthrough, toggle
  `ignoresMouseEvents` from pointer hit-tests; make key only for text fields and hand focus back after.
- **SwiftUI Settings scene**: a placeholder `Settings {}` gets opened by ⌘, and restoration → redirect to your window.
- **Menus in panels**: choosing an item moves the pointer outside → hold the panel while menus track.
- **Timers/animation**: no `TimelineView(.animation)` for decoration; no `Timer.publish` in View structs; use
  `tolerance`. `CGWindowListCopyWindowInfo` is expensive — don't poll it.
- **Swift 6 toolchain in Swift 5 mode**: avoid async/actors in AppKit glue if you can't compile on the target first;
  GCD + Combine are predictable. With newer SDKs `import Foundation` may not bring CoreGraphics — import explicitly.
- **Scripts**: macOS ships bash 3.2 — keep embedded Python/heredocs in separate files; test scripts on the Mac.
- **SwiftPM**: one build dir per concurrent build (`--scratch-path`); `.build-*/` in `.gitignore`.
- **Private frameworks**: `dlopen`/`dlsym`, nil-guard everything, keep a fallback.
