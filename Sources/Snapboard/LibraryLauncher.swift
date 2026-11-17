import AppKit
import SnapboardCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    func addLibraryItem(kind: SnapboardCore.LibraryItem.Kind, title: String, target: String, tags: [String], workspaceIDs: [UUID]) -> String? {
        let item = SnapboardCore.LibraryItem(kind: kind, title: title, target: target, tags: tags, workspaceIDs: workspaceIDs)
        return saveLibraryItem(item)
    }

    func saveLibraryItem(_ item: SnapboardCore.LibraryItem, replacing previous: SnapboardCore.LibraryItem? = nil) -> String? {
        guard item.isValid else { return "Enter a name and a valid app, folder, action ID, or full http(s) address." }
        var next = state
        let validWorkspaces = Set(next.workspaces.map(\.id))
        guard Set(item.workspaceIDs).isSubset(of: validWorkspaces) else { return "A selected workspace no longer exists." }
        guard !next.libraryItems.contains(where: {
            $0.id != item.id && $0.kind == item.kind && $0.target == item.target
        }) else { return "This item is already in the library. Edit the existing item instead." }
        if let previous {
            guard let index = next.libraryItems.firstIndex(where: { $0.id == previous.id }), item.id == previous.id else {
                return "This item no longer exists."
            }
            next.libraryItems[index] = item
            if previous.kind == .application || previous.kind == .link {
                for index in next.workspaces.indices where previous.workspaceIDs.contains(next.workspaces[index].id) {
                    next.workspaces[index].items.removeAll { old in
                        old.id == previous.id || (old.target == previous.target && old.kind.rawValue == previous.kind.rawValue)
                    }
                }
            }
        } else {
            next.libraryItems.append(item)
        }
        if item.kind == .application || item.kind == .link {
            let workspaceKind: WorkspaceItem.Kind = item.kind == .application ? .application : .link
            for index in next.workspaces.indices where item.workspaceIDs.contains(next.workspaces[index].id) {
                if !next.workspaces[index].items.contains(where: { $0.kind == workspaceKind && $0.target == item.target }) {
                    next.workspaces[index].items.append(WorkspaceItem(kind: workspaceKind, title: item.title, target: item.target))
                }
            }
        }
        state = next
        return nil
    }

    func openLibraryItem(_ item: SnapboardCore.LibraryItem, onAction: ((UUID) -> Void)? = nil) -> String? {
        guard item.isValid else { return "This saved item has an invalid address." }
        switch item.kind {
        case .link:
            guard let url = URL(string: item.target), NSWorkspace.shared.open(url) else { return "macOS could not open this link." }
        case .application, .folder:
            let url = URL(fileURLWithPath: item.target)
            guard FileManager.default.fileExists(atPath: url.path) else { return "This saved file has moved or is missing." }
            guard NSWorkspace.shared.open(url) else { return "macOS could not open this item." }
        case .action:
            guard let id = UUID(uuidString: item.target), let onAction else { return "This action is unavailable." }
            onAction(id)
        }
        return nil
    }
}

/// One collection powers the bookmark list and the visual launcher.
struct LibraryLauncherView: View {
    @ObservedObject private var model = AppModel.shared
    let onAction: ((UUID) -> Void)?
    @State private var selection = 0
    @State private var query = ""
    @State private var kind: SnapboardCore.LibraryItem.Kind = .link
    @State private var title = ""
    @State private var target = ""
    @State private var tags = ""
    @State private var editingID: UUID?
    @State private var selectedWorkspaces = Set<UUID>()
    @State private var newGroup = ""
    @State private var selectedGroup: UUID?
    @State private var errorMessage: String?

    init(onAction: ((UUID) -> Void)? = nil) {
        self.onAction = onAction
    }

