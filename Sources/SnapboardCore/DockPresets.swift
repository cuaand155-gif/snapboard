import Foundation

/// The small, explicit set of Dock preferences Snapboard can save and restore.
public enum DockPreferenceKey: String, CaseIterable, Codable {
    case apps = "persistent-apps"
    case folders = "persistent-others"
    case orientation
    case autohide
    case tileSize = "tilesize"
    case magnification
    case largeSize = "largesize"

    public var label: String {
        switch self {
        case .apps: return "Apps"
        case .folders: return "Folders and files"
        case .orientation: return "Position"
        case .autohide: return "Automatically hide"
        case .tileSize: return "Icon size"
        case .magnification: return "Magnification"
        case .largeSize: return "Magnified size"
        }
    }
}

public enum DockPresetError: LocalizedError {
    case invalidSnapshot(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot(let detail): return "Dock preset is invalid: \(detail)"
        }
    }
}

/// Binary property lists retain the Dock tile dictionaries without interpreting undocumented fields.
/// A key absent from the captured preferences is recorded so restore can remove a value introduced later.
public struct DockSnapshot: Codable, Equatable {
    public let values: [String: Data]
    public let absentKeys: [String]

    public init(values: [String: Data], absentKeys: [String]) throws {
        let allowed = Set(DockPreferenceKey.allCases.map(\.rawValue))
        let present = Set(values.keys)
        let absent = Set(absentKeys)
        guard present.isDisjoint(with: absent), present.union(absent) == allowed,
              absent.count == absentKeys.count else {
            throw DockPresetError.invalidSnapshot("preferences must include each supported key exactly once")
        }
        for (key, data) in values {
            let property = try PropertyListSerialization.propertyList(from: data, format: nil)
            switch DockPreferenceKey(rawValue: key) {
            case .apps, .folders:
                guard property is [[String: Any]] else {
                    throw DockPresetError.invalidSnapshot("\(key) must contain Dock tiles")
                }
            case .orientation:
                guard property is String else {
                    throw DockPresetError.invalidSnapshot("orientation must be text")
                }
            case .autohide, .magnification, .tileSize, .largeSize:
                guard property is NSNumber else {
                    throw DockPresetError.invalidSnapshot("\(key) must be a number or switch")
                }
            case nil:
                throw DockPresetError.invalidSnapshot("unsupported preference \(key)")
            }
        }
        self.values = values
        self.absentKeys = absentKeys.sorted()
    }

    private enum CodingKeys: String, CodingKey { case values, absentKeys }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(values: container.decode([String: Data].self, forKey: .values),
                      absentKeys: container.decode([String].self, forKey: .absentKeys))
    }

    public func propertyList(for key: DockPreferenceKey) throws -> Any? {
        guard let data = values[key.rawValue] else { return nil }
        return try PropertyListSerialization.propertyList(from: data, format: nil)
    }

    public func displayValue(for key: DockPreferenceKey) -> String {
        guard let property = try? propertyList(for: key) else { return "System default" }
        switch key {
        case .apps, .folders:
            guard let tiles = property as? [[String: Any]] else { return "Unavailable" }
            let names = tiles.compactMap { tile -> String? in
                let data = tile["tile-data"] as? [String: Any] ?? [:]
                if let label = data["file-label"] as? String, !label.isEmpty { return label }
                if let file = data["file-data"] as? [String: Any],
                   let url = file["_CFURLString"] as? String {
                    return URL(fileURLWithPath: url).lastPathComponent
                }
                return nil
            }
            return names.isEmpty ? "\(tiles.count) entries" : names.joined(separator: ", ")
        case .orientation:
            return (property as? String)?.capitalized ?? "Unavailable"
        case .autohide, .magnification:
            return (property as? NSNumber)?.boolValue == true ? "On" : "Off"
        case .tileSize, .largeSize:
            return (property as? NSNumber).map { "\($0.intValue) pt" } ?? "Unavailable"
        }
    }

    public func isEquivalent(to other: DockSnapshot) -> Bool {
        guard absentKeys == other.absentKeys else { return false }
        for key in DockPreferenceKey.allCases {
            let lhs = try? propertyList(for: key)
            let rhs = try? other.propertyList(for: key)
            switch (lhs, rhs) {
            case (nil, nil): continue
            case let (a?, b?):
                guard (a as AnyObject).isEqual(b) else { return false }
            default: return false
            }
        }
        return true
    }

    public func changes(from current: DockSnapshot) -> [DockPreferenceKey] {
        DockPreferenceKey.allCases.filter { key in
            let old = try? current.propertyList(for: key)
            let new = try? propertyList(for: key)
            switch (old, new) {
            case (nil, nil): return false
            case let (a?, b?): return !(a as AnyObject).isEqual(b)
            default: return true
            }
        }
    }
}

public struct DockPreset: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public let snapshot: DockSnapshot

    public init(id: UUID = UUID(), name: String, snapshot: DockSnapshot) {
        self.id = id
        self.name = name
        self.snapshot = snapshot
    }
}
