import AppKit
import Carbon.HIToolbox

/// Control-Option + arrow keys / Return snap the window in front without the mouse.
/// They can be switched off in Settings. (Changing which keys are used comes later.)
final class Hotkeys {
    static let bindings: [(key: Int, action: QuickSnap, label: String)] = [
        (kVK_LeftArrow, .leftHalf, "⌃⌥←  Left half"),
        (kVK_RightArrow, .rightHalf, "⌃⌥→  Right half"),
        (kVK_UpArrow, .topHalf, "⌃⌥↑  Top half"),
        (kVK_DownArrow, .bottomHalf, "⌃⌥↓  Bottom half"),
        (kVK_Return, .maximise, "⌃⌥↩  Fill the screen")
    ]

    var onPermissionNeeded: (() -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var lastPermissionPromptAt: Date = .distantPast
    private let permissionPromptCooldown: TimeInterval = 10

    deinit { stop() }

    func start() {
        guard refs.isEmpty else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == OSType(0x534E_4150) else { return OSStatus(eventNotHandledErr) }
            let index = Int(id.id)
            guard Hotkeys.bindings.indices.contains(index), let userData else { return noErr }
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotkeys.handleHotkey(at: index) }
            return noErr
        }, 1, &spec, userData, &handler)

        let mods = UInt32(controlKey | optionKey)
        for (i, b) in Hotkeys.bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x534E_4150), id: UInt32(i))   // "SNAP"
            if RegisterEventHotKey(UInt32(b.key), mods, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref = ref {
                refs.append(ref)
            }
        }
    }

    func stop() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        if let h = handler { RemoveEventHandler(h); handler = nil }
    }

    private func handleHotkey(at index: Int) {
        guard WindowMover.isTrusted else {
            notifyPermissionNeededIfReady()
            return
        }
        Hotkeys.bindings[index].action.apply()
    }

    private func notifyPermissionNeededIfReady() {
        let now = Date()
        guard now.timeIntervalSince(lastPermissionPromptAt) >= permissionPromptCooldown else { return }
        lastPermissionPromptAt = now
        onPermissionNeeded?()
    }
}
