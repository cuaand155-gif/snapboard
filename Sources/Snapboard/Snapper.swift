import AppKit
import SnapboardCore

/// Hold Shift while dragging a window: the zones on that screen light up, the one under the
/// pointer is highlighted, and letting go snaps the window into it. Dragging without Shift is
/// left completely alone, and so is Shift-dragging that doesn't move a window (selecting text).
final class Snapper {
    private var monitors: [Any] = []
    private let overlay = ZoneOverlay()
    /// The front window when this drag began, and where it was, looked up once per drag.
    private var lookedUp = false
    private var window: AXUIElement?
    private var startOrigin: CGPoint?
    /// True once the window has really moved with Shift held.
    private var active = false
    private var target: (screen: NSScreen, zone: Int)?

    func start() {
        guard monitors.isEmpty else { return }
        let drag = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] e in self?.dragged(e) }
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in self?.released() }
        let flags = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] e in self?.flagsChanged(e) }
        monitors = [drag, up, flags].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        reset()
    }

    private func dragged(_ event: NSEvent) {
        guard AppModel.shared.state.snappingOn, WindowMover.isTrusted else { return }
        if !lookedUp {
            lookedUp = true
            window = WindowMover.frontWindow()
            startOrigin = window.flatMap { WindowMover.frame(of: $0) }?.origin
        }
        guard let w = window, let start = startOrigin else { return }
        guard event.modifierFlags.contains(.shift) else { deactivate(); return }
        if !active {
            guard let now = WindowMover.frame(of: w)?.origin, hypot(now.x - start.x, now.y - start.y) > 3 else { return }
            active = true
        }
        updateTarget()
    }

    private func flagsChanged(_ event: NSEvent) {
        // Letting go of Shift mid-drag hides the zones; pressing it again brings them back.
        if active && !event.modifierFlags.contains(.shift) { deactivate() }
    }

    private func updateTarget() {
        guard let screen = NSScreen.underMouse else { return }
        let layout = AppModel.shared.layout(for: screen)
        let unit = ScreenMath.unitPoint(forAppKit: NSEvent.mouseLocation, in: screen.visibleFrame)
        let zone = layout.zoneIndex(at: unit)
        target = zone.map { (screen, $0) }
        overlay.show(layout: layout, on: screen, highlighted: zone)
    }

    private func released() {
        defer { reset() }
        guard active, let window = window, let t = target else { return }
        let zones = AppModel.shared.layout(for: t.screen).zones()
        guard zones.indices.contains(t.zone) else { return }
        let frame = ScreenMath.appKitRect(forUnit: zones[t.zone], in: t.screen.visibleFrame)
        // Let the system finish its own drag first, then place the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { WindowMover.move(window, to: frame) }
    }

    private func deactivate() {
        active = false
        target = nil
        overlay.hide()
    }

    private func reset() {
        deactivate()
        lookedUp = false
        window = nil
        startOrigin = nil
    }
}

/// Places the window in front into a fixed share of its screen (keyboard shortcuts).
enum QuickSnap: CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximise

    var unitRect: CGRect {
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .maximise: return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    func apply() {
        guard WindowMover.isTrusted, let window = WindowMover.frontWindow(),
              let current = WindowMover.frame(of: window),
              let screen = WindowMover.screen(for: current) else { NSSound.beep(); return }
        WindowMover.move(window, to: ScreenMath.appKitRect(forUnit: unitRect, in: screen.visibleFrame))
    }
}
