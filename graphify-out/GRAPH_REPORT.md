# Graph Report - snapboard  (2026-11-18)

## Corpus Check
- 42 files · ~31,492 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 1 file(s) not represented in the graph (top: (none) 1)

## Summary
- 924 nodes · 2143 edges · 34 communities (26 shown, 8 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 173 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `b5d87d10`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- View
- LibraryLauncherView
- DockPreferenceKey
- WidgetKind
- AppDelegate
- LayoutNode
- Identifiable
- Codable
- DropShelfItem
- SnapboardCore
- String
- AutomationEditorView
- FullscreenLauncherController
- CGRect
- steps
- Snapper
- ScreenRecorder
- Snapboard
- WindowMover
- ZoneOverlay
- Recording.swift
- RecordingWindowController
- RecordingSource
- NSScreen
- RecordingError
- RecordingView
- SettingsView
- QuickSnap
- Layout
- workspace-design.md
- Package.swift
- build-app.sh

## God Nodes (most connected - your core abstractions)
1. `ScreenRecorder` - 39 edges
2. `AppDelegate` - 38 edges
3. `CGRect` - 36 edges
4. `LibraryLauncherView` - 33 edges
5. `LayoutNode` - 33 edges
6. `SnapboardCore` - 32 edges
7. `SavedState` - 32 edges
8. `AppModel` - 29 edges
9. `AutomationEditorView` - 27 edges
10. `CustomDock` - 24 edges

## Surprising Connections (you probably didn't know these)
- `Layout` --references--> `AppDelegate`  [INFERRED]
  CLAUDE.md → Sources/Snapboard/AppDelegate.swift
- `Layout` --references--> `AppModel`  [INFERRED]
  CLAUDE.md → Sources/Snapboard/AppModel.swift
- `Layout` --references--> `Hotkeys`  [INFERRED]
  CLAUDE.md → Sources/Snapboard/Hotkeys.swift
- `Layout` --references--> `SettingsView`  [INFERRED]
  CLAUDE.md → Sources/Snapboard/SettingsView.swift
- `Layout` --references--> `Snapper`  [INFERRED]
  CLAUDE.md → Sources/Snapboard/Snapper.swift

## Import Cycles
- None detected.

## Communities (34 total, 8 thin omitted)

### Community 0 - "View"
Cohesion: 0.05
Nodes (35): CustomDockBody, .body, .buttons, .horizontal, CustomDockController, CustomDockPanelState, CustomSurfacesMenu, CustomSurfacesView (+27 more)

### Community 1 - "LibraryLauncherView"
Cohesion: 0.05
Nodes (19): AppModel, .state, Keychain, LibraryLauncherView, .activeGroup, .availableTags, .body, .launcherPane (+11 more)

### Community 2 - "DockPreferenceKey"
Cohesion: 0.05
Nodes (31): CoreFoundation, DockOperationError, .errorDescription, noRestorePoint, preferencesUnavailable, syncFailed, verificationFailed, DockPreferences (+23 more)

### Community 3 - "WidgetKind"
Cohesion: 0.05
Nodes (34): VinylWidget, .body, .bottomBar, .centerLabel, .deckBackground, .tonearm, .turntableDeck, .turntablePlatter (+26 more)

### Community 4 - "AppDelegate"
Cohesion: 0.06
Nodes (5): AppDelegate, MenuAction, .reservedShortcuts, Hotkeys, action

### Community 5 - "LayoutNode"
Cohesion: 0.07
Nodes (21): LayoutEditorView, .body, .toolbar, LayoutDivider, LayoutLimits, LayoutNode, split, zone (+13 more)

### Community 6 - "Identifiable"
Cohesion: 0.09
Nodes (20): AutomationRuntime, AutomationRule, AutomationStep, .hasValidTarget, AutomationValidation, KeyboardShortcut, .hasValidModifiers, Kind (+12 more)

### Community 7 - "Codable"
Cohesion: 0.10
Nodes (17): .snapKey, .body, .body, Feed, FeedText, FlexibleID, Last, Meds (+9 more)

### Community 8 - "DropShelfItem"
Cohesion: 0.09
Nodes (13): PDFKit, DropShelfCard, .body, DropShelfController, .isVisible, DropShelfItem, .isImage, .isPDF (+5 more)

### Community 9 - "SnapboardCore"
Cohesion: 0.10
Nodes (16): AppKit, Carbon.HIToolbox, Combine, CoreGraphics, Foundation, Security, ServiceManagement, SnapboardCore (+8 more)

### Community 10 - "String"
Cohesion: 0.12
Nodes (14): DeckStyle, .id, matteDark, transparent, warmWood, Kind, application, folder (+6 more)

### Community 11 - "AutomationEditorView"
Cohesion: 0.18
Nodes (5): AutomationEditorView, .body, .triggerSection, KeyChoice, ModifierChoice

### Community 12 - "FullscreenLauncherController"
Cohesion: 0.10
Nodes (9): AppDiscoveryModel, .filteredApps, FullscreenLauncherController, .isVisible, FullscreenLauncherView, .body, InstalledApp, LauncherAppTile (+1 more)

### Community 13 - "CGRect"
Cohesion: 0.21
Nodes (5): CGRect, .area, ScreenMath, WidgetGrid, ScreenMathTests

### Community 14 - "steps"
Cohesion: 0.11
Nodes (18): runs-on, steps, timeout-minutes, jobs, build, name, on, push (+10 more)

### Community 17 - "Snapboard"
Cohesion: 0.13
Nodes (14): 1. Download the app (easiest), 2. Or build it yourself (only if you want to), 3. First launch, Actions and triggers, Connect Lifeboard (for the Lifeboard and weather widgets), Custom surfaces, For developers, Good to know (+6 more)

### Community 18 - "WindowMover"
Cohesion: 0.23
Nodes (3): ApplicationServices, WindowMover, .isTrusted

### Community 19 - "ZoneOverlay"
Cohesion: 0.21
Nodes (3): ZoneOverlay, ZonesView, .isFlipped

### Community 21 - "Recording.swift"
Cohesion: 0.18
Nodes (10): AVFoundation, CoreImage, CoreMedia, CoreVideo, ScreenCaptureKit, RecordingAudio, .id, microphone (+2 more)

### Community 22 - "RecordingWindowController"
Cohesion: 0.20
Nodes (4): RecordingWindowController, .hasPendingExport, .isBusy, .isRecording

### Community 23 - "RecordingSource"
Cohesion: 0.24
Nodes (3): RecordingSource, .size, SendableBox

### Community 24 - "NSScreen"
Cohesion: 0.18
Nodes (5): NSScreen, .mainHeight, .underMouse, CodableRect, .rect

### Community 25 - "RecordingError"
Cohesion: 0.18
Nodes (11): RecordingError, cameraPermission, deviceStart, .errorDescription, exportSetup, invalidSource, microphonePermission, noCamera (+3 more)

### Community 26 - "RecordingView"
Cohesion: 0.31
Nodes (3): RecordingView, .body, .duration

### Community 28 - "QuickSnap"
Cohesion: 0.25
Nodes (7): QuickSnap, bottomHalf, leftHalf, maximise, rightHalf, topHalf, .unitRect

### Community 29 - "Layout"
Cohesion: 0.29
Nodes (4): Snapboard project context, Commands (on a Mac with Xcode), Layout, Rules

## Knowledge Gaps
- **136 isolated node(s):** `PackageDescription`, `.body`, `Security`, `.underMouse`, `.mainHeight` (+131 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 293 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ScreenRecorder` connect `ScreenRecorder` to `AppDelegate`, `FullscreenLauncherController`, `.stream`, `Recording.swift`, `RecordingWindowController`, `RecordingSource`, `RecordingView`?**
  _High betweenness centrality (0.079) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `AppDelegate` (e.g. with `Layout` and `CustomDockController`) actually correct?**
  _`AppDelegate` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `.body`, `Security` to the rest of the system?**
  _136 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `View` be split into smaller, more focused modules?**
  _Cohesion score 0.05362614913176711 - nodes in this community are weakly interconnected._
- **Why does `AppDelegate` connect `AppDelegate` to `View`, `WidgetKind`, `DropShelfItem`, `SnapboardCore`, `Snapper`, `Layout`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **Are the 15 inferred relationships involving `CGRect` (e.g. with `.openSettings()` and `.openWorkspaces()`) actually correct?**
  _`CGRect` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Should `LibraryLauncherView` be split into smaller, more focused modules?**
  _Cohesion score 0.05359831376091539 - nodes in this community are weakly interconnected._