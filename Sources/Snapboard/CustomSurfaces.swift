import AppKit
import SwiftUI
import SnapboardCore

/// Per-panel observable state so hover and library updates mutate the existing SwiftUI view
/// without replacing `panel.contentView` (`NSHostingView`).
private final class CustomDockPanelState: ObservableObject {
    @Published var dock: CustomDock
    @Published var items: [SnapboardCore.LibraryItem]
    @Published var expanded: Bool

    init(dock: CustomDock, items: [SnapboardCore.LibraryItem], expanded: Bool) {
        self.dock = dock
        self.items = items
        self.expanded = expanded
    }
}

/// Owns the independent floating panels configured in SavedState.customDocks.
final class CustomDockController {
    private struct DockEntry {
        let panel: NSPanel
        let state: CustomDockPanelState
    }

    private var entries: [UUID: DockEntry] = [:]
    private var expanded: Set<UUID> = []
    private let onOpen: (UUID) -> Void

    init(onOpen: @escaping (UUID) -> Void) { self.onOpen = onOpen }

    /// Call after launch, screen changes, and surface or library edits.
    func sync() {
        let state = AppModel.shared.state
        let screens = NSScreen.screens
        let active = state.customDocks.filter { $0.enabled && $0.applies(to: state.surfaceWorkspaceID) }
        let activeIDs = Set(active.map(\.id))
        for id in entries.keys.filter({ !activeIDs.contains($0) }) {
            entries[id]?.panel.orderOut(nil)
            entries.removeValue(forKey: id)
            expanded.remove(id)
        }
        guard !screens.isEmpty else { return }

        var edgeCounts: [String: Int] = [:]
        for dock in active {
            guard let key = dock.renderedDisplayKey(available: screens.map(\.snapKey)),
                  let screen = screens.first(where: { $0.snapKey == key }) else { continue }
            let resolved = dock.itemIDs.compactMap { id in state.libraryItems.first(where: { $0.id == id }) }
            let isExpanded = !dock.autoHide || expanded.contains(dock.id)
            let edge = "\(key):\(dock.placement.rawValue)"
            let ordinal = edgeCounts[edge, default: 0]
            edgeCounts[edge] = ordinal + 1
            let frame = Self.frame(for: dock, itemCount: resolved.count, expanded: isExpanded,
                                   on: screen, ordinal: ordinal)
            let entry: DockEntry
            if let existing = entries[dock.id] {
                entry = existing
                if entry.state.dock != dock { entry.state.dock = dock }
                if entry.state.items != resolved { entry.state.items = resolved }
                if entry.state.expanded != isExpanded { entry.state.expanded = isExpanded }
            } else {
                let panel = makePanel()
                let panelState = CustomDockPanelState(dock: dock, items: resolved, expanded: isExpanded)
                panel.contentView = NSHostingView(rootView: CustomDockBody(
                    state: panelState,
                    onOpen: onOpen,
                    onHover: { [weak self] hovering in
                        self?.setExpanded(hovering, for: dock.id)
                    }
                ))
                entry = DockEntry(panel: panel, state: panelState)
                entries[dock.id] = entry
            }
            entry.panel.title = dock.name
            if entry.panel.frame != frame {
                entry.panel.setFrame(frame, display: true, animate: false)
            }
            entry.panel.orderFrontRegardless()
        }
    }

    func stop() {
        entries.values.forEach { $0.panel.orderOut(nil) }
        entries.removeAll()
        expanded.removeAll()
    }

