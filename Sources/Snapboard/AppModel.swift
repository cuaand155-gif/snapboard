import AppKit
import Combine
import Security
import SnapboardCore

/// The app's remembered state, saved to ~/Library/Application Support/Snapboard/settings.json.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var state: SavedState { didSet { save() } }
    private(set) var launchWarning: String?
    private var savingEnabled = true

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Snapboard", isDirectory: true).appendingPathComponent("settings.json")
    }()

    private init() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            state = SavedState()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            state = try JSONDecoder().decode(SavedState.self, from: data)
        } catch {
            state = SavedState()
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("settings-unreadable-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: fileURL, to: backup)
                launchWarning = "Snapboard loaded default settings because it could not read settings.json. A copy of the original is at \(backup.path). Changes you make now will save to settings.json."
            } catch {
                savingEnabled = false
                launchWarning = "Snapboard loaded default settings because it could not read settings.json. It could not back up the original file, so it will not save changes. Your original settings remain at \(fileURL.path)."
            }
        }
    }

    private func save() {
        guard savingEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Snapboard could not save its settings: \(error.localizedDescription)")
        }
    }

    /// Opens Lifeboard in the browser.
    /// Returns false when there is no address.
    @discardableResult
    func openLifeboard() -> Bool {
        guard let url = lifeboardHomeURL(from: state.lifeboardURL) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    func layout(for screen: NSScreen) -> LayoutNode { state.layout(for: screen.snapKey) }
    func setLayout(_ layout: LayoutNode, for screen: NSScreen) { state.layouts[screen.snapKey] = layout }

    /// A workspace captures layouts for the screens connected when it is saved.
    private func currentScreenLayouts() -> [String: LayoutNode] {
        var layouts: [String: LayoutNode] = [:]
        for screen in NSScreen.screens { layouts[screen.snapKey] = layout(for: screen) }
        return layouts
    }

    @discardableResult
    func createWorkspace(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let workspace = Workspace(name: trimmed, layouts: currentScreenLayouts())
        var next = state
        next.workspaces.append(workspace)
        next.activeWorkspaceID = workspace.id
        state = next
        return workspace.id
    }

    func renameWorkspace(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return false }
        var next = state
        next.workspaces[index].name = trimmed
        state = next
        return true
    }

    func activateWorkspace(_ id: UUID) -> Bool {
        guard let workspace = state.workspaces.first(where: { $0.id == id }) else { return false }
        var next = state
        next.layouts.merge(workspace.layouts) { _, saved in saved }
        next.activeWorkspaceID = id
        state = next
        return true
    }

    func updateWorkspaceLayouts(_ id: UUID) -> Bool {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return false }
        var next = state
        next.workspaces[index].layouts.merge(currentScreenLayouts()) { _, current in current }
        state = next
        return true
    }

    func addApplication(_ url: URL, to id: UUID) -> String? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path) else {
            return "Choose an application in Finder (.app)."
        }
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return "This workspace no longer exists." }
        var next = state
        next.workspaces[index].items.append(WorkspaceItem(kind: .application,
                                                         title: url.deletingPathExtension().lastPathComponent,
                                                         target: url.path))
        state = next
        return nil
    }

    func addLink(title: String, address: String, to id: UUID) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else {
            return "Enter a full http:// or https:// link with a website address."
        }
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return "This workspace no longer exists." }
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = state
        next.workspaces[index].items.append(WorkspaceItem(kind: .link,
                                                         title: label.isEmpty ? (url.host ?? trimmed) : label,
                                                         target: trimmed))
        state = next
        return nil
    }

    func removeItem(_ itemID: UUID, from workspaceID: UUID) {
        guard let index = state.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        var next = state
        next.workspaces[index].items.removeAll { $0.id == itemID }
        state = next
    }

    func openWorkspaceItem(_ item: WorkspaceItem) -> String? {
        switch item.kind {
        case .application:
            let url = URL(fileURLWithPath: item.target)
            guard url.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: url.path) else {
                return "The application “\(item.title)” is missing. Add it again from its current location."
            }
            return NSWorkspace.shared.open(url) ? nil : "macOS could not open “\(item.title)”."
        case .link:
            guard let url = URL(string: item.target), let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else {
                return "The saved link “\(item.title)” is invalid. Remove it and add a full http(s) link."
            }
            return NSWorkspace.shared.open(url) ? nil : "macOS could not open “\(item.title)”."
        }
    }
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
