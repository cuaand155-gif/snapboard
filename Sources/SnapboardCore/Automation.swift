import Foundation

/// A reusable sequence. An empty workspace list makes the action available everywhere.
public struct SavedAction: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var steps: [AutomationStep]
    public var workspaceIDs: [UUID]

    public init(id: UUID = UUID(), name: String, steps: [AutomationStep] = [], workspaceIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.steps = steps
        self.workspaceIDs = workspaceIDs
    }

    public func isAvailable(in workspaceID: UUID?) -> Bool {
        workspaceIDs.isEmpty || workspaceID.map { workspaceIDs.contains($0) } == true
    }
}

/// A step has one documented effect. `target` is an item/workspace UUID or an HTTPS URL
/// for the corresponding kinds; snap steps do not use it.
public struct AutomationStep: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable, CaseIterable {
        case openLibraryItem, activateWorkspace, openURL
        case snapLeft, snapRight, snapTop, snapBottom, snapFull

        public var title: String {
            switch self {
            case .openLibraryItem: return "Open library item"
            case .activateWorkspace: return "Use workspace"
            case .openURL: return "Open web link"
            case .snapLeft: return "Snap window left"
            case .snapRight: return "Snap window right"
            case .snapTop: return "Snap window top"
            case .snapBottom: return "Snap window bottom"
            case .snapFull: return "Fill screen"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var target: String

    public init(id: UUID = UUID(), kind: Kind, target: String = "") {
        self.id = id
        self.kind = kind
        self.target = target
    }

    public var hasValidTarget: Bool {
        switch kind {
        case .openLibraryItem, .activateWorkspace:
            return UUID(uuidString: target) != nil
        case .openURL:
            guard let url = URL(string: target), let scheme = url.scheme?.lowercased() else { return false }
            return ["http", "https"].contains(scheme) && url.host?.isEmpty == false
        case .snapLeft, .snapRight, .snapTop, .snapBottom, .snapFull:
            return true
        }
    }
}

/// Carbon modifier flags are kept as numbers so this model remains AppKit free.
public enum ShortcutModifiers {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
}

public struct KeyboardShortcut: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Global triggers require two known modifiers so an ordinary typing key cannot be captured.
    public var hasValidModifiers: Bool {
        let known = ShortcutModifiers.command | ShortcutModifiers.shift |
            ShortcutModifiers.option | ShortcutModifiers.control
        return modifiers & ~known == 0 && (modifiers & known).nonzeroBitCount >= 2
    }
}

/// A global keyboard trigger for one saved action. Disabling preserves its configuration.
public struct AutomationRule: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var actionID: UUID
    public var shortcut: KeyboardShortcut
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, actionID: UUID,
                shortcut: KeyboardShortcut, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.actionID = actionID
        self.shortcut = shortcut
        self.enabled = enabled
    }
}

public enum AutomationValidation {
    /// Returns every enabled rule whose keyboard combination conflicts with another
    /// enabled rule or a built-in Snapboard shortcut. A disabled rule never blocks one.
    public static func conflictingRuleIDs(_ rules: [AutomationRule], reserved: Set<KeyboardShortcut>) -> Set<UUID> {
        let active = rules.filter(\.enabled)
        let grouped = Dictionary(grouping: active, by: \.shortcut)
        return Set(grouped.flatMap { shortcut, group -> [UUID] in
            guard group.count > 1 || reserved.contains(shortcut) else { return [] }
            return group.map(\.id)
        })
    }

    public static func invalidActionIDs(_ actions: [SavedAction]) -> Set<UUID> {
        Set(actions.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            $0.steps.isEmpty || $0.steps.contains(where: { !$0.hasValidTarget }) }.map(\.id))
    }

    public static func invalidRuleIDs(_ rules: [AutomationRule]) -> Set<UUID> {
        Set(rules.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.shortcut.hasValidModifiers }.map(\.id))
    }
}
