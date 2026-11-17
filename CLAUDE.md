# CLAUDE.md

Snapboard is Alexi's personal macOS menu bar app: Shift-drag window snapping, desktop widgets, workspaces, a shared item library and launcher, action sequences and keyboard triggers, custom floating docks and menu groups, native Dock presets, and screen recording. The owner isn't a developer: keep `README.md` click-by-click and all on-screen text in plain language.

Before project work, read the canonical [Snapboard project packet](https://github.com/cuaand155-gif/ai-system/blob/main/docs/projects/snapboard/packet.md) in `ai-system` and any project files it links. Check Life Hub for live tasks and status. If a source is unavailable, report it as unverified rather than assuming its contents.

## Layout

- `Sources/SnapboardCore/` — pure logic, no AppKit: layouts, widget grid, saved state, item library, actions, surface definitions, Dock snapshots, and Lifeboard feed model. Put new decision logic here with a test in `Tests/SnapboardCoreTests/`.
- `Sources/Snapboard/` — the app: `AppDelegate` (menu bar, first launch), `Snapper` (Shift-drag snapping), `ZoneOverlay`, `LayoutEditor`, `Hotkeys`, `WindowMover`, `Widgets`, `SettingsView`, `AppModel`, and the library, automation, custom surfaces, Dock preset, and recording windows.
- `scripts/build-app.sh` — builds `build/Snapboard.app` (Info.plist with `LSUIElement`, ad-hoc signed).

## Commands (on a Mac with Xcode)

```bash
swift test                    # core tests
./scripts/build-app.sh        # build the app
```

The GitHub macOS workflow also runs tests and builds a universal app. On a Mac without full Xcode, SwiftPM may fail before compiling source; use the hosted macOS check for the release gate.

## Rules

- Lifeboard data is read only: `GET /api/widgets` with `Authorization: Bearer <WIDGET_TOKEN>` (Lifeboard `lib/widget-feed-rules.js`). The token lives in the Keychain, never in the settings file or the code.
- Saved state is `~/Library/Application Support/Snapboard/settings.json`; new fields must decode with a default so older files still load (see `SavedState.init(from:)`).
- Snapping must never affect a drag without Shift, or a Shift-drag that doesn't move a window.
