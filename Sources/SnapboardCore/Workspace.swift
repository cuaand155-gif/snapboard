import Foundation

/// A named context with a saved window layout for each screen and launchable items.
public struct Workspace: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var layouts: [String: LayoutNode]
    public var items: [WorkspaceItem]

    public init(id: UUID = UUID(), name: String, layouts: [String: LayoutNode] = [:], items: [WorkspaceItem] = []) {
        self.id = id
        self.name = name
        self.layouts = layouts
        self.items = items
    }
}

public struct WorkspaceItem: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable, Equatable {
        case application
        case link
    }

    public var id: UUID
    public var kind: Kind
    public var title: String
    public var target: String

    public init(id: UUID = UUID(), kind: Kind, title: String, target: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.target = target
    }
}
