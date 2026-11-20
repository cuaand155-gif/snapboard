import AppKit
import Combine
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Represents a stashed file or text item in the Drop Shelf (inspired by Droppy).
public struct DropShelfItem: Identifiable, Equatable {
    public let id: UUID
    public let url: URL?
    public let text: String?
    public let title: String
    public let addedAt: Date
    public let icon: NSImage?

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.text = nil
        self.title = url.lastPathComponent
        self.addedAt = Date()
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
    }

    public init(text: String) {
        self.id = UUID()
        self.url = nil
        self.text = text
        self.title = text.prefix(30).replacingOccurrences(of: "\n", with: " ") + (text.count > 30 ? "…" : "")
        self.addedAt = Date()
        self.icon = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: "Text snippet")
    }

    public var isImage: Bool {
        guard let ext = url?.pathExtension.lowercased() else { return false }
        return ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff"].contains(ext)
    }

    public var isPDF: Bool {
        url?.pathExtension.lowercased() == "pdf"
    }
}

/// Observable state manager for the Drop Shelf.
public final class DropShelfModel: ObservableObject {
    public static let shared = DropShelfModel()

    @Published public var items: [DropShelfItem] = []
    @Published public var statusMessage: String?

    private init() {}

    public func addFiles(_ urls: [URL]) {
        for url in urls {
            if !items.contains(where: { $0.url?.path == url.path }) {
                items.append(DropShelfItem(url: url))
            }
        }
    }

    public func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(DropShelfItem(text: trimmed))
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func clearAll() {
        items.removeAll()
        statusMessage = nil
    }

    // MARK: - Quick Actions

    public func openItem(_ item: DropShelfItem) {
        if let url = item.url {
            NSWorkspace.shared.open(url)
        } else if let text = item.text {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            statusMessage = "Copied text to clipboard"
        }
    }

    public func revealInFinder(_ item: DropShelfItem) {
        if let url = item.url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    public func copyPath(_ item: DropShelfItem) {
        if let path = item.url?.path {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            statusMessage = "Copied path to clipboard"
        }
    }

    /// Combines all image and PDF items into one merged PDF.
    public func combineAllIntoPDF() {
        let targetURLs = items.compactMap(\.url).filter { itemURL in
            let ext = itemURL.pathExtension.lowercased()
            return ["pdf", "png", "jpg", "jpeg", "heic", "webp"].contains(ext)
        }
        guard !targetURLs.isEmpty else {
            statusMessage = "No images or PDFs to merge."
            return
        }

        let doc = PDFDocument()
        var pageIndex = 0

        for url in targetURLs {
            if url.pathExtension.lowercased() == "pdf", let sourceDoc = PDFDocument(url: url) {
                for i in 0..<sourceDoc.pageCount {
                    if let page = sourceDoc.page(at: i) {
                        doc.insert(page, at: pageIndex)
                        pageIndex += 1
                    }
                }
            } else if let img = NSImage(contentsOf: url), let page = PDFPage(image: img) {
                doc.insert(page, at: pageIndex)
                pageIndex += 1
            }
        }

        let outDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dest = outDir.appendingPathComponent("Combined_\(Int(Date().timeIntervalSince1970)).pdf")

        if doc.write(to: dest) {
            statusMessage = "Saved PDF to Downloads: \(dest.lastPathComponent)"
            items.append(DropShelfItem(url: dest))
        } else {
            statusMessage = "Failed to create merged PDF."
        }
    }

    /// Converts an image to PNG.
    public func convertImageToPNG(_ item: DropShelfItem) {
        guard let url = item.url, let image = NSImage(contentsOf: url) else { return }
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let newURL = url.deletingPathExtension().appendingPathExtension("png")
        do {
            try pngData.write(to: newURL)
            statusMessage = "Converted to PNG: \(newURL.lastPathComponent)"
            items.append(DropShelfItem(url: newURL))
        } catch {
            statusMessage = "Could not convert image: \(error.localizedDescription)"
        }
    }
}

/// A floating, notch-docked shelf window controller (inspired by Droppy).
public final class DropShelfController: NSObject, NSWindowDelegate {
    public static let shared = DropShelfController()

