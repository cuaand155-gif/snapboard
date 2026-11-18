import Carbon.HIToolbox
import SnapboardCore
import SwiftUI

/// Edits the same saved actions used by library tiles and global keyboard triggers.
struct AutomationEditorView: View {
    @ObservedObject private var model = AppModel.shared
    @State private var runError: String?
    @State private var registrationErrors: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actions and triggers").font(.title2.bold())
                        Text("Build a reusable sequence, then run it from the library or a keyboard shortcut.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("New action") { addAction() }
                }
                if let runError {
                    Text(runError).foregroundStyle(.red).font(.callout)
                        .accessibilityLabel("Automation error: \(runError)")
                }
                if !registrationErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(registrationErrors, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(model.state.savedActions) { action in
                    actionCard(action)
                }
                if model.state.savedActions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.badge.clock").font(.largeTitle)
                        Text("No actions yet").font(.headline)
                        Text("Create an action to combine saved items, workspaces, links, and window snaps.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
                triggerSection
            }
            .padding(20)
        }
        .frame(minWidth: 690, minHeight: 560)
        .onAppear { refreshRegistrations() }
    }

    private func actionCard(_ action: SavedAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Action name", text: actionName(action.id)).font(.headline)
                Button("Run") { runError = AutomationRuntime.shared.run(action) }
                    .disabled(AutomationValidation.invalidActionIDs([action]).contains(action.id))
                Button("Remove", role: .destructive) { removeAction(action.id) }
            }
            if AutomationValidation.invalidActionIDs([action]).contains(action.id) {
                Label("Add a name and at least one step; each step needs a valid target.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Available in").font(.subheadline.bold())
                HStack(spacing: 12) {
                    Text(action.workspaceIDs.isEmpty ? "All workspaces" : "Selected workspaces")
                        .foregroundStyle(.secondary)
                    ForEach(model.state.workspaces) { workspace in
                        Toggle(workspace.name, isOn: workspaceAssociation(action.id, workspace.id))
                            .toggleStyle(.checkbox)
                    }
                }
                if action.workspaceIDs.contains(where: { id in !model.state.workspaces.contains(where: { $0.id == id }) }) {
                    HStack {
                        Text("A selected workspace no longer exists.").font(.caption).foregroundStyle(.red)
                        Button("Clear missing") { clearMissingWorkspaces(action.id) }
                    }
                }
            }
            Text("Steps run from top to bottom").font(.subheadline.bold())
            ForEach(Array(action.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).").foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                    Text(step.kind.title).frame(width: 145, alignment: .leading)
                    stepTarget(step, actionID: action.id)
                    if !step.hasValidTarget {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).help("Choose a valid target for this step.")
                    }
                    Spacer(minLength: 0)
                    Button { moveStep(action.id, stepID: step.id, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0).help("Move step up")
                    Button { moveStep(action.id, stepID: step.id, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == action.steps.count - 1).help("Move step down")
                    Button { removeStep(action.id, step.id) } label: { Image(systemName: "minus.circle") }
                        .help("Remove step")
                }
            }
            Menu("Add step") {
                ForEach(AutomationStep.Kind.allCases, id: \.self) { kind in
                    Button(kind.title) { addStep(kind, to: action.id) }
                }
            }
            actionUsageSummary(action)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func actionUsageSummary(_ action: SavedAction) -> some View {
        let workspaceNames: String = {
            if action.workspaceIDs.isEmpty { return "All workspaces" }
            let names = model.state.workspaces
                .filter { action.workspaceIDs.contains($0.id) }
                .map(\.name)
            return names.isEmpty ? "None" : names.joined(separator: ", ")
        }()
        let triggerNames = model.state.automationRules
            .filter { $0.actionID == action.id }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed trigger" : $0.name }
        let libraryNames = model.state.libraryItems
            .filter { $0.kind == .action && UUID(uuidString: $0.target) == action.id }
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled item" : $0.title }

        return VStack(alignment: .leading, spacing: 2) {
            Text("Used by").font(.subheadline.bold())
            Text("Workspaces: \(workspaceNames)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Triggers: \(triggerNames.isEmpty ? "None" : triggerNames.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            Text("Library items: \(libraryNames.isEmpty ? "None" : libraryNames.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stepTarget(_ step: AutomationStep, actionID: UUID) -> some View {
        switch step.kind {
        case .openLibraryItem:
            Picker("Library item", selection: stepTargetBinding(actionID, step.id)) {
                Text("Choose an item").tag("")
                ForEach(model.state.libraryItems) { item in Text(item.title).tag(item.id.uuidString) }
            }
            .labelsHidden().frame(maxWidth: 260)
        case .activateWorkspace:
            Picker("Workspace", selection: stepTargetBinding(actionID, step.id)) {
                Text("Choose a workspace").tag("")
                ForEach(model.state.workspaces) { workspace in Text(workspace.name).tag(workspace.id.uuidString) }
            }
            .labelsHidden().frame(maxWidth: 260)
        case .openURL:
            TextField("https://example.com", text: stepTargetBinding(actionID, step.id))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
        case .snapLeft, .snapRight, .snapTop, .snapBottom, .snapFull:
            Text("Front window").foregroundStyle(.secondary)
        }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Keyboard triggers").font(.headline)
                Spacer()
                Button("Add trigger") { addRule() }.disabled(model.state.savedActions.isEmpty)
            }
            if !model.state.shortcutsOn {
                Text("Keyboard shortcuts are off in Settings. Saved triggers will resume when shortcuts are on.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            let conflicts = AutomationValidation.conflictingRuleIDs(model.state.automationRules,
                                                                     reserved: AutomationRuntime.reservedShortcuts)
            ForEach(model.state.automationRules) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Toggle("Enabled", isOn: ruleEnabled(rule.id)).labelsHidden()
                        TextField("Trigger name", text: ruleName(rule.id)).frame(minWidth: 100)
                        Picker("Action", selection: ruleActionID(rule.id)) {
                            ForEach(model.state.savedActions) { action in Text(action.name).tag(action.id) }
                        }
                        .frame(width: 180)
                        Picker("Modifiers", selection: ruleModifiers(rule.id)) {
                            ForEach(modifierChoices) { choice in Text(choice.label).tag(choice.id) }
                        }
                        .frame(width: 100)
                        Picker("Key", selection: ruleKeyCode(rule.id)) {
                            ForEach(keyChoices) { key in Text(key.label).tag(key.id) }
                        }
                        .frame(width: 80)
                        Button { removeRule(rule.id) } label: { Image(systemName: "minus.circle") }
                            .help("Remove trigger")
                    }
                    if conflicts.contains(rule.id) {
                        Text("This shortcut conflicts with another enabled trigger or a built-in Snapboard shortcut.")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if !model.state.savedActions.contains(where: { $0.id == rule.actionID }) {
                        Text("The action for this trigger no longer exists.").font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func update(refresh: Bool = true, _ change: (inout SavedState) -> Void) {
        var next = model.state
        change(&next)
        model.state = next
        if refresh { refreshRegistrations() }
    }

    private func refreshRegistrations() {
        registrationErrors = AutomationRuntime.shared.refresh()
    }

    private func addAction() { update(refresh: false) { $0.savedActions.append(SavedAction(name: "New action")) } }
    private func clearMissingWorkspaces(_ actionID: UUID) {
        update(refresh: false) { state in
            guard let i = state.savedActions.firstIndex(where: { $0.id == actionID }) else { return }
            let existing = Set(state.workspaces.map(\.id))
            state.savedActions[i].workspaceIDs.removeAll { !existing.contains($0) }
        }
    }
    private func removeAction(_ id: UUID) {
        update(refresh: true) {
            $0.savedActions.removeAll { $0.id == id }
            $0.automationRules.removeAll { $0.actionID == id }
        }
    }
    private func addStep(_ kind: AutomationStep.Kind, to actionID: UUID) {
        let target: String
        switch kind {
        case .openLibraryItem: target = model.state.libraryItems.first?.id.uuidString ?? ""
        case .activateWorkspace: target = model.state.workspaces.first?.id.uuidString ?? ""
        default: target = ""
        }
        update(refresh: false) { state in
            guard let i = state.savedActions.firstIndex(where: { $0.id == actionID }) else { return }
            state.savedActions[i].steps.append(AutomationStep(kind: kind, target: target))
        }
    }
    private func removeStep(_ actionID: UUID, _ stepID: UUID) {
        update(refresh: false) { state in
            guard let index = state.savedActions.firstIndex(where: { $0.id == actionID }) else { return }
            state.savedActions[index].steps.removeAll { $0.id == stepID }
        }
    }
    private func moveStep(_ actionID: UUID, stepID: UUID, by amount: Int) {
        update(refresh: false) { state in
            guard let index = state.savedActions.firstIndex(where: { $0.id == actionID }),
                  let from = state.savedActions[index].steps.firstIndex(where: { $0.id == stepID }) else { return }
            let destination = from + amount
            guard state.savedActions[index].steps.indices.contains(destination) else { return }
            state.savedActions[index].steps.swapAt(from, destination)
        }
    }
    private func addRule() {
        guard let actionID = model.state.savedActions.first?.id else { return }
        update(refresh: true) { $0.automationRules.append(AutomationRule(name: "New trigger", actionID: actionID,
            shortcut: KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K),
                                       modifiers: ShortcutModifiers.command | ShortcutModifiers.option))) }
    }
    private func removeRule(_ id: UUID) { update(refresh: true) { $0.automationRules.removeAll { $0.id == id } } }

    private func actionName(_ id: UUID) -> Binding<String> {
        Binding(get: { model.state.savedActions.first(where: { $0.id == id })?.name ?? "" },
                set: { value in update(refresh: false) { state in
                    if let i = state.savedActions.firstIndex(where: { $0.id == id }) { state.savedActions[i].name = value }
                } })
    }
    private func workspaceAssociation(_ actionID: UUID, _ workspaceID: UUID) -> Binding<Bool> {
        Binding(get: { model.state.savedActions.first(where: { $0.id == actionID })?.workspaceIDs.contains(workspaceID) ?? false },
                set: { selected in update(refresh: false) { state in
                    guard let i = state.savedActions.firstIndex(where: { $0.id == actionID }) else { return }
                    if selected {
                        if !state.savedActions[i].workspaceIDs.contains(workspaceID) { state.savedActions[i].workspaceIDs.append(workspaceID) }
                    } else {
                        state.savedActions[i].workspaceIDs.removeAll { $0 == workspaceID }
                    }
                } })
    }
    private func stepTargetBinding(_ actionID: UUID, _ stepID: UUID) -> Binding<String> {
        Binding(get: { model.state.savedActions.first(where: { $0.id == actionID })?.steps.first(where: { $0.id == stepID })?.target ?? "" },
                set: { value in update(refresh: false) { state in
                    guard let i = state.savedActions.firstIndex(where: { $0.id == actionID }),
                          let j = state.savedActions[i].steps.firstIndex(where: { $0.id == stepID }) else { return }
                    state.savedActions[i].steps[j].target = value
                } })
    }
    private func ruleName(_ id: UUID) -> Binding<String> {
        Binding(get: { model.state.automationRules.first(where: { $0.id == id })?.name ?? "" },
                set: { value in update(refresh: false) { if let i = $0.automationRules.firstIndex(where: { $0.id == id }) { $0.automationRules[i].name = value } } })
    }
    private func ruleEnabled(_ id: UUID) -> Binding<Bool> {
        Binding(get: { model.state.automationRules.first(where: { $0.id == id })?.enabled ?? false },
                set: { value in update { if let i = $0.automationRules.firstIndex(where: { $0.id == id }) { $0.automationRules[i].enabled = value } } })
    }
    private func ruleActionID(_ id: UUID) -> Binding<UUID> {
        Binding(get: { model.state.automationRules.first(where: { $0.id == id })?.actionID ?? UUID() },
                set: { value in update { if let i = $0.automationRules.firstIndex(where: { $0.id == id }) { $0.automationRules[i].actionID = value } } })
    }
    private func ruleModifiers(_ id: UUID) -> Binding<UInt32> {
        Binding(get: { model.state.automationRules.first(where: { $0.id == id })?.shortcut.modifiers ?? 0 },
                set: { value in update { if let i = $0.automationRules.firstIndex(where: { $0.id == id }) { $0.automationRules[i].shortcut.modifiers = value } } })
    }
    private func ruleKeyCode(_ id: UUID) -> Binding<UInt32> {
        Binding(get: { model.state.automationRules.first(where: { $0.id == id })?.shortcut.keyCode ?? 0 },
                set: { value in update { if let i = $0.automationRules.firstIndex(where: { $0.id == id }) { $0.automationRules[i].shortcut.keyCode = value } } })
    }
}

private struct KeyChoice: Identifiable {
    let id: UInt32
    let label: String
}

private struct ModifierChoice: Identifiable {
    let id: UInt32
    let label: String
}

private let keyChoices: [KeyChoice] = [
    ("A", kVK_ANSI_A), ("B", kVK_ANSI_B), ("C", kVK_ANSI_C), ("D", kVK_ANSI_D),
    ("E", kVK_ANSI_E), ("F", kVK_ANSI_F), ("G", kVK_ANSI_G), ("H", kVK_ANSI_H),
    ("I", kVK_ANSI_I), ("J", kVK_ANSI_J), ("K", kVK_ANSI_K), ("L", kVK_ANSI_L),
    ("M", kVK_ANSI_M), ("N", kVK_ANSI_N), ("O", kVK_ANSI_O), ("P", kVK_ANSI_P),
    ("Q", kVK_ANSI_Q), ("R", kVK_ANSI_R), ("S", kVK_ANSI_S), ("T", kVK_ANSI_T),
    ("U", kVK_ANSI_U), ("V", kVK_ANSI_V), ("W", kVK_ANSI_W), ("X", kVK_ANSI_X),
    ("Y", kVK_ANSI_Y), ("Z", kVK_ANSI_Z), ("←", kVK_LeftArrow), ("→", kVK_RightArrow),
    ("↑", kVK_UpArrow), ("↓", kVK_DownArrow), ("↩", kVK_Return)
].map { KeyChoice(id: UInt32($0.1), label: $0.0) }

private let modifierChoices: [ModifierChoice] = [
    ("⌘⌥", ShortcutModifiers.command | ShortcutModifiers.option),
    ("⌘⇧", ShortcutModifiers.command | ShortcutModifiers.shift),
    ("⌃⌥", ShortcutModifiers.control | ShortcutModifiers.option),
    ("⌃⇧", ShortcutModifiers.control | ShortcutModifiers.shift),
    ("⌘⌃", ShortcutModifiers.command | ShortcutModifiers.control),
    ("⌘⌥⇧", ShortcutModifiers.command | ShortcutModifiers.option | ShortcutModifiers.shift)
].map { ModifierChoice(id: $0.1, label: $0.0) }
