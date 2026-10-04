import AppKit
import SwiftUI
import SnapboardCore

/// Edit layout: a full-screen overlay showing that screen's zones. Click a zone to pick it,
/// drag a divider to resize, split or remove the picked zone, start from a preset, then Save.
final class LayoutEditorController {
    private var panel: NSPanel?

    func open(for screen: NSScreen) {
        close()
        let p = EditorPanel(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        let view = LayoutEditorView(screenName: screen.localizedName,
                                    start: AppModel.shared.layout(for: screen),
                                    onSave: { [weak self] layout in
                                        AppModel.shared.setLayout(layout, for: screen)
                                        self?.close()
                                    },
                                    onCancel: { [weak self] in self?.close() })
        p.contentView = NSHostingView(rootView: view)
        p.setFrame(screen.visibleFrame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// A borderless panel still needs to accept clicks and the Escape key.
private final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct LayoutEditorView: View {
    let screenName: String
    @State var layout: LayoutNode
    @State private var picked: Int?
    let onSave: (LayoutNode) -> Void
    let onCancel: () -> Void

    init(screenName: String, start: LayoutNode, onSave: @escaping (LayoutNode) -> Void, onCancel: @escaping () -> Void) {
        self.screenName = screenName
        _layout = State(initialValue: start)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.35)
                    .onTapGesture { picked = nil }

                ForEach(Array(layout.zones().enumerated()), id: \.offset) { i, z in
                    let r = scaled(z, size)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(picked == i ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(picked == i ? Color.accentColor : Color.white.opacity(0.7), lineWidth: picked == i ? 3 : 1.5))
                        .overlay(Text("\(i + 1)").font(.system(size: 28, weight: .semibold)).foregroundColor(.white.opacity(0.8)))
                        .frame(width: max(r.width - 12, 1), height: max(r.height - 12, 1))
                        .position(x: r.midX, y: r.midY)
                        .onTapGesture { picked = i }
                }

                ForEach(Array(layout.dividers().enumerated()), id: \.offset) { _, d in
                    let line = scaled(d.line, size)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: d.axis == .sideBySide ? 8 : max(line.width * 0.3, 40),
                               height: d.axis == .sideBySide ? max(line.height * 0.3, 40) : 8)
                        .position(x: line.midX, y: line.midY)
                        .gesture(DragGesture(coordinateSpace: .named("editor")).onChanged { g in
                            let unit = CGPoint(x: g.location.x / max(size.width, 1), y: g.location.y / max(size.height, 1))
                            layout = layout.settingRatio(LayoutNode.ratio(for: d, draggedTo: unit), at: d.path)
                        })
                        .onHover { inside in
                            if inside { (d.axis == .sideBySide ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
                            else { NSCursor.pop() }
                        }
                }

                toolbar
                    .position(x: size.width / 2, y: 60)
            }
            .coordinateSpace(name: "editor")
        }
        .onExitCommand(perform: onCancel)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(screenName).font(.headline)
            Menu("Start from…") {
                ForEach(Preset.allCases, id: \.self) { p in
                    Button(p.title) { layout = p.layout; picked = nil }
                }
            }
            .fixedSize()
            Divider().frame(height: 20)
            Button("Split side by side") { split(.sideBySide) }.disabled(picked == nil)
            Button("Split top / bottom") { split(.stacked) }.disabled(picked == nil)
            Button("Remove zone") {
                if let i = picked { layout = layout.removing(zone: i); picked = nil }
            }
            .disabled(picked == nil || layout.zoneCount < 2)
            Divider().frame(height: 20)
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            Button("Save") { onSave(layout) }.keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }

    private func split(_ axis: SplitAxis) {
        guard let i = picked else { return }
        layout = layout.splitting(zone: i, axis: axis)
        picked = nil
    }

    private func scaled(_ r: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
    }
}
