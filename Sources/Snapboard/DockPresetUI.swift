import AppKit
import CoreFoundation
import SnapboardCore
import SwiftUI

private enum DockOperationError: LocalizedError {
    case preferencesUnavailable
    case syncFailed
    case verificationFailed
    case noRestorePoint

    var errorDescription: String? {
        switch self {
        case .preferencesUnavailable: return "Snapboard could not open this Mac's Dock preferences."
        case .syncFailed: return "macOS did not save the Dock preferences. Snapboard tried to put the previous settings back."
        case .verificationFailed: return "The Dock settings did not match the preset after saving. Snapboard tried to put the previous settings back."
        case .noRestorePoint: return "There is no previous Dock snapshot to restore."
        }
    }
}

private struct DockRestorePoint: Codable {
    let capturedAt: Date
    let snapshot: DockSnapshot
    var restored: Bool
}

/// Preference writes occur only after the user confirms an apply or restore action in DockPresetView.
private enum DockPreferences {
    private static let domain = "com.apple.dock" as CFString
    private static var restoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapboard", isDirectory: true)
            .appendingPathComponent("dock-restore.json")
    }

    static func capture() throws -> DockSnapshot {
        var values: [String: Data] = [:]
        var absent: [String] = []
        for key in DockPreferenceKey.allCases {
            guard let value = CFPreferencesCopyValue(
                key.rawValue as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
                absent.append(key.rawValue)
                continue
            }
            values[key.rawValue] = try PropertyListSerialization.data(
                fromPropertyList: value, format: .binary, options: 0)
        }
        guard !values.isEmpty else { throw DockOperationError.preferencesUnavailable }
        return try DockSnapshot(values: values, absentKeys: absent)
    }

    static func hasRestorePoint() throws -> Bool {
        guard FileManager.default.fileExists(atPath: restoreURL.path) else { return false }
        return try !JSONDecoder().decode(DockRestorePoint.self, from: Data(contentsOf: restoreURL)).restored
    }

    static func apply(_ preset: DockPreset) throws -> String? {
        if FileManager.default.fileExists(atPath: restoreURL.path) {
            _ = try JSONDecoder().decode(DockRestorePoint.self, from: Data(contentsOf: restoreURL))
        }
        let previous = try capture()
        let point = DockRestorePoint(capturedAt: Date(), snapshot: previous, restored: false)
        let data = try JSONEncoder().encode(point)
        try FileManager.default.createDirectory(
            at: restoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Never change the Dock unless the exact pre-change snapshot is safely on disk.
        try data.write(to: restoreURL, options: .atomic)
        do {
            try writeAndVerify(preset.snapshot)
        } catch {
            try? writeAndVerify(previous)
            throw error
        }
        return restartDockWarning()
    }

    static func restore() throws -> String? {
        let point = try JSONDecoder().decode(DockRestorePoint.self, from: Data(contentsOf: restoreURL))
        guard !point.restored else { throw DockOperationError.noRestorePoint }
        let current = try capture()
        do {
            try writeAndVerify(point.snapshot)
        } catch {
            try? writeAndVerify(current)
            throw error
        }
        let warning = restartDockWarning()
        var consumed = point
        consumed.restored = true
        do {
            try JSONEncoder().encode(consumed).write(to: restoreURL, options: .atomic)
        } catch {
            return "The previous Dock was restored, but Snapboard could not update its restore record: \(error.localizedDescription)"
        }
        return warning
    }

    private static func writeAndVerify(_ snapshot: DockSnapshot) throws {
        for key in DockPreferenceKey.allCases {
            let property = try snapshot.propertyList(for: key)
            CFPreferencesSetValue(key.rawValue as CFString, property.map { $0 as CFPropertyList },
                                  domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw DockOperationError.syncFailed
        }
        guard try capture().isEquivalent(to: snapshot) else {
            throw DockOperationError.verificationFailed
        }
    }

    private static func restartDockWarning() -> String? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        guard !running.isEmpty else { return nil }
        if running.map({ $0.terminate() }).allSatisfy({ $0 }) { return nil }
        return "Dock settings were saved, but Snapboard could not restart Dock. Sign out and back in to see the change."
    }
}

