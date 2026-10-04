import AppKit
import SwiftUI
import SnapboardCore

/// Snapboard lives in the menu bar (no Dock icon). The menu switches layouts, opens the
/// layout editor, adds and removes widgets, pauses snapping and opens Settings.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let snapper = Snapper()
    private let hotkeys = Hotkeys()
    private let widgets = WidgetManager()
    private let editor = LayoutEditorController()
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Snapboard")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        widgets.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.widgets.screensChanged() }

        if WindowMover.isTrusted { startSnapping() } else { showWelcome() }
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
        })
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 260), styleMask: [.titled, .closable],
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snapboard needs one permission").font(.title2.bold())
            Text("To move other apps' windows into your zones, macOS needs you to allow Snapboard under Privacy & Security → Accessibility.")
            Text("Press the button, switch Snapboard on in the list, and this window closes by itself.")
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Open Accessibility settings", action: openSettings).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 260)
    }
}
