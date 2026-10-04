import AppKit
import SnapboardCore

/// A see-through layer over one screen that draws the zones while a window is being dragged.
/// It never takes clicks, so the drag underneath carries on normally.
final class ZoneOverlay {
    private var panel: NSPanel?
    private let view = ZonesView()

    func show(layout: LayoutNode, on screen: NSScreen, highlighted: Int?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.frame != screen.visibleFrame { panel.setFrame(screen.visibleFrame, display: false) }
        view.zones = layout.zones()
        view.highlighted = highlighted
        view.needsDisplay = true
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.contentView = view
        return p
    }
}

/// Draws unit-space zones scaled to its own bounds.
final class ZonesView: NSView {
    var zones: [CGRect] = []
    var highlighted: Int?

    override var isFlipped: Bool { true }   // y down, like unit space

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for (i, z) in zones.enumerated() {
            let r = CGRect(x: z.minX * bounds.width, y: z.minY * bounds.height,
                           width: z.width * bounds.width, height: z.height * bounds.height).insetBy(dx: 6, dy: 6)
            let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
            (i == highlighted ? accent.withAlphaComponent(0.35) : NSColor.black.withAlphaComponent(0.12)).setFill()
            path.fill()
            (i == highlighted ? accent : NSColor.white.withAlphaComponent(0.6)).setStroke()
            path.lineWidth = i == highlighted ? 3 : 1.5
            path.stroke()
        }
    }
}
