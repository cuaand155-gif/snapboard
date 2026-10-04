import AppKit
import Security
import SnapboardCore

/// The app's remembered state, saved to ~/Library/Application Support/Snapboard/settings.json.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var state: SavedState { didSet { save() } }

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Snapboard", isDirectory: true).appendingPathComponent("settings.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(SavedState.self, from: data) {
            state = loaded
        } else {
            state = SavedState()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Snapboard could not save its settings: \(error.localizedDescription)")
        }
    }

    func layout(for screen: NSScreen) -> LayoutNode { state.layout(for: screen.snapKey) }
    func setLayout(_ layout: LayoutNode, for screen: NSScreen) { state.layouts[screen.snapKey] = layout }
}

extension NSScreen {
    var snapKey: String { screenKey(name: localizedName, size: frame.size) }

    /// The screen the mouse is on.
    static var underMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main
    }

    /// The height every Accessibility coordinate is measured against: the screen at AppKit (0, 0).
    static var mainHeight: CGFloat { screens.first?.frame.height ?? 0 }
}

/// The Lifeboard widget token, kept in the Mac's Keychain (never in the settings file).
enum Keychain {
    private static let service = "Snapboard"
    private static let account = "lifeboard-widget-token"

    static func token() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setToken(_ token: String) -> Bool {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