    private var panel: NSPanel?
    private let model = DropShelfModel.shared

    private override init() {
        super.init()
    }

    public var isVisible: Bool {
        panel?.isVisible ?? false
    }

    public func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    public func open() {
        if panel == nil {
            setupPanel()
        }
        // Opens on the screen the pointer is on, so it appears where the user is working.
        guard let p = panel, let screen = NSScreen.underMouse else { return }

        // Position under notch/top edge of that screen
        let width: CGFloat = 460
        let height: CGFloat = 200
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - (width / 2)
        let y = screenFrame.maxY - height - 8

        p.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        p.orderFrontRegardless()
    }

    public func close() {
        panel?.orderOut(nil)
    }

    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.delegate = self

        let view = DropShelfView(model: model, onClose: { [weak self] in
            self?.close()
        })
        p.contentView = NSHostingView(rootView: view)
        self.panel = p
    }
}

/// SwiftUI View rendering the Drop Shelf hub.
public struct DropShelfView: View {
    @ObservedObject var model: DropShelfModel
    let onClose: () -> Void
    @State private var isTargeted = false

    public var body: some View {
        VStack(spacing: 8) {
            // Header bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tray.fill")
                        .foregroundStyle(.orange)
                    Text("Drop Shelf")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    if !model.items.isEmpty {
                        Text("\(model.items.count)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.3)))
                    }
                }

                Spacer()

                if !model.items.isEmpty {
                    Button(action: { model.combineAllIntoPDF() }) {
                        Label("Make PDF", systemImage: "doc.on.doc.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.12)))

                    Button(action: { model.clearAll() }) {
                        Text("Clear")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Drop zone / items container
            if model.items.isEmpty {
                emptyDropTarget
            } else {
                itemsScrollArea
            }

            // Status notice if any
            if let msg = model.statusMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 460, height: 190)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isTargeted ? Color.orange : Color.white.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
        .onDrop(of: [.fileURL, .text], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private var emptyDropTarget: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 26))
                .foregroundStyle(isTargeted ? .orange : .secondary)

            Text(isTargeted ? "Drop files to stash!" : "Drop files, photos, or text here to stash across spaces")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(isTargeted ? Color.orange.opacity(0.8) : Color.white.opacity(0.12))
        )
    }

    private var itemsScrollArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.items) { item in
                    DropShelfCard(item: item, onRemove: {
                        model.remove(id: item.id)
                    }, onOpen: {
                        model.openItem(item)
                    })
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                        DispatchQueue.main.async { model.addFiles([url]) }
                    } else if let url = data as? URL {
                        DispatchQueue.main.async { model.addFiles([url]) }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                // Plain-text drops arrive as raw bytes (Data) as often as a String, so accept both.
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    let text = (data as? String) ?? (data as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    if let text, !text.isEmpty {
                        DispatchQueue.main.async { model.addText(text) }
                    }
                }
            }
        }
    }
}

/// Card representing a stashed file or text snippet with drag-out capability.
struct DropShelfCard: View {
    let item: DropShelfItem
    let onRemove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8), .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }

            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(width: 76)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        )
        .onTapGesture(count: 2, perform: onOpen)
        .onDrag {
            if let url = item.url {
                return NSItemProvider(object: url as NSURL)
            } else if let text = item.text {
                return NSItemProvider(object: text as NSString)
            }
            return NSItemProvider()
        }
        .contextMenu {
            Button("Open", action: onOpen)
            if item.url != nil {
                Button("Reveal in Finder") { DropShelfModel.shared.revealInFinder(item) }
                Button("Copy File Path") { DropShelfModel.shared.copyPath(item) }
                if item.isImage {
                    Button("Convert to PNG") { DropShelfModel.shared.convertImageToPNG(item) }
                }
            }
            Divider()
            Button("Remove from Shelf", action: onRemove)
        }
    }
}