struct DockPresetView: View {
    @ObservedObject private var model = AppModel.shared
    @State private var name = ""
    @State private var selectedID: UUID?
    @State private var current: DockSnapshot?
    @State private var message: String?
    @State private var pendingApply = false
    @State private var pendingRestore = false
    @State private var canRestore = false

    private var selected: DockPreset? {
        model.state.dockPresets.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dock presets").font(.title2).bold()
            Text("Save this Mac's Dock apps, folders, position, size, and visibility. Preview changes before applying a preset.")
                .foregroundStyle(.secondary)

            HStack {
                TextField("Preset name", text: $name)
                Button("Capture current Dock") { capturePreset() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.state.dockPresets.isEmpty {
                Text("No Dock presets yet.").foregroundStyle(.secondary)
            } else {
                Picker("Preset", selection: $selectedID) {
                    Text("Choose a preset").tag(nil as UUID?)
                    ForEach(model.state.dockPresets) { preset in
                        Text(preset.name).tag(preset.id as UUID?)
                    }
                }
            }

            if let selected, let current {
                let changes = selected.snapshot.changes(from: current)
                GroupBox("Preview: \(selected.name)") {
                    VStack(alignment: .leading, spacing: 8) {
                        if changes.isEmpty {
                            Text("This preset matches the current Dock.")
                        } else {
                            ForEach(changes, id: \.rawValue) { key in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key.label).bold()
                                    Text("Current: \(current.displayValue(for: key))")
                                    Text("Preset: \(selected.snapshot.displayValue(for: key))")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                Button("Apply preset…") { pendingApply = true }
                    .disabled(changes.isEmpty)
            }

            HStack {
                Button("Refresh preview") { refresh() }
                Button("Restore previous Dock…") { pendingRestore = true }
                    .disabled(!canRestore)
            }

            if let message {
                Text(message).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 350)
        .onAppear { refresh() }
        .confirmationDialog("Apply Dock preset?", isPresented: $pendingApply) {
            Button("Apply and restart Dock") { applySelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Snapboard will save the current Dock for restoration, then change this Mac's Dock.")
        }
        .confirmationDialog("Restore previous Dock?", isPresented: $pendingRestore) {
            Button("Restore and restart Dock") { restorePrevious() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace the current Dock settings with the snapshot saved before the last preset was applied.")
        }
    }

    private func refresh() {
        message = nil
        do {
            current = try DockPreferences.capture()
        } catch {
            current = nil
            message = error.localizedDescription
        }
        do {
            canRestore = try DockPreferences.hasRestorePoint()
        } catch {
            canRestore = false
            message = "Saved Dock restore point could not be read: \(error.localizedDescription)"
        }
    }

    private func capturePreset() {
        do {
            let snapshot = try DockPreferences.capture()
            let preset = DockPreset(name: name.trimmingCharacters(in: .whitespacesAndNewlines), snapshot: snapshot)
            var next = model.state
            next.dockPresets.append(preset)
            model.state = next
            selectedID = preset.id
            name = ""
            refresh()
        } catch { message = error.localizedDescription }
    }

    private func applySelected() {
        guard let selected else { return }
        do {
            let warning = try DockPreferences.apply(selected)
            refresh()
            message = warning ?? "Applied \(selected.name). The previous Dock can be restored here."
        } catch { message = error.localizedDescription; refreshPreviewWithoutClearingMessage() }
    }

    private func restorePrevious() {
        do {
            let warning = try DockPreferences.restore()
            refresh()
            message = warning ?? "Previous Dock restored."
        } catch { message = error.localizedDescription; refreshPreviewWithoutClearingMessage() }
    }

    private func refreshPreviewWithoutClearingMessage() {
        current = try? DockPreferences.capture()
        canRestore = (try? DockPreferences.hasRestorePoint()) ?? false
    }
}
