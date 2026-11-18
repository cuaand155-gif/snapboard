import AppKit
import Combine
import SwiftUI
import SnapboardCore

/// Snapboard lives in the menu bar (no Dock icon). The menu switches layouts, opens the
/// layout editor, adds and removes widgets, pauses snapping and opens Settings.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let snapper = Snapper()
    private let hotkeys = Hotkeys()
    private let widgets = WidgetManager()
    private lazy var customDocks = CustomDockController { [weak self] id in self?.openLibraryItem(id) }
    private let editor = LayoutEditorController()
    private var settingsWindow: NSWindow?
    private var workspaceWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var toolWindows: [String: NSWindow] = [:]
    private var permissionTimer: Timer?
    private var libraryObserver: AnyCancellable?
    private var recordingIndicatorTimer: Timer?
    private var lastRecordingActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Snapboard")
        recordingIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateRecordingIndicator()
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        widgets.start()
        customDocks.sync()
        libraryObserver = AppModel.shared.$state.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.customDocks.sync() }
        }
        let automationWarnings = AutomationRuntime.shared.refresh()
        automationWarnings.forEach { NSLog("Snapboard automation: %@", $0) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.widgets.screensChanged()
            self?.customDocks.sync()
        }

        snapper.onPermissionNeeded = { [weak self] in self?.showWelcome() }
        hotkeys.onPermissionNeeded = { [weak self] in self?.showWelcome() }
        if WindowMover.isTrusted { startSnapping() } else { showWelcome() }
        if let warning = AppModel.shared.launchWarning {
            let alert = NSAlert()
            alert.messageText = "Snapboard could not read saved settings"
            alert.informativeText = warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: Permission and first launch

    private func startSnapping() {
        welcomeWindow?.close()
        welcomeWindow = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        snapper.start()
        applyShortcutSetting()
    }

    /// Explains the one permission, opens the right Settings page, and carries on by itself
    /// as soon as the permission is switched on (no restart needed).
    private func showWelcome() {
        if let w = welcomeWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        permissionTimer?.invalidate()
        let view = WelcomeView(openSettings: {
            WindowMover.askForPermission()
            WindowMover.openAccessibilitySettings()
        }, refreshAfterUpdate: {
            WindowMover.refreshPermissionAfterUpdate()
        })
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 280), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Welcome to Snapboard"
        w.delegate = self
        w.contentView = NSHostingView(rootView: view)
        w.isReleasedWhenClosed = false
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        welcomeWindow = w
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            if WindowMover.isTrusted { self?.startSnapping() }
        }
    }

    /// Closing the welcome window without allowing: stop checking; the menu offers it again.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === welcomeWindow else { return }
        permissionTimer?.invalidate()
        permissionTimer = nil
        welcomeWindow = nil
    }

    private func applyShortcutSetting() {
        if AppModel.shared.state.shortcutsOn && WindowMover.isTrusted { hotkeys.start() } else { hotkeys.stop() }
        AutomationRuntime.shared.refresh().forEach { NSLog("Snapboard automation: %@", $0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if WindowMover.isTrusted {
            openLibrary()
        } else {
            showWelcome()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingIndicatorTimer?.invalidate()
        AutomationRuntime.shared.stop()
        customDocks.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let recorder = RecordingWindowController.shared
        guard recorder.isRecording || recorder.isBusy || recorder.hasPendingExport else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Finish your recording before quitting"
        alert.informativeText = "Open the recorder to finish, export, or discard the recording before quitting Snapboard."
        alert.addButton(withTitle: "Open recorder")
        alert.addButton(withTitle: "Keep Snapboard open")
        if alert.runModal() == .alertFirstButtonReturn { recorder.open() }
        return .terminateCancel
    }

    private func updateRecordingIndicator() {
        let active = RecordingWindowController.shared.isRecording
        guard active != lastRecordingActive else { return }
        lastRecordingActive = active
        statusItem.button?.image = NSImage(systemSymbolName: active ? "record.circle.fill" : "rectangle.split.2x1",
                                          accessibilityDescription: active ? "Snapboard recording" : "Snapboard")
        statusItem.button?.contentTintColor = active ? .systemRed : nil
    }

    // MARK: Menu (rebuilt each time it opens, so it always shows the current state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = AppModel.shared.state

        if !WindowMover.isTrusted {
            menu.addItem(item("Allow Snapboard to move windows…") { [weak self] in self?.showWelcome() })
            menu.addItem(.separator())
        }

        for screen in NSScreen.screens {
            let title = NSScreen.screens.count > 1 ? "Edit layout: \(screen.localizedName)…" : "Edit layout…"
            menu.addItem(item(title) { [weak self] in self?.editor.open(for: screen) })
            let presets = NSMenuItem(title: NSScreen.screens.count > 1 ? "Quick layout: \(screen.localizedName)" : "Quick layout",
                                     action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for p in Preset.allCases {
                let i = item(p.title) { AppModel.shared.setLayout(p.layout, for: screen) }
                i.state = AppModel.shared.layout(for: screen) == p.layout ? .on : .off
                sub.addItem(i)
            }
            presets.submenu = sub
            menu.addItem(presets)
        }
        menu.addItem(.separator())

        let workspacesItem = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        let workspaceMenu = NSMenu()
        if state.workspaces.isEmpty {
            let empty = NSMenuItem(title: "No workspaces saved", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            workspaceMenu.addItem(empty)
        } else {
            for workspace in state.workspaces {
                let use = item(workspace.name) { [weak self] in
                    if !AppModel.shared.activateWorkspace(workspace.id) {
                        self?.showWorkspaceError("This workspace no longer exists.")
                    }
                }
                use.state = state.activeWorkspaceID == workspace.id ? .on : .off
                workspaceMenu.addItem(use)
            }
        }
        if let active = state.workspaces.first(where: { $0.id == state.activeWorkspaceID }), !active.items.isEmpty {
            workspaceMenu.addItem(.separator())
            let openItem = NSMenuItem(title: "Open saved item", action: nil, keyEquivalent: "")
            let openMenu = NSMenu()
            for savedItem in active.items {
                openMenu.addItem(item(savedItem.title) { [weak self] in
                    if let error = AppModel.shared.openWorkspaceItem(savedItem) { self?.showWorkspaceError(error) }
                })
            }
            openItem.submenu = openMenu
            workspaceMenu.addItem(openItem)
        }
        workspaceMenu.addItem(.separator())
        workspaceMenu.addItem(item("Manage workspaces…") { [weak self] in self?.openWorkspaces() })
        workspacesItem.submenu = workspaceMenu
        menu.addItem(workspacesItem)
        menu.addItem(.separator())

        menu.addItem(item("Library and launcher…") { [weak self] in self?.openLibrary() })
        menu.addItem(item("Automation…") { [weak self] in self?.openAutomation() })
        let surfaces = NSMenuItem(title: "Custom surfaces", action: nil, keyEquivalent: "")
        let surfacesMenu = CustomSurfacesMenu.makeMenu(groups: state.menuGroups, items: state.libraryItems,
                                                      surfaceWorkspaceID: state.surfaceWorkspaceID) { [weak self] id in
            self?.openLibraryItem(id)
        }
        surfacesMenu.addItem(.separator())
        surfacesMenu.addItem(item("Search menu items…") { [weak self] in self?.openMenuPicker() })
        surfacesMenu.addItem(item("Manage docks and groups…") { [weak self] in self?.openSurfaces() })
        surfaces.submenu = surfacesMenu
        menu.addItem(surfaces)
        menu.addItem(item("Dock presets…") { [weak self] in self?.openDockPresets() })
        if RecordingWindowController.shared.isRecording {
            let active = NSMenuItem(title: "● Recording in progress", action: nil, keyEquivalent: "")
            active.isEnabled = false
            menu.addItem(active)
            menu.addItem(item("Stop recording") { RecordingWindowController.shared.stop() })
        }
        menu.addItem(item("Record screen…") { RecordingWindowController.shared.open() })
        menu.addItem(.separator())

        let widgetsItem = NSMenuItem(title: "Widgets", action: nil, keyEquivalent: "")
        let wsub = NSMenu()
        for kind in WidgetKind.allCases {
            let i = item(kind.title) { [weak self] in self?.widgets.toggle(kind) }
            i.state = widgets.isShown(kind) ? .on : .off
            wsub.addItem(i)
        }
        widgetsItem.submenu = wsub
        menu.addItem(widgetsItem)
        menu.addItem(.separator())

        let pause = item(state.snappingOn ? "Pause snapping" : "Resume snapping") {
            AppModel.shared.state.snappingOn.toggle()
        }
        menu.addItem(pause)
        if state.shortcutsOn {
            let keys = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
            let ksub = NSMenu()
            for b in Hotkeys.bindings { ksub.addItem(item(b.label) { b.action.apply() }) }
            keys.submenu = ksub
            menu.addItem(keys)
        }
        menu.addItem(item("Open Lifeboard") { [weak self] in
            if !AppModel.shared.openLifeboard() { self?.openSettings() }   // no address yet: add it first
        })
        menu.addItem(item("Settings…") { [weak self] in self?.openSettings() })
        menu.addItem(.separator())
        menu.addItem(item("Quit Snapboard") { NSApp.terminate(nil) })
    }

    private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(onFeedChanged: { [weak self] in
                self?.widgets.feed.refresh()
                self?.applyShortcutSetting()
            })
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 420), styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Snapboard Settings"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
            // Shortcut on/off takes effect when Settings closes.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                self?.applyShortcutSetting()
                self?.widgets.feed.refresh()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func openWorkspaces() {
        if workspaceWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 500),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Snapboard Workspaces"
            window.contentView = NSHostingView(rootView: WorkspaceEditorView())
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 580, height: 420)
            window.center()
            workspaceWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        workspaceWindow?.makeKeyAndOrderFront(nil)
    }

    private func showWorkspaceError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Snapboard could not open that item"
        alert.informativeText = message
        alert.runModal()
    }

    private func openLibraryItem(_ id: UUID) {
        guard let item = AppModel.shared.state.libraryItems.first(where: { $0.id == id }) else {
            showWorkspaceError("That library item is no longer available.")
            return
        }
        if let error = AppModel.shared.openLibraryItem(item, onAction: { [weak self] id in self?.runAction(id) }) {
            showWorkspaceError(error)
        }
    }

    private func runAction(_ id: UUID) {
        guard let action = AppModel.shared.state.savedActions.first(where: { $0.id == id }) else {
            showWorkspaceError("That saved action is no longer available.")
            return
        }
        if let error = AutomationRuntime.shared.run(action) { showWorkspaceError(error) }
    }

    private func openTool<Content: View>(_ key: String, title: String, size: NSSize,
                                         @ViewBuilder content: () -> Content) {
        if toolWindows[key] == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = title
            window.contentView = NSHostingView(rootView: content())
            window.isReleasedWhenClosed = false
            window.center()
            toolWindows[key] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        toolWindows[key]?.makeKeyAndOrderFront(nil)
    }

    private func openLibrary() {
        openTool("library", title: "Snapboard Library and Launcher", size: NSSize(width: 780, height: 580)) {
            LibraryLauncherView(onAction: { [weak self] id in self?.runAction(id) })
        }
    }

    private func openAutomation() {
        openTool("automation", title: "Snapboard Automation", size: NSSize(width: 760, height: 560)) {
            AutomationEditorView()
        }
    }

    private func openSurfaces() {
        openTool("surfaces", title: "Snapboard Docks and Menu Groups", size: NSSize(width: 720, height: 560)) {
            CustomSurfacesView(onChange: { [weak self] in self?.customDocks.sync() })
        }
    }

    private func openMenuPicker() {
        openTool("menu-picker", title: "Snapboard Menu Items", size: NSSize(width: 400, height: 340)) {
            MenuGroupPickerView(onOpen: { [weak self] id in
                self?.toolWindows["menu-picker"]?.close()
                self?.openLibraryItem(id)
            })
        }
    }

    private func openDockPresets() {
        openTool("dock-presets", title: "Snapboard Dock Presets", size: NSSize(width: 640, height: 500)) {
            DockPresetView()
        }
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction(action)
        i.target = target
        i.representedObject = target   // keeps the target alive as long as the item
        return i
    }
}

/// Lets a menu item run a closure.
final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

struct WelcomeView: View {
    let openSettings: () -> Void
    let refreshAfterUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snapboard needs one permission").font(.title2.bold())
            Text("To move other apps' windows into your zones, macOS needs you to allow Snapboard under Privacy & Security → Accessibility.")
            Text("Press the button, switch Snapboard on in the list, and this window closes by itself.")
                .foregroundStyle(.secondary)
            Text("Already switched on? After an app update, macOS still remembers the older version. Click \"Refresh after update\", then switch Snapboard back on once.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Refresh after update", action: refreshAfterUpdate)
                Spacer()
                Button("Open Accessibility settings", action: openSettings).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 280)
    }
}