    private var results: [SnapboardCore.LibraryItem] { model.state.libraryItems.filter { $0.matches(query) } }
    private var activeGroup: LauncherGroup? { model.state.launcherGroups.first { $0.id == selectedGroup } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("View", selection: $selection) {
                Text("Library").tag(0)
                Text("Launcher").tag(1)
            }
            .pickerStyle(.segmented)
            TextField("Search names, URLs, or tags", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(openFirstSearchResult)
            if selection == 0 { libraryPane } else { launcherPane }
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 520)
        .alert("Snapboard library", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var libraryPane: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved items").font(.headline)
                List(results) { item in
                    HStack {
                        Image(systemName: symbol(for: item.kind)).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(item.title)
                            Text(item.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") { errorMessage = model.openLibraryItem(item, onAction: onAction) }
                        Button("Edit") { beginEditing(item) }
                        Button("Remove") { remove(item.id) }
                    }
                }
                HStack {
                    Button("Import…", action: importArchive)
                    Button("Export…", action: exportArchive)
                }
            }
            .frame(minWidth: 330)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(editingID == nil ? "Add item" : "Edit item").font(.headline)
                Picker("Type", selection: $kind) {
                    ForEach(SnapboardCore.LibraryItem.Kind.allCases, id: \.self) { type in Text(type.rawValue.capitalized).tag(type) }
                }
                TextField("Name", text: $title)
                TextField(kind == .link ? "https://example.com" : kind == .action ? "Action ID" : "/Applications/Example.app", text: $target)
                if kind == .application || kind == .folder {
                    Button("Choose in Finder…", action: chooseFile)
                }
                TextField("Tags, separated by commas", text: $tags)
                if !model.state.workspaces.isEmpty {
                    Text("Available in workspaces").font(.subheadline.bold())
                    ForEach(model.state.workspaces) { workspace in
                        Toggle(workspace.name, isOn: Binding(
                            get: { selectedWorkspaces.contains(workspace.id) },
                            set: { if $0 { selectedWorkspaces.insert(workspace.id) } else { selectedWorkspaces.remove(workspace.id) } }
                        ))
                    }
                }
                Button(editingID == nil ? "Save item" : "Save changes") {
                    saveItem()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target.isEmpty)
                if editingID != nil { Button("Cancel editing", action: clearEditor) }
                Spacer()
            }
            .frame(minWidth: 230)
        }
    }

    private var launcherPane: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading) {
                Text("Pages").font(.headline)
                List(selection: $selectedGroup) {
                    ForEach(model.state.launcherGroups) { group in Text(group.name).tag(group.id) }
                }
                HStack {
                    TextField("New page", text: $newGroup).onSubmit(addGroup)
                    Button("Add", action: addGroup).disabled(newGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(width: 190)
            Divider()
            if let group = activeGroup {
                VStack(alignment: .leading) {
                    Text(group.name).font(.title2.bold())
                    let groupItems = group.itemIDs.compactMap { id in results.first { $0.id == id } }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 115))], spacing: 12) {
                        ForEach(groupItems) { item in
                            Button { errorMessage = model.openLibraryItem(item, onAction: onAction) } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: symbol(for: item.kind)).font(.largeTitle)
                                    Text(item.title).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 80)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    ScrollView {
                        ForEach(results) { item in
                            Toggle(item.title, isOn: Binding(
                                get: { group.itemIDs.contains(item.id) },
                                set: { setMembership(item.id, in: group.id, enabled: $0) }
                            ))
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Create a page to arrange your saved items.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .onAppear { selectedGroup = selectedGroup ?? model.state.launcherGroups.first?.id }
    }

    private func symbol(for kind: SnapboardCore.LibraryItem.Kind) -> String {
        switch kind { case .application: return "app"; case .link: return "link"; case .folder: return "folder"; case .action: return "bolt" }
    }

    private func openFirstSearchResult() {
        let item: SnapboardCore.LibraryItem?
        if selection == 1, let group = activeGroup {
            item = group.itemIDs.compactMap { id in results.first { $0.id == id } }.first
        } else {
            item = results.first
        }
        if let item { errorMessage = model.openLibraryItem(item, onAction: onAction) }
    }

    private func beginEditing(_ item: SnapboardCore.LibraryItem) {
        editingID = item.id
        kind = item.kind
        title = item.title
        target = item.target
        tags = item.tags.joined(separator: ", ")
        selectedWorkspaces = Set(item.workspaceIDs)
    }

    private func clearEditor() {
        editingID = nil
        kind = .link
        title = ""
        target = ""
        tags = ""
        selectedWorkspaces.removeAll()
    }

    private func saveItem() {
        let previous = editingID.flatMap { id in model.state.libraryItems.first { $0.id == id } }
        if editingID != nil && previous == nil {
            errorMessage = "This item no longer exists."
            return
        }
        let item = SnapboardCore.LibraryItem(id: editingID ?? UUID(), kind: kind, title: title, target: target,
                               tags: tags.split(separator: ",").map(String.init),
                               workspaceIDs: Array(selectedWorkspaces))
        errorMessage = model.saveLibraryItem(item, replacing: previous)
        if errorMessage == nil { clearEditor() }
    }

    private func remove(_ id: UUID) {
        var next = model.state
        guard let item = next.libraryItems.first(where: { $0.id == id }) else { return }
        next.libraryItems.removeAll { $0.id == id }
        for index in next.launcherGroups.indices { next.launcherGroups[index].itemIDs.removeAll { $0 == id } }
        // Legacy workspace entries otherwise recreate this library item when the state is decoded.
        if item.kind == .application || item.kind == .link {
            for index in next.workspaces.indices {
                next.workspaces[index].items.removeAll { old in
                    old.id == id || (old.target == item.target &&
                        (item.kind == .application ? old.kind == .application : old.kind == .link))
                }
            }
        }
        model.state = next
        if editingID == id { clearEditor() }
    }

    private func addGroup() {
        let name = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var next = model.state
        let group = LauncherGroup(name: name)
        next.launcherGroups.append(group)
        model.state = next
        selectedGroup = group.id
        newGroup = ""
    }

    private func setMembership(_ itemID: UUID, in groupID: UUID, enabled: Bool) {
        var next = model.state
        guard let index = next.launcherGroups.firstIndex(where: { $0.id == groupID }) else { return }
        next.launcherGroups[index].itemIDs.removeAll { $0 == itemID }
        if enabled { next.launcherGroups[index].itemIDs.append(itemID) }
        model.state = next
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = kind == .application
        panel.allowsMultipleSelection = false
        if kind == .application { panel.allowedContentTypes = [.applicationBundle] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        target = url.path
        if title.isEmpty { title = kind == .application ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
    }

    private func exportArchive() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Snapboard Library.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try LibraryArchive(items: model.state.libraryItems, groups: model.state.launcherGroups).exportData()
            try data.write(to: url, options: .atomic)
        } catch { errorMessage = "Export failed: \(error.localizedDescription)" }
    }

    private func importArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let merged = try LibraryArchive.importData(data, items: model.state.libraryItems, groups: model.state.launcherGroups)
            var next = model.state
            next.libraryItems = merged.items
            next.launcherGroups = merged.groups
            model.state = next
        } catch { errorMessage = "The library file is invalid or could not be read. No items were changed." }
    }
}
