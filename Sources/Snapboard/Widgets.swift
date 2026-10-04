import AppKit
import SwiftUI
import SnapboardCore

enum WidgetKind: String, CaseIterable, Identifiable {
    case clock, lifeboard, weather, nowPlaying

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock and date"
        case .lifeboard: return "Lifeboard today"
        case .weather: return "Weather"
        case .nowPlaying: return "Now playing"
        }
    }

    var size: CGSize {
        switch self {
        case .clock: return CGSize(width: 200, height: 96)
        case .lifeboard: return CGSize(width: 288, height: 200)
        case .weather: return CGSize(width: 240, height: 80)
        case .nowPlaying: return CGSize(width: 288, height: 72)
        }
    }
}

/// Shows, hides and remembers the desktop widgets. Widgets sit on the desktop, under normal
/// windows; window zones ignore them. Dropping one lines it up on the widget grid unless the
/// grid is turned off in Settings.
final class WidgetManager: NSObject, NSWindowDelegate {
    private var panels: [WidgetKind: NSPanel] = [:]
    private var settle: [WidgetKind: DispatchWorkItem] = [:]
    let feed = FeedModel()
    let music = NowPlayingModel()

    func start() {
        for kind in WidgetKind.allCases where AppModel.shared.state.widgets[kind.rawValue] != nil { show(kind) }
        feed.start()
        music.start()
    }

    func isShown(_ kind: WidgetKind) -> Bool { panels[kind] != nil }

    func toggle(_ kind: WidgetKind) { isShown(kind) ? remove(kind) : add(kind) }

    func add(_ kind: WidgetKind) {
        guard panels[kind] == nil, let screen = NSScreen.main else { return }
        // A new widget starts near the top-left of the main screen, then lines up on the grid.
        let area = screen.visibleFrame
        let start = CGRect(x: area.minX + 24, y: area.maxY - 24 - kind.size.height, width: kind.size.width, height: kind.size.height)
        AppModel.shared.state.widgets[kind.rawValue] = CodableRect(WidgetGrid().snap(start, in: area))
        show(kind)
    }

    func remove(_ kind: WidgetKind) {
        panels[kind]?.orderOut(nil)
        panels[kind] = nil
        AppModel.shared.state.widgets[kind.rawValue] = nil
    }

    /// After screens change (a monitor unplugged), pull any widget that is now off-screen back on.
    func screensChanged() {
        for (kind, panel) in panels {
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
            if !onScreen, let main = NSScreen.main {
                let fixed = ScreenMath.clamp(panel.frame, into: main.visibleFrame)
                panel.setFrame(fixed, display: true)
                AppModel.shared.state.widgets[kind.rawValue] = CodableRect(fixed)
            }
        }
    }

    private func show(_ kind: WidgetKind) {
        guard let saved = AppModel.shared.state.widgets[kind.rawValue]?.rect else { return }
        let p = NSPanel(contentRect: saved, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: WidgetShell(kind: kind, feed: feed, music: music,
                                                            onRemove: { [weak self] in self?.remove(kind) }))
        p.setFrame(saved, display: true)
        p.orderFrontRegardless()
        panels[kind] = p
    }

    // Lines a widget up once the mouse is let go, not while it is still being dragged.
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let kind = panels.first(where: { $0.value === panel })?.key else { return }
        settle[kind]?.cancel()
        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self = self, let panel = panel else { return }
            if NSEvent.pressedMouseButtons != 0 { self.windowDidMove(notification); return }
            var frame = panel.frame
            if AppModel.shared.state.widgetGridOn, let screen = panel.screen ?? NSScreen.main {
                let snapped = WidgetGrid().snap(frame, in: screen.visibleFrame)
                if snapped != frame { panel.setFrame(snapped, display: true, animate: true) }
                frame = snapped
            }
            AppModel.shared.state.widgets[kind.rawValue] = CodableRect(frame)
        }
        settle[kind] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

// MARK: - Data

