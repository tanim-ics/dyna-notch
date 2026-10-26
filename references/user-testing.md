# Test like a user: in-app test hooks

Build these into the app in the first week (debug-safe: they only read state or act like a user would):

| Hook | Purpose |
|---|---|
| `scheme://state` → `state.json` | What is visible: screen/presentation, selected tab, open popovers, flags, test-ID frames |
| `scheme://snapshot/<name>` | The app renders its own window(s) to PNG (`cacheDisplay` / ImageRenderer) — works without screen-recording permission |
| `scheme://ui/click?window=…&id=<testID>` | Real mouse-down/up events into our own window at a tagged control |
| `scheme://ui/pointer?x=&y=` | Simulated pointer for hover logic (route hover through the app's own hit-testing) |
| `scheme://ui/menu?item=<title>` | Next menu that opens picks this item |
| `scheme://ui/action?name=<action>` | Fire a shortcut / gesture action without real keys |
| `scheme://set?key=value` | Change a setting through the settings model |
| `scheme://simulate/<event>` | Events you can't cause on demand (battery, devices, notifications) |

- Tag controls with a `.uiTestID("…")` modifier backed by a registry of live frames.
- `scripts/ui-regression.sh`: open each screen → assert state → snapshot renders (size > threshold); cards open/close;
  every simulated event; palette/search; every settings page. Exit code = failures. Wire into `check.sh --ui`.
- Live data (music, weather, time) makes pixel goldens flaky — assert state instead.
- The user may be using the machine: pin panels open during tests, expect their clicks, restore their settings.
- Verify outcomes on the system too where possible (`osascript` volume, `defaults read`, files created/removed).