    private func setExpanded(_ value: Bool, for id: UUID) {
        if !value, let entry = entries[id], entry.panel.frame.contains(NSEvent.mouseLocation) { return }
        let changed = value ? expanded.insert(id).inserted : expanded.remove(id) != nil
        if changed { sync() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private static func frame(for dock: CustomDock, itemCount: Int, expanded: Bool,
                              on screen: NSScreen, ordinal: Int) -> NSRect {
        let bounds = screen.visibleFrame
        let horizontal = dock.placement == .bottom || dock.placement == .top
        let itemExtent = CGFloat(max(itemCount, 1)) * (horizontal ? 70 : 62) + 28
        let length = min(max(120, itemExtent), horizontal ? bounds.width - 36 : bounds.height - 36)
        let thickness: CGFloat = expanded ? (horizontal ? 68 : 86) : 22
        let size = horizontal ? NSSize(width: length, height: thickness)
                              : NSSize(width: thickness, height: length)
        let inset: CGFloat = 8 + CGFloat(ordinal) * (horizontal ? 76 : 94)
        let x: CGFloat
        let y: CGFloat
        switch dock.placement {
        case .bottom:
            x = bounds.midX - size.width / 2
            y = bounds.minY + inset
        case .top:
            x = bounds.midX - size.width / 2
            y = bounds.maxY - size.height - inset
        case .left:
            x = bounds.minX + inset
            y = bounds.midY - size.height / 2
        case .right:
            x = bounds.maxX - size.width - inset
            y = bounds.midY - size.height / 2
        }
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

private struct CustomDockBody: View {
    @ObservedObject var state: CustomDockPanelState
    let onOpen: (UUID) -> Void
    let onHover: (Bool) -> Void

    private var horizontal: Bool { state.dock.placement == .top || state.dock.placement == .bottom }

    var body: some View {
        Group {
            if state.expanded {
                if horizontal {
                    HStack(spacing: 5) { buttons }
                } else {
                    VStack(spacing: 5) { buttons }
                }
            } else {
                Image(systemName: horizontal ? "ellipsis" : "ellipsis.vertical")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Show \(state.dock.name)")
            }
        }
        .padding(state.expanded ? 7 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: state.expanded ? 14 : 8))
        .onHover(perform: onHover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.dock.name)
    }

    @ViewBuilder private var buttons: some View {
        if state.items.isEmpty {
            Text(state.dock.name).font(.caption).lineLimit(1).foregroundStyle(.secondary)
        } else {
            ForEach(state.items) { item in
                Button { onOpen(item.id) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "square.grid.2x2")
                        Text(item.title).font(.caption2).lineLimit(1)
                    }
                    .frame(width: horizontal ? 62 : 68, height: horizontal ? 50 : 52)
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel("Open \(item.title)")
            }
        }
    }
}

/// A Settings-ready editor. All mutations replace SavedState so persistence runs once.
struct CustomSurfacesView: View {
    @ObservedObject private var model = AppModel.shared
    let onChange: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Floating docks").font(.title2.bold())
                    Spacer()
                    Button("Add dock") { update { $0.customDocks.append(CustomDock(name: "New dock")) } }
                }
                Text("Create separate docks for different displays or edges. A disconnected display falls back until it returns.")
                    .foregroundStyle(.secondary)
                ForEach(model.state.customDocks) { dock in dockEditor(dock) }

                Divider()
                HStack {
                    Text("Menu groups").font(.title2.bold())
                    Spacer()
                    Button("Add group") { update { $0.menuGroups.append(MenuGroup(name: "New group")) } }
                }
                Text("Items appear in this order in the Snapboard menu and keyboard picker.")
                    .foregroundStyle(.secondary)
                ForEach(model.state.menuGroups) { group in groupEditor(group) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private func dockEditor(_ dock: CustomDock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Dock name", text: Binding(
                    get: { currentDock(dock.id)?.name ?? dock.name },
                    set: { value in changeDock(dock.id) { $0.name = value } }
                ))
                Toggle("Enabled", isOn: Binding(
                    get: { currentDock(dock.id)?.enabled ?? false },
                    set: { value in changeDock(dock.id) { $0.enabled = value } }
                ))
                Button("Remove dock") { update { $0.customDocks.removeAll { $0.id == dock.id } } }
            }
            HStack {
                Picker("Edge", selection: Binding(
                    get: { currentDock(dock.id)?.placement ?? .bottom },
                    set: { value in changeDock(dock.id) { $0.placement = value } }
                )) {
                    ForEach(CustomDock.Placement.allCases, id: \.self) { edge in
                        Text(edge.rawValue.capitalized).tag(edge)
                    }
                }
                Picker("Display", selection: Binding(
                    get: { currentDock(dock.id)?.displayKey ?? "" },
                    set: { value in changeDock(dock.id) { $0.displayKey = value.isEmpty ? nil : value } }
                )) {
                    Text("Available display").tag("")
                    ForEach(displayChoices(for: dock)) { choice in Text(choice.name).tag(choice.key) }
                }
                Toggle("Hide until hovered", isOn: Binding(
                    get: { currentDock(dock.id)?.autoHide ?? false },
                    set: { value in changeDock(dock.id) { $0.autoHide = value } }
                ))
            }
            itemEditor(dock.itemIDs, toggle: { id in
                changeDock(dock.id) { surface in
                    if surface.itemIDs.contains(id) { surface.itemIDs.removeAll { $0 == id } }
                    else { surface.itemIDs.append(id) }
                }
            }, move: { id, offset in
                changeDock(dock.id) { moveID(id, by: offset, in: &$0.itemIDs) }
            })
            workspaceEditor(dock.workspaceIDs) { workspaceID in
                changeDock(dock.id) { toggleWorkspace(workspaceID, in: &$0.workspaceIDs) }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func groupEditor(_ group: MenuGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Group name", text: Binding(
                    get: { currentGroup(group.id)?.name ?? group.name },
                    set: { value in changeGroup(group.id) { $0.name = value } }
                ))
                Toggle("Enabled", isOn: Binding(
                    get: { currentGroup(group.id)?.enabled ?? false },
                    set: { value in changeGroup(group.id) { $0.enabled = value } }
                ))
                Button("Remove group") { update { $0.menuGroups.removeAll { $0.id == group.id } } }
            }
            itemEditor(group.itemIDs, toggle: { id in
                changeGroup(group.id) { surface in
                    if surface.itemIDs.contains(id) { surface.itemIDs.removeAll { $0 == id } }
                    else { surface.itemIDs.append(id) }
                }
            }, move: { id, offset in
                changeGroup(group.id) { moveID(id, by: offset, in: &$0.itemIDs) }
            })
            workspaceEditor(group.workspaceIDs) { workspaceID in
                changeGroup(group.id) { toggleWorkspace(workspaceID, in: &$0.workspaceIDs) }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func itemEditor(_ itemIDs: [UUID], toggle: @escaping (UUID) -> Void,
                            move: @escaping (UUID, Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Items").font(.headline)
            ForEach(model.state.libraryItems) { item in
                HStack {
                    Toggle(item.title, isOn: Binding(
                        get: { itemIDs.contains(item.id) },
                        set: { _ in toggle(item.id) }
                    ))
                    if let index = itemIDs.firstIndex(of: item.id) {
                        Button { move(item.id, -1) } label: { Image(systemName: "arrow.up") }
                            .disabled(index == 0).help("Move up")
                        Button { move(item.id, 1) } label: { Image(systemName: "arrow.down") }
                            .disabled(index == itemIDs.count - 1).help("Move down")
                    }
                }
            }
            if model.state.libraryItems.isEmpty {
                Text("Add items to the shared library first.").foregroundStyle(.secondary)
            }
        }
    }

    private func workspaceEditor(_ workspaceIDs: [UUID], toggle: @escaping (UUID) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Workspaces").font(.headline)
            Text(workspaceIDs.isEmpty ? "All workspaces" : "Only selected workspaces")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.state.workspaces) { workspace in
                Toggle(workspace.name, isOn: Binding(
                    get: { workspaceIDs.contains(workspace.id) },
                    set: { _ in toggle(workspace.id) }
                ))
            }
        }
    }

    private struct DisplayChoice: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    private func displayChoices(for dock: CustomDock) -> [DisplayChoice] {
        var choices = NSScreen.screens.map { DisplayChoice(key: $0.snapKey, name: $0.localizedName) }
        if let key = dock.displayKey, !choices.contains(where: { $0.key == key }) {
            choices.append(DisplayChoice(key: key, name: "Disconnected: \(key)"))
        }
        return choices
    }

    private func currentDock(_ id: UUID) -> CustomDock? { model.state.customDocks.first { $0.id == id } }
    private func currentGroup(_ id: UUID) -> MenuGroup? { model.state.menuGroups.first { $0.id == id } }

    private func update(_ change: (inout SavedState) -> Void) {
        var next = model.state
        change(&next)
        model.state = next
        onChange()
    }

    private func changeDock(_ id: UUID, _ change: (inout CustomDock) -> Void) {
        update { state in
            guard let index = state.customDocks.firstIndex(where: { $0.id == id }) else { return }
            change(&state.customDocks[index])
        }
    }

    private func changeGroup(_ id: UUID, _ change: (inout MenuGroup) -> Void) {
        update { state in
            guard let index = state.menuGroups.firstIndex(where: { $0.id == id }) else { return }
            change(&state.menuGroups[index])
        }
    }

    private func moveID(_ id: UUID, by offset: Int, in ids: inout [UUID]) {
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
    }

    private func toggleWorkspace(_ id: UUID, in ids: inout [UUID]) {
        if ids.contains(id) { ids.removeAll { $0 == id } }
        else { ids.append(id) }
    }
}

