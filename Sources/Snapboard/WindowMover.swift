import AppKit
import ApplicationServices
import SnapboardCore

/// Moving other apps' windows through the macOS Accessibility API. Needs the one-time
/// Accessibility permission (System Settings → Privacy & Security → Accessibility).
enum WindowMover {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's own "allow Snapboard" prompt once.
    static func askForPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The front window of the app in front, unless that app is Snapboard itself.
    static func frontWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value else { return nil }
        return (window as! AXUIElement)
    }

    /// The window's frame in AppKit coordinates.
    static func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return ScreenMath.appKitRect(forAccessibility: CGRect(origin: pos, size: size), mainScreenHeight: NSScreen.mainHeight)
    }

    /// Moves and resizes a window to `target` (AppKit coordinates). Position, then size, then
    /// position again, because some apps refuse a size that would push them off the screen.
    /// Apps with fixed-size windows keep their size and only move.
    static func move(_ window: AXUIElement, to target: CGRect) {
        let ax = ScreenMath.accessibilityRect(forAppKit: target, mainScreenHeight: NSScreen.mainHeight)
        var origin = ax.origin, size = ax.size
        guard let pos = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
    }

    /// The screen a window is mostly on.
    static func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        } ?? NSScreen.main
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
