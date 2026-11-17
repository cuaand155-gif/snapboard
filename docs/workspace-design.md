# Workspace controls

Snapboard uses the macOS menu bar for quick actions and a native window for edits. Keep Workspaces between Quick layout and Widgets in the menu. Put saved workspaces first, show a checkmark on the current one, then the current workspace's saved items and Manage workspaces.

The management window uses a left list for workspace selection and a right detail pane for actions. Use standard SwiftUI controls, system type, system colors, visible text labels, and plain error messages. Keep saved layout updates behind the explicit **Update saved layouts from current screens** button. **Use workspace** applies saved zones but never launches items, moves existing windows, closes apps, or changes the macOS Dock. **Open** launches one saved app or link on request. **Remove** acts on one item the user selected.

Keep this pattern aligned with the existing Settings form and layout editor. No animation or extra permission is needed.
