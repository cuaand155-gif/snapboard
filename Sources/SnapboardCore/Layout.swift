import CoreGraphics
import Foundation

/// A zone layout for one screen, as a tree of splits. Every leaf is a zone.
///
/// Positions are in "unit space": 0...1 across the screen's usable area, with y going DOWN
/// (0 is the top). The editor works in this space directly; `ScreenMath` turns it into real
/// screen frames.
public indirect enum LayoutNode: Codable, Equatable {
    case zone
    /// `ratio` is the share of the space the first child gets (0.1...0.9).
    /// `.sideBySide`: first is left. `.stacked`: first is on top.
    case split(axis: SplitAxis, ratio: Double, first: LayoutNode, second: LayoutNode)
}

public enum SplitAxis: String, Codable, Equatable {
    case sideBySide   // a vertical divider: left | right
    case stacked      // a horizontal divider: top / bottom
}

/// Where a node sits in the tree: 0 = first child, 1 = second child, from the root.
public typealias NodePath = [Int]

/// A divider the editor can drag: which split it belongs to, its axis and where it is drawn.
public struct LayoutDivider: Equatable {
    public let path: NodePath
    public let axis: SplitAxis
    /// The divider line in unit space (zero width for `.sideBySide`, zero height for `.stacked`).
    public let line: CGRect
    /// The area the split covers, so a drag can be turned back into a ratio.
    public let bounds: CGRect
}

public enum LayoutLimits {
    public static let minRatio = 0.1
    public static let maxRatio = 0.9
    public static let maxZones = 12
}

public extension LayoutNode {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Zones in reading order (left to right, top to bottom within each split), in unit space.
    func zones(in rect: CGRect = LayoutNode.unit) -> [CGRect] {
        switch self {
        case .zone:
            return [rect]
        case let .split(axis, ratio, first, second):
            let (a, b) = Self.divide(rect, axis: axis, ratio: ratio)
            return first.zones(in: a) + second.zones(in: b)
        }
    }

    var zoneCount: Int { zones().count }

    /// Every divider, for the editor.
    func dividers(in rect: CGRect = LayoutNode.unit, path: NodePath = []) -> [LayoutDivider] {
        guard case let .split(axis, ratio, first, second) = self else { return [] }
        let (a, b) = Self.divide(rect, axis: axis, ratio: ratio)
        let line: CGRect = axis == .sideBySide
            ? CGRect(x: a.maxX, y: rect.minY, width: 0, height: rect.height)
            : CGRect(x: rect.minX, y: a.maxY, width: rect.width, height: 0)
        return [LayoutDivider(path: path, axis: axis, line: line, bounds: rect)]
            + first.dividers(in: a, path: path + [0])
            + second.dividers(in: b, path: path + [1])
    }

    /// The index of the zone containing `point` (unit space), or nil when outside.
    func zoneIndex(at point: CGPoint) -> Int? {
        zones().firstIndex { $0.contains(point) || Self.onFarEdge(point, of: $0) }
    }

    /// Splits zone `index` in two, equal halves. Does nothing past `LayoutLimits.maxZones`.
    func splitting(zone index: Int, axis: SplitAxis) -> LayoutNode {
        guard zoneCount < LayoutLimits.maxZones, let path = path(ofZone: index) else { return self }
        return replacing(at: path, with: .split(axis: axis, ratio: 0.5, first: .zone, second: .zone))
    }

    /// Removes zone `index`; its neighbour in the same split takes its space. The last zone stays.
    func removing(zone index: Int) -> LayoutNode {
        guard let path = path(ofZone: index), let parentPath = path.isEmpty ? nil : Array(path.dropLast()),
              case let .split(_, _, first, second)? = node(at: parentPath) else { return self }
        let sibling = path.last == 0 ? second : first
        return replacing(at: parentPath, with: sibling)
    }

    /// Moves the divider of the split at `path` so the first side gets `ratio` (clamped).
    func settingRatio(_ ratio: Double, at path: NodePath) -> LayoutNode {
        guard case let .split(axis, _, first, second)? = node(at: path) else { return self }
        let r = min(max(ratio, LayoutLimits.minRatio), LayoutLimits.maxRatio)
        return replacing(at: path, with: .split(axis: axis, ratio: r, first: first, second: second))
    }