/// The menu can be rebuilt on every open using the latest shared library state.
enum CustomSurfacesMenu {
    static func makeMenu(groups: [MenuGroup], items: [SnapboardCore.LibraryItem],
                         surfaceWorkspaceID: UUID? = nil, onOpen: @escaping (UUID) -> Void) -> NSMenu {
        let menu = NSMenu()
        for group in groups where group.enabled && group.applies(to: surfaceWorkspaceID) {
            let parent = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
            let children = NSMenu()
            for id in group.itemIDs {
                guard let item = items.first(where: { $0.id == id }) else { continue }
                let child = NSMenuItem(title: item.title, action: #selector(MenuAction.run), keyEquivalent: "")
                let target = MenuAction { onOpen(id) }
                child.target = target
                child.representedObject = target
                children.addItem(child)
            }
            parent.submenu = children
            menu.addItem(parent)
        }
        return menu
    }
}

/// Searchable keyboard entry for menu groups; arrow keys move selection and Return opens it.
struct MenuGroupPickerView: View {
    @ObservedObject private var model = AppModel.shared
    @State private var query = ""
    @State private var selectedItemID: UUID?
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search menu items", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { openSelected() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(matches) { match in
                            Text(match.group.name).font(.headline).padding(.top, 4)
                            ForEach(match.items) { item in
                                Button {
                                    selectedItemID = item.id
                                    openAndReset(item.id)
                                } label: {
                                    Text(item.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            selectedItemID == item.id
                                                ? Color.accentColor.opacity(0.2)
                                                : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                            }
                        }
                    }
                }
                .onChange(of: selectedItemID) { newID in
                    if let newID { proxy.scrollTo(newID, anchor: .center) }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 300)
        .onAppear {
            focusAndSyncSelection()
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.title == "Snapboard Menu Items" {
                focusAndSyncSelection()
            }
        }
        .onChange(of: query) { _ in syncSelection() }
    }

    private struct PickerGroup: Identifiable {
        let group: MenuGroup
        let items: [SnapboardCore.LibraryItem]
        var id: UUID { group.id }
    }

    private var matches: [PickerGroup] {
        model.state.menuGroups.filter { $0.enabled && $0.applies(to: model.state.surfaceWorkspaceID) }.compactMap { group in
            let items = group.itemIDs.compactMap { id in model.state.libraryItems.first { $0.id == id } }
                .filter { query.isEmpty || $0.title.localizedStandardContains(query) || group.name.localizedStandardContains(query) }
            return items.isEmpty ? nil : PickerGroup(group: group, items: items)
        }
    }

    private var flatItems: [SnapboardCore.LibraryItem] { matches.flatMap(\.items) }

    private func focusAndSyncSelection() {
        syncSelection()
        DispatchQueue.main.async { searchFocused = true }
    }

    private func syncSelection() {
        let items = flatItems
        if let current = selectedItemID, items.contains(where: { $0.id == current }) { return }
        selectedItemID = items.first?.id
    }

    private func moveSelection(by delta: Int) {
        let items = flatItems
        guard !items.isEmpty else { selectedItemID = nil; return }
        if let current = selectedItemID, let idx = items.firstIndex(where: { $0.id == current }) {
            let next = (idx + delta + items.count) % items.count
            selectedItemID = items[next].id
        } else {
            selectedItemID = items.first?.id
        }
    }

    private func openSelected() {
        let items = flatItems
        let targetID = selectedItemID.flatMap { id in items.contains(where: { $0.id == id }) ? id : nil } ?? items.first?.id
        if let id = targetID { openAndReset(id) }
    }

    private func openAndReset(_ id: UUID) {
        query = ""
        onOpen(id)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.title == "Snapboard Menu Items" else { return event }
            switch event.keyCode {
            case 125: // Down arrow
                moveSelection(by: 1)
                return nil
            case 126: // Up arrow
                moveSelection(by: -1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
