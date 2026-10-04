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

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func start() {
        guard refs.isEmpty else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            if Hotkeys.bindings.indices.contains(index) {
                DispatchQueue.main.async { Hotkeys.bindings[index].action.apply() }
            }
            return noErr
        }, 1, &spec, nil, &handler)

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
}
