import AppKit
import Combine
import Foundation
import SwiftUI

/// Represents an installed application found on the system.
public struct InstalledApp: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let icon: NSImage?

    public init(url: URL) {
        self.id = url.path
        self.name = url.deletingPathExtension().lastPathComponent
        self.url = url
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.id == rhs.id
    }
}

/// Discovers, caches, and indexes installed Mac applications.
public final class AppDiscoveryModel: ObservableObject {
    public static let shared = AppDiscoveryModel()

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public var query = "" {
        didSet { selectedIndex = 0 }   // a new search starts again at the first app
    }
    @Published public private(set) var isLoading = false
    /// The highlighted tile in the grid; arrow keys move it, Return opens it.
    @Published public var selectedIndex = 0
    /// How many tiles fit across the grid, measured by the view; used so Up/Down jump a whole row.
    public var gridColumns = 5

    private init() {
        refresh()
    }

    public var filteredApps: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(q) }
    }

    /// The app under the highlight (the first match if the highlight is out of range).
    public var selectedApp: InstalledApp? {
        let list = filteredApps
        return list.indices.contains(selectedIndex) ? list[selectedIndex] : list.first
    }

    public func moveSelection(by step: Int) {
        let count = filteredApps.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + step, 0), count - 1)
    }

    public func refresh() {
        guard !isLoading else { return }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let searchDirs = [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                URL(fileURLWithPath: "/System/Applications/Utilities"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            ]

            var foundURLs: [URL] = []
            var seenNames = Set<String>()

            for dir in searchDirs {
                guard let enumerator = FileManager.default.enumerator(
                    at: dir,
                    includingPropertiesForKeys: [.isApplicationKey],
                    options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "app" {
                        let baseName = fileURL.deletingPathExtension().lastPathComponent
                        if seenNames.insert(baseName.lowercased()).inserted {
                            foundURLs.append(fileURL)
                        }
                    }
                }
            }

            let loaded = foundURLs.map { InstalledApp(url: $0) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self?.apps = loaded
                self?.isLoading = false
            }
        }
    }
}

/// Window controller managing the full-screen LaunchOS-style overlay.
public final class FullscreenLauncherController: NSObject, NSWindowDelegate {
    public static let shared = FullscreenLauncherController()

    private var window: NSWindow?
    private var localKeyMonitor: Any?

    private override init() {
        super.init()
    }

    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    public func toggle() {
        if isVisible { close() } else { open() }
    }

    public func open() {
        AppDiscoveryModel.shared.query = ""
        AppDiscoveryModel.shared.refresh()   // pick up apps installed since launch
        if window == nil {
            setupWindow()
        }
        // Covers the screen the pointer is on, so it opens where the user is.
        guard let w = window, let screen = NSScreen.underMouse else { return }
        w.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        startKeyMonitor()
    }

    public func close() {
        stopKeyMonitor()
        window?.orderOut(nil)
    }

    private func setupWindow() {
        guard let screen = NSScreen.underMouse else { return }
        // A borderless window can't become key by default, so typing and arrow keys never reach it.
        let w = KeyableBorderlessWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.delegate = self

        let view = FullscreenLauncherView(
            discovery: AppDiscoveryModel.shared,
            onClose: { [weak self] in self?.close() }
        )
        w.contentView = NSHostingView(rootView: view)
        self.window = w
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            let discovery = AppDiscoveryModel.shared
            let columns = max(1, discovery.gridColumns)
            switch event.keyCode {
            case 53: // Escape
                self.close()
                return nil
            case 123: // Left
                discovery.moveSelection(by: -1)
                return nil
            case 124: // Right
                discovery.moveSelection(by: 1)
                return nil
            case 125: // Down: one row
                discovery.moveSelection(by: columns)
                return nil
            case 126: // Up: one row
                discovery.moveSelection(by: -columns)
                return nil
            case 36, 76: // Return / Enter opens the highlighted app
                if let app = discovery.selectedApp {
                    NSWorkspace.shared.open(app.url)
                    self.close()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
    }
}

/// SwiftUI View rendering the full-screen LaunchOS app grid with live search.
public struct FullscreenLauncherView: View {
    @ObservedObject var discovery: AppDiscoveryModel
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 24)
    ]

    public var body: some View {
        ZStack {
            // Blurred backdrop that dismisses on click
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 28) {
                // Search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)

                    TextField("Search applications…", text: $discovery.query)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        // Return opens the highlighted app; the key monitor in FullscreenLauncherController handles it.

                    if !discovery.query.isEmpty {
                        Button(action: { discovery.query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .frame(maxWidth: 580)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 6)
                .padding(.top, 40)

                // App Grid
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(Array(discovery.filteredApps.enumerated()), id: \.element.id) { index, app in
                                LauncherAppTile(
                                    app: app,
                                    isSelected: index == discovery.selectedIndex,
                                    onLaunch: {
                                        launch(app)
                                    }
                                )
                                .id(app.id)
                            }
                        }
                        // Tells the key handler how many tiles fit across, so Up/Down move a whole row.
                        .background(GeometryReader { geo in
                            Color.clear
                                .onAppear { discovery.gridColumns = max(1, Int((geo.size.width + 24) / 134)) }
                                .onChange(of: geo.size.width) { width in
                                    discovery.gridColumns = max(1, Int((width + 24) / 134))
                                }
                        })
                        .padding(.horizontal, 64)
                        .padding(.vertical, 24)
                    }
                    .onChange(of: discovery.selectedIndex) { _ in
                        if let id = discovery.selectedApp?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onAppear {
            isSearchFocused = true
            discovery.selectedIndex = 0
        }
    }

    private func launch(_ app: InstalledApp) {
        NSWorkspace.shared.open(app.url)
        onClose()
    }
}

/// Individual tile in the LaunchOS-style app grid.
struct LauncherAppTile: View {
    let app: InstalledApp
    let isSelected: Bool
    let onLaunch: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onLaunch) {
            VStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                        .shadow(color: .black.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 12 : 6, x: 0, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 72, height: 72)
                        .overlay(Image(systemName: "app.fill").font(.title))
                }

                Text(app.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
            }
            .padding(8)
            .frame(width: 110)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected || isHovered ? Color.white.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A borderless window that is allowed to take keyboard focus, so the search field and arrow keys work.
final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
