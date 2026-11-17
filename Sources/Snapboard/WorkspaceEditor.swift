import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapboardCore

/// Keeps workspace edits separate from the quick layout editor.
struct WorkspaceEditorView: View {
    @ObservedObject private var model = AppModel.shared
    @State private var selectedID: UUID?
    @State private var newName = ""
    @State private var renameName = ""
    @State private var linkTitle = ""
    @State private var linkAddress = ""
    @State private var errorMessage: String?
    @State private var applyLayouts = true
    @State private var launchItems = false
    @State private var activateSurfaces = true

    private var selectedWorkspace: Workspace? {
        model.state.workspaces.first { $0.id == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workspaces").font(.headline)
                List(selection: $selectedID) {
                    ForEach(model.state.workspaces) { workspace in
                        HStack {
                            Text(workspace.name).lineLimit(1)
                            Spacer(minLength: 4)
                            if model.state.activeWorkspaceID == workspace.id {
                                Image(systemName: "checkmark")
                                    .accessibilityLabel("Current workspace")
                            }
                        }
                        .tag(workspace.id)
                    }
                }
                .frame(minWidth: 180)
                TextField("New workspace name", text: $newName)
                    .onSubmit(createWorkspace)
                Button("Save current layouts as workspace", action: createWorkspace)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
            .frame(width: 230)

            Divider()

            ScrollView {
                if let workspace = selectedWorkspace {
                    workspaceDetails(workspace)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No workspace selected").font(.title3.bold())
                        Text("Name a workspace on the left to save the layouts on your connected screens.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .frame(minWidth: 340)
        }
        .frame(minWidth: 580, minHeight: 420)
        .onAppear {
            if selectedID == nil {
                selectedID = model.state.activeWorkspaceID ?? model.state.workspaces.first?.id
                renameName = selectedWorkspace?.name ?? ""
            }
        }
        .onChange(of: selectedID) { _ in
            renameName = selectedWorkspace?.name ?? ""
            linkTitle = ""
            linkAddress = ""
        }
        .alert("Could not complete the workspace action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func workspaceDetails(_ workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(workspace.name).font(.title2.bold())
            Text("Choose what switching to this workspace will change. Open windows and the macOS Dock stay as they are.")
                .foregroundStyle(.secondary)

            GroupBox("Activation preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Apply saved zones on \(workspace.layouts.count) screen(s)", isOn: $applyLayouts)
                    let itemCount = Set(workspace.items.map(\.target)).union(model.state.libraryItems
                        .filter { $0.workspaceIDs.contains(workspace.id) }.map(\.target)).count
                    Toggle("Open \(itemCount) saved item(s)", isOn: $launchItems)
                        .disabled(itemCount == 0)
                    let surfaceCount = model.state.customDocks.filter { $0.workspaceIDs.contains(workspace.id) }.count
                        + model.state.menuGroups.filter { $0.workspaceIDs.contains(workspace.id) }.count
                    Toggle("Show \(surfaceCount) workspace surface(s)", isOn: $activateSurfaces)
                        .disabled(surfaceCount == 0)
                    Text("Only the selected parts change. A missing item produces an error without removing your saved configuration.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }

            HStack {
                Button("Activate selected parts") {
                    guard let errors = model.activateWorkspace(workspace.id, applyLayouts: applyLayouts,
                                                              launchItems: launchItems,
                                                              activateSurfaces: activateSurfaces) else {
                        errorMessage = "This workspace no longer exists."
                        return
                    }
                    if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
                }
                Button("Update saved layouts from current screens") {
                    if !model.updateWorkspaceLayouts(workspace.id) { errorMessage = "This workspace no longer exists." }
                }
            }

            Divider()
            Text("Name").font(.headline)
            HStack {
                TextField("Workspace name", text: $renameName)
                    .onSubmit { saveName(workspace.id) }
                Button("Rename") { saveName(workspace.id) }
                    .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()
            Text("Saved apps and links").font(.headline)
            let linkedItems = model.state.libraryItems.filter { item in
                item.workspaceIDs.contains(workspace.id) &&
                    !workspace.items.contains { $0.kind.rawValue == item.kind.rawValue && $0.target == item.target }
            }
            if workspace.items.isEmpty && linkedItems.isEmpty {
                Text("No apps or links yet. Add one below to open it from this workspace.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workspace.items) { savedItem in
                    HStack {
                        Image(systemName: savedItem.kind == .application ? "app" : "link")
                            .accessibilityHidden(true)
                        Text(savedItem.title).lineLimit(1)
                        Spacer()
                        Button("Open") {
                            errorMessage = model.openWorkspaceItem(savedItem)
                        }
                        Button("Remove") {
                            model.removeItem(savedItem.id, from: workspace.id)
                        }
                        .accessibilityLabel("Remove \(savedItem.title) from \(workspace.name)")
                    }
                }
                ForEach(linkedItems) { item in
                    HStack {
                        Image(systemName: item.kind == .link ? "link" : item.kind == .folder ? "folder" : "app")
                            .accessibilityHidden(true)
                        Text(item.title).lineLimit(1)
                        Spacer()
                        Button("Open") {
                            errorMessage = model.openLibraryItem(item, onAction: { id in
                                guard let action = model.state.savedActions.first(where: { $0.id == id }) else {
                                    errorMessage = "That action is no longer available."
                                    return
                                }
                                errorMessage = AutomationRuntime.shared.run(action)
                            })
                        }
                        Button("Remove") {
                            var next = model.state
                            if let index = next.libraryItems.firstIndex(where: { $0.id == item.id }) {
                                next.libraryItems[index].workspaceIDs.removeAll { $0 == workspace.id }
                                model.state = next
                            }
                        }
                        .accessibilityLabel("Remove \(item.title) from \(workspace.name)")
                    }
                }
            }

            Button("Add application…") { chooseApplication(for: workspace.id) }
            HStack {
                TextField("Link name (optional)", text: $linkTitle)
                TextField("https://example.com", text: $linkAddress)
            }
            Button("Add link") {
                errorMessage = model.addLink(title: linkTitle, address: linkAddress, to: workspace.id)
                if errorMessage == nil { linkTitle = ""; linkAddress = "" }
            }
            .disabled(linkAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
    }

    private func createWorkspace() {
        guard let id = model.createWorkspace(named: newName) else {
            errorMessage = "Enter a workspace name."
            return
        }
        newName = ""
        selectedID = id
    }

    private func saveName(_ id: UUID) {
        if !model.renameWorkspace(id, to: renameName) {
            errorMessage = "Enter a workspace name and try again."
        }
    }

    private func chooseApplication(for id: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        errorMessage = model.addApplication(url, to: id)
    }
}
