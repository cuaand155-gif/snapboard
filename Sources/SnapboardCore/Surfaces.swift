import Foundation

/// A user-owned floating dock. Items refer to the shared library by ID so an
/// item can appear in several docks, menu groups, workspaces and launcher pages.
public struct CustomDock: Codable, Equatable, Identifiable {
    public enum Placement: String, Codable, CaseIterable, Hashable {
        case bottom, left, right, top
    }

    public var id: UUID
    public var name: String
    public var itemIDs: [UUID]
    /// The same stable screen key used by saved workspace layouts.
    public var displayKey: String?
    public var placement: Placement
    public var autoHide: Bool
    public var enabled: Bool
    /// Empty means this dock is available in every workspace.
    public var workspaceIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case id, name, itemIDs, displayKey, placement, autoHide, enabled, workspaceIDs
    }

    public init(id: UUID = UUID(), name: String, itemIDs: [UUID] = [],
                displayKey: String? = nil, placement: Placement = .bottom,
                autoHide: Bool = false, enabled: Bool = true, workspaceIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
        self.displayKey = displayKey
        self.placement = placement
        self.autoHide = autoHide
        self.enabled = enabled
        self.workspaceIDs = workspaceIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        itemIDs = try c.decode([UUID].self, forKey: .itemIDs)
        displayKey = try c.decodeIfPresent(String.self, forKey: .displayKey)
        placement = try c.decode(Placement.self, forKey: .placement)
        autoHide = try c.decode(Bool.self, forKey: .autoHide)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        workspaceIDs = try c.decodeIfPresent([UUID].self, forKey: .workspaceIDs) ?? []
    }

    public func applies(to workspaceID: UUID?) -> Bool {
        workspaceIDs.isEmpty || workspaceID.map(workspaceIDs.contains) == true
    }

    /// Keep the configured display unchanged when it disconnects. Render on an
    /// available display until it returns, then automatically use it again.
    public func renderedDisplayKey(available: [String]) -> String? {
        if let displayKey, available.contains(displayKey) { return displayKey }
        return available.first
    }
}

/// Ordered commands presented in Snapboard's menu and keyboard picker.
public struct MenuGroup: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var itemIDs: [UUID]
    public var enabled: Bool
    /// Empty means this group is available in every workspace.
    public var workspaceIDs: [UUID]

    private enum CodingKeys: String, CodingKey { case id, name, itemIDs, enabled, workspaceIDs }

    public init(id: UUID = UUID(), name: String, itemIDs: [UUID] = [], enabled: Bool = true,
                workspaceIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
        self.enabled = enabled
        self.workspaceIDs = workspaceIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        itemIDs = try c.decode([UUID].self, forKey: .itemIDs)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        workspaceIDs = try c.decodeIfPresent([UUID].self, forKey: .workspaceIDs) ?? []
    }

    public func applies(to workspaceID: UUID?) -> Bool {
        workspaceIDs.isEmpty || workspaceID.map(workspaceIDs.contains) == true
    }
}
