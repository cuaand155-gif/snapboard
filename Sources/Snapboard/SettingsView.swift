import AppKit
import ServiceManagement
import SwiftUI
import SnapboardCore

struct SettingsView: View {
    @ObservedObject var model = AppModel.shared
    @State private var token = Keychain.token() ?? ""
    @State private var testResult: String?
    @State private var openAtLogin = [SMAppService.Status.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    let onFeedChanged: () -> Void

    init(onFeedChanged: @escaping () -> Void) {
        self.onFeedChanged = onFeedChanged
    }

    var body: some View {
        Form {
            Section("Snapping") {
                Toggle("Hold Shift while dragging a window to snap it", isOn: $model.state.snappingOn)
                Toggle("Keyboard shortcuts (Control-Option + arrows or Return)", isOn: $model.state.shortcutsOn)
            }
            Section("Widgets") {
                Toggle("Line widgets up on a grid when dropped", isOn: $model.state.widgetGridOn)
            }
            Section("Lifeboard") {
                TextField("Lifeboard address", text: $model.state.lifeboardURL, prompt: Text("your-site.vercel.app"))
                SecureField("Widget token", text: $token)
                HStack {
                    Button("Save and test connection") { saveAndTest() }
                    if let r = testResult { Text(r).font(.callout).foregroundStyle(.secondary) }
                }
                Text("The token is the WIDGET_TOKEN you set in Vercel. It is kept in your Mac's Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open Snapboard when I log in", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { on in setOpenAtLogin(on) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }

    private func saveAndTest() {
        Keychain.setToken(token)
        testResult = "Checking…"
        FeedModel.fetch { result in
            switch result {
            case let .success(feed): testResult = "Connected. \(FeedText.tasksHeadline(feed.tasks))."
            case let .failure(err): testResult = err.message
            }
            onFeedChanged()
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        let status = SMAppService.mainApp.status
        // Already in the state asked for (this also stops the toggle reset below from looping).
        if on == (status == .enabled || status == .requiresApproval) { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                testResult = "Almost: allow Snapboard under System Settings → General → Login Items."
            }
        } catch {
            testResult = "Couldn't change the login setting: \(error.localizedDescription)"
            let now = SMAppService.mainApp.status
            openAtLogin = now == .enabled || now == .requiresApproval
        }
    }
}
