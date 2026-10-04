import CoreGraphics
import Foundation

/// Everything Snapboard remembers, saved as one small JSON file in
/// ~/Library/Application Support/Snapboard/settings.json so a reinstall can restore it.
/// The Lifeboard token is NOT here; it lives in the Keychain.
public struct SavedState: Codable, Equatable {
    /// Zone layout per screen, keyed by `screenKey`.
    public var layouts: [String: LayoutNode] = [:]
    /// Widget kind -> saved frame (AppKit coordinates). A missing kind is not shown.
    public var widgets: [String: CodableRect] = [:]
    public var snappingOn = true
    public var shortcutsOn = true
    public var widgetGridOn = true
    public var lifeboardURL = ""

    public init() {}

    public func layout(for screen: String) -> LayoutNode {
        layouts[screen] ?? Preset.halves.layout
    }

    // Older files may lack newer keys; missing keys fall back to the defaults above.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layouts = (try? c.decode([String: LayoutNode].self, forKey: .layouts)) ?? [:]
        widgets = (try? c.decode([String: CodableRect].self, forKey: .widgets)) ?? [:]
        snappingOn = (try? c.decode(Bool.self, forKey: .snappingOn)) ?? true
        shortcutsOn = (try? c.decode(Bool.self, forKey: .shortcutsOn)) ?? true
        widgetGridOn = (try? c.decode(Bool.self, forKey: .widgetGridOn)) ?? true
        lifeboardURL = (try? c.decode(String.self, forKey: .lifeboardURL)) ?? ""
    }
}

public struct CodableRect: Codable, Equatable {
    public var x, y, width, height: Double
    public init(_ r: CGRect) {
        x = Double(r.minX); y = Double(r.minY); width = Double(r.width); height = Double(r.height)
    }
    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// A stable name for a screen: its display name plus its size, so the laptop screen and an
/// external monitor each keep their own layout.
public func screenKey(name: String, size: CGSize) -> String {
    "\(name) \(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
}

/// Turns "lifeboard.vercel.app", "https://x.app/" or "https://x.app/today" into the widget feed URL.
public func feedURL(from base: String) -> URL? {
    lifeboardURL(from: base, path: "/api/widgets")
}

/// Lifeboard's home page, for the "Open Lifeboard" button.
public func lifeboardHomeURL(from base: String) -> URL? {
    lifeboardURL(from: base, path: "/")
}

private func lifeboardURL(from base: String, path: String) -> URL? {
    var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
    guard var c = URLComponents(string: s), c.host?.isEmpty == false else { return nil }
    c.path = path
    c.query = nil
    c.fragment = nil
    return c.url
}
