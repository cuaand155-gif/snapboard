import AppKit
import Carbon.HIToolbox
import SnapboardCore

/// Owns the Carbon registrations for user-defined keyboard triggers. Rebuilding always
/// unregisters the old refs first, including when shortcuts have been switched off.
final class AutomationRuntime: @unchecked Sendable {
    static let shared = AutomationRuntime()

    private static let signature: OSType = 0x4155_544F // "AUTO", distinct from built-in "SNAP"
    private var registrations: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actionsByHotkeyID: [UInt32: UUID] = [:]

    private init() {}

    static var reservedShortcuts: Set<KeyboardShortcut> {
        Set(Hotkeys.bindings.map {
            KeyboardShortcut(keyCode: UInt32($0.key), modifiers: UInt32(controlKey | optionKey))
        })
    }

    /// Returns visible diagnostics for rules that could not be registered.
    @discardableResult
    func refresh() -> [String] {
        stop()
        let state = AppModel.shared.state
        guard state.shortcutsOn else { return [] }

        let conflicts = AutomationValidation.conflictingRuleIDs(state.automationRules,
                                                                 reserved: Self.reservedShortcuts)
        let invalidActions = AutomationValidation.invalidActionIDs(state.savedActions)
        let invalidRules = AutomationValidation.invalidRuleIDs(state.automationRules)
        var errors: [String] = []
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            guard result == noErr, hotkeyID.signature == AutomationRuntime.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let keyID = hotkeyID.id
            DispatchQueue.main.async { AutomationRuntime.shared.handle(keyID) }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return ["Keyboard triggers could not be started (macOS error \(status))."] }

        for (index, rule) in state.automationRules.enumerated() where rule.enabled {
            if invalidRules.contains(rule.id) {
                errors.append("A trigger needs a name and at least two modifier keys.")
                continue
            }
            if conflicts.contains(rule.id) {
                errors.append("\(rule.name): shortcut conflicts with another trigger or a built-in Snapboard shortcut.")
                continue
            }
            guard let action = state.savedActions.first(where: { $0.id == rule.actionID }) else {
                errors.append("\(rule.name): saved action is missing.")
                continue
            }
            guard !invalidActions.contains(action.id) else {
                errors.append("\(rule.name): saved action has an empty name, missing step, or invalid target.")
                continue
            }
            // Keep IDs outside Hotkeys' small built-in range as an extra guard if
            // Carbon changes handler order while registrations are being refreshed.
            let hotkeyID = UInt32(index + 1000)
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(rule.shortcut.keyCode, rule.shortcut.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: hotkeyID),
                                             GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref {
                registrations.append(ref)
                actionsByHotkeyID[hotkeyID] = action.id
            } else {
                errors.append("\(rule.name): macOS rejected this shortcut (error \(result)). Try another combination.")
            }
        }
        return errors
    }

    func stop() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
        actionsByHotkeyID.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    @discardableResult
    func run(_ action: SavedAction) -> String? {
        run(action, visited: [])
    }

    private func handle(_ hotkeyID: UInt32) {
        guard let actionID = actionsByHotkeyID[hotkeyID],
              let action = AppModel.shared.state.savedActions.first(where: { $0.id == actionID }) else { return }
        if let error = run(action) {
            NSLog("Snapboard automation: %@", error)
            NSSound.beep()
        }
    }

    private func run(_ action: SavedAction, visited: Set<UUID>) -> String? {
        let model = AppModel.shared
        guard !visited.contains(action.id) else { return "Action “\(action.name)” refers back to itself." }
        guard action.isAvailable(in: model.state.activeWorkspaceID) else {
            return "Action “\(action.name)” is not available in the active workspace."
        }
        guard !AutomationValidation.invalidActionIDs([action]).contains(action.id) else {
            return "Action “\(action.name)” needs a name and valid steps before it can run."
        }
        var seen = visited
        seen.insert(action.id)
        for step in action.steps {
            switch step.kind {
            case .openLibraryItem:
                guard let id = UUID(uuidString: step.target),
                      let item = model.state.libraryItems.first(where: { $0.id == id }) else {
                    return "Action “\(action.name)” refers to a library item that no longer exists."
                }
                var nestedError: String?
                let error = model.openLibraryItem(item, onAction: { nestedID in
                    guard let nested = model.state.savedActions.first(where: { $0.id == nestedID }) else {
                        nestedError = "A library item refers to an action that no longer exists."
                        return
                    }
                    nestedError = self.run(nested, visited: seen)
                })
                if let error = error ?? nestedError { return error }
            case .activateWorkspace:
                guard let id = UUID(uuidString: step.target) else {
                    return "Action “\(action.name)” has an invalid workspace target."
                }
                guard let errors = model.activateWorkspace(id, applyLayouts: true, launchItems: false, activateSurfaces: true) else {
                    return "Action “\(action.name)” refers to a workspace that no longer exists."
                }
                if !errors.isEmpty {
                    return errors.joined(separator: " ")
                }
            case .openURL:
                guard let url = URL(string: step.target), NSWorkspace.shared.open(url) else {
                    return "Action “\(action.name)” could not open its web link."
                }
            case .snapLeft, .snapRight, .snapTop, .snapBottom, .snapFull:
                guard WindowMover.isTrusted else {
                    return "Allow Snapboard in System Settings → Privacy & Security → Accessibility to snap windows."
                }
                guard WindowMover.frontWindow() != nil else {
                    return "There is no movable front window to snap."
                }
                let snap: QuickSnap
                switch step.kind {
                case .snapLeft: snap = .leftHalf
                case .snapRight: snap = .rightHalf
                case .snapTop: snap = .topHalf
                case .snapBottom: snap = .bottomHalf
                default: snap = .maximise
                }
                snap.apply()
            }
        }
        return nil
    }
}