    /// The ratio a divider should take when dragged to `point` (unit space).
    static func ratio(for divider: LayoutDivider, draggedTo point: CGPoint) -> Double {
        let b = divider.bounds
        let raw = divider.axis == .sideBySide
            ? Double((point.x - b.minX) / max(b.width, 0.0001))
            : Double((point.y - b.minY) / max(b.height, 0.0001))
        return min(max(raw, LayoutLimits.minRatio), LayoutLimits.maxRatio)
    }

    // MARK: - Tree helpers

    func node(at path: NodePath) -> LayoutNode? {
        guard let step = path.first else { return self }
        guard case let .split(_, _, first, second) = self, step == 0 || step == 1 else { return nil }
        return (step == 0 ? first : second).node(at: Array(path.dropFirst()))
    }

    func replacing(at path: NodePath, with replacement: LayoutNode) -> LayoutNode {
        guard let step = path.first else { return replacement }
        guard case let .split(axis, ratio, first, second) = self else { return self }
        let rest = Array(path.dropFirst())
        return step == 0
            ? .split(axis: axis, ratio: ratio, first: first.replacing(at: rest, with: replacement), second: second)
            : .split(axis: axis, ratio: ratio, first: first, second: second.replacing(at: rest, with: replacement))
    }

    /// The path to zone `index` (reading order), or nil when out of range.
    func path(ofZone index: Int) -> NodePath? {
        var paths: [NodePath] = []
        func walk(_ node: LayoutNode, _ path: NodePath) {
            switch node {
            case .zone: paths.append(path)
            case let .split(_, _, first, second):
                walk(first, path + [0])
                walk(second, path + [1])
            }
        }
        walk(self, [])
        return paths.indices.contains(index) ? paths[index] : nil
    }

    private static func divide(_ rect: CGRect, axis: SplitAxis, ratio: Double) -> (CGRect, CGRect) {
        let r = CGFloat(min(max(ratio, LayoutLimits.minRatio), LayoutLimits.maxRatio))
        switch axis {
        case .sideBySide:
            let w = rect.width * r
            return (CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                    CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height))
        case .stacked:
            let h = rect.height * r
            return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h),
                    CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h))
        }
    }

    /// CGRect.contains excludes the max edges; the screen's right and bottom edges still count.
    private static func onFarEdge(_ p: CGPoint, of r: CGRect) -> Bool {
        let inX = p.x >= r.minX && p.x <= r.maxX, inY = p.y >= r.minY && p.y <= r.maxY
        return inX && inY && (abs(p.x - 1) < 0.0001 || abs(p.y - 1) < 0.0001)
    }
}

/// Starting layouts offered in the editor and on first launch.
public enum Preset: String, CaseIterable, Codable {
    case full, halves, thirds, bigLeftTwoRight, quarters

    public var title: String {
        switch self {
        case .full: return "One zone"
        case .halves: return "Halves"
        case .thirds: return "Thirds"
        case .bigLeftTwoRight: return "Big left, two right"
        case .quarters: return "Quarters"
        }
    }

    public var layout: LayoutNode {
        let half = LayoutNode.split(axis: .sideBySide, ratio: 0.5, first: .zone, second: .zone)
        let twoStacked = LayoutNode.split(axis: .stacked, ratio: 0.5, first: .zone, second: .zone)
        switch self {
        case .full:
            return .zone
        case .halves:
            return half
        case .thirds:
            return .split(axis: .sideBySide, ratio: 1.0 / 3, first: .zone,
                          second: .split(axis: .sideBySide, ratio: 0.5, first: .zone, second: .zone))
        case .bigLeftTwoRight:
            return .split(axis: .sideBySide, ratio: 0.6, first: .zone, second: twoStacked)
        case .quarters:
            return .split(axis: .sideBySide, ratio: 0.5, first: twoStacked, second: twoStacked)
        }
    }
}
