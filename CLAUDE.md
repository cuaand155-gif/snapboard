# CLAUDE.md

Snapboard is Alexi's personal macOS menu bar app: drag a window with Shift held to snap it into zones she draws per screen, plus desktop widgets (clock, Lifeboard today, weather, now playing). Spec: the "Snap + Widgets for Mac — Product Spec" Claude doc. The owner isn't a developer: keep `README.md` click-by-click and all on-screen text in plain language.

## Layout

- `Sources/SnapboardCore/` — pure logic, no AppKit: zone layouts as a split tree in unit space (y down), coordinate conversion (unit / AppKit / Accessibility), the widget grid, saved state, and the Lifeboard feed model. Put new decision logic here with a test in `Tests/SnapboardCoreTests/`.
- `Sources/Snapboard/` — the app: `AppDelegate` (menu bar, first launch), `Snapper` (Shift-drag snapping), `ZoneOverlay`, `LayoutEditor` (SwiftUI), `Hotkeys` (Carbon, ⌃⌥ + arrows/Return), `WindowMover` (Accessibility API), `Widgets` (panels at desktop level, feed, now playing), `SettingsView`, `AppModel` (settings JSON + Keychain).
- `scripts/build-app.sh` — builds `build/Snapboard.app` (Info.plist with `LSUIElement`, ad-hoc signed).

## Commands (on a Mac with Xcode)

```bash
swift test                    # core tests
./scripts/build-app.sh        # build the app
```

Cloud sessions run on Linux without Swift, so code here can't be compiled or run there: say so, and have Alexi build on her Mac.

## Rules

- Lifeboard data is read only: `GET /api/widgets` with `Authorization: Bearer <WIDGET_TOKEN>` (Lifeboard `lib/widget-feed-rules.js`). The token lives in the Keychain, never in the settings file or the code.
- Saved state is `~/Library/Application Support/Snapboard/settings.json`; new fields must decode with a default so older files still load (see `SavedState.init(from:)`).
- Snapping must never affect a drag without Shift, or a Shift-drag that doesn't move a window.