/// Reads Lifeboard's widget feed every 5 minutes. Read only.
final class FeedModel: ObservableObject {
    @Published var feed: Feed?
    @Published var problem: String?
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        Self.fetch { [weak self] result in
            switch result {
            case let .success(feed): self?.feed = feed; self?.problem = nil
            case let .failure(err): self?.problem = err.message
            }
        }
    }

    struct FetchError: Error { let message: String }

    /// Also used by Settings' "Test connection".
    static func fetch(_ done: @escaping (Result<Feed, FetchError>) -> Void) {
        let finish = { (r: Result<Feed, FetchError>) in DispatchQueue.main.async { done(r) } }
        guard let url = feedURL(from: AppModel.shared.state.lifeboardURL) else {
            return finish(.failure(FetchError(message: "Add your Lifeboard address in Settings")))
        }
        guard let token = Keychain.token(), !token.isEmpty else {
            return finish(.failure(FetchError(message: "Add your widget token in Settings")))
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, _, error in
            if error != nil { return finish(.failure(FetchError(message: "Offline: showing the last update"))) }
            guard let data = data, let feed = try? Feed.decode(data) else {
                return finish(.failure(FetchError(message: "Lifeboard sent something unexpected")))
            }
            finish(feed.ok ? .success(feed) : .failure(FetchError(message: feed.error ?? "Lifeboard said no")))
        }.resume()
    }
}

/// What Spotify or Apple Music is playing, checked every 5 seconds. macOS asks once for
/// permission to talk to those apps; neither is ever opened by this.
final class NowPlayingModel: ObservableObject {
    @Published var line: String?
    private var timer: Timer?

    private static let script = NSAppleScript(source: """
    if application "Spotify" is running then
        tell application "Spotify"
            if player state is playing then return (name of current track) & " — " & (artist of current track)
        end tell
    end if
    if application "Music" is running then
        tell application "Music"
            if player state is playing then return (name of current track) & " — " & (artist of current track)
        end tell
    end if
    return ""
    """)

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        check()
    }

    private func check() {
        var err: NSDictionary?
        let out = Self.script?.executeAndReturnError(&err).stringValue ?? ""
        line = out.isEmpty ? nil : out
    }
}

// MARK: - Views

struct WidgetShell: View {
    let kind: WidgetKind
    @ObservedObject var feed: FeedModel
    @ObservedObject var music: NowPlayingModel
    let onRemove: () -> Void

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .contextMenu {
                if kind == .lifeboard || kind == .weather { Button("Refresh now") { feed.refresh() } }
                Button("Remove widget", action: onRemove)
            }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .clock: ClockWidget()
        case .lifeboard: LifeboardWidget(feed: feed)
        case .weather: WeatherWidget(feed: feed)
        case .nowPlaying: NowPlayingWidget(music: music)
        }
    }
}

struct ClockWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(ctx.date, format: .dateTime.weekday(.wide).month(.wide).day()).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct LifeboardWidget: View {
    @ObservedObject var feed: FeedModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FeedText.tasksHeadline(feed.feed?.tasks)).font(.headline)
            ForEach(feed.feed?.tasks?.items.prefix(4).map { $0 } ?? []) { t in
                Text("\(t.doing ? "▸" : "•") \(t.title)").font(.callout).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(FeedText.medsLine(feed.feed?.meds)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let p = feed.problem { Text(p).font(.caption2).foregroundStyle(.orange) }
        }
    }
}

struct WeatherWidget: View {
    @ObservedObject var feed: FeedModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FeedText.weatherLine(feed.feed?.weather)).font(.headline).lineLimit(2)
            if let p = feed.problem { Text(p).font(.caption2).foregroundStyle(.orange) }
        }
    }
}

struct NowPlayingWidget: View {
    @ObservedObject var music: NowPlayingModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note").font(.title2)
            Text(music.line ?? "Nothing playing").font(.callout).lineLimit(2)
        }
    }
}
