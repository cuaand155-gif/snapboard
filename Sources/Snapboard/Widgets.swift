import AppKit
import Combine
import SwiftUI
import SnapboardCore

enum WidgetKind: String, CaseIterable, Identifiable {
    case clock, lifeboard, weather, nowPlaying, vinyl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock and date"
        case .lifeboard: return "Lifeboard today"
        case .weather: return "Weather"
        case .nowPlaying: return "Now playing"
        case .vinyl: return "Vinyl turntable"
        }
    }

    var size: CGSize {
        switch self {
        case .clock: return CGSize(width: 200, height: 96)
        case .lifeboard: return CGSize(width: 288, height: 200)
        case .weather: return CGSize(width: 240, height: 80)
        case .nowPlaying: return CGSize(width: 288, height: 72)
        case .vinyl: return CGSize(width: 320, height: 320)
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
        updateMusic()
    }

    /// Now playing only checks the music apps while its widget is on the desktop.
    private func updateMusic() {
        if panels[.nowPlaying] != nil || panels[.vinyl] != nil { music.start() } else { music.stop() }
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
        updateMusic()
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
        updateMusic()
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

/// What Spotify or Apple Music is playing, checked every 3 seconds while Now Playing or
/// Vinyl turntable is shown. Supports title, artist, album, artwork, and playback controls.
final class NowPlayingModel: ObservableObject {
    @Published var line: String?
    @Published var trackTitle = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var artworkImage: NSImage?
    private var currentArtworkURL = ""
    private var activePlayerName: String?
    private var timer: Timer?

    private static let players: [(bundleID: String, name: String)] = [
        ("com.spotify.client", "Spotify"),
        ("com.apple.Music", "Music")
    ]
    private var scripts: [String: NSAppleScript] = [:]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.check() }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        line = nil
        isPlaying = false
        artworkImage = nil
        currentArtworkURL = ""
    }

    func playPause() {
        guard let app = activePlayerName else { return }
        let s = NSAppleScript(source: "tell application \"\(app)\" to playpause")
        s?.executeAndReturnError(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.check() }
    }

    func nextTrack() {
        guard let app = activePlayerName else { return }
        let s = NSAppleScript(source: "tell application \"\(app)\" to next track")
        s?.executeAndReturnError(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.check() }
    }

    func previousTrack() {
        guard let app = activePlayerName else { return }
        let s = NSAppleScript(source: "tell application \"\(app)\" to previous track")
        s?.executeAndReturnError(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.check() }
    }

    private func check() {
        for player in Self.players
        where !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty {
            if let out = script(for: player.name)?.executeAndReturnError(nil).stringValue, !out.isEmpty {
                let parts = out.components(separatedBy: "|||")
                if parts.count >= 4 {
                    let stateStr = parts[0]
                    let playing = stateStr.lowercased().contains("playing")
                    let song = parts[1]
                    let art = parts[2]
                    let alb = parts[3]
                    let artURL = parts.count > 4 ? parts[4] : ""

                    activePlayerName = player.name
                    isPlaying = playing
                    trackTitle = song
                    artist = art
                    album = alb
                    line = song.isEmpty ? nil : "\(song) — \(art)"

                    if !artURL.isEmpty && artURL != currentArtworkURL {
                        currentArtworkURL = artURL
                        fetchArtwork(from: artURL)
                    } else if artURL.isEmpty && artworkImage == nil && !song.isEmpty {
                        // For Music app, extract artwork asynchronously
                        fetchMusicAppArtwork()
                    }
                    return
                }
            }
        }
        activePlayerName = nil
        line = nil
        isPlaying = false
    }

    private func fetchArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artworkImage = img }
        }.resume()
    }

    private func fetchMusicAppArtwork() {
        guard activePlayerName == "Music" else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = NSAppleScript(source: """
            tell application "Music"
                try
                    if (count of artworks of current track) > 0 then
                        return data of artwork 1 of current track
                    end if
                end try
                return ""
            end tell
            """)
            if let dataDesc = script?.executeAndReturnError(nil).data {
                if let img = NSImage(data: dataDesc) {
                    DispatchQueue.main.async { self?.artworkImage = img }
                }
            }
        }
    }

    private func script(for app: String) -> NSAppleScript? {
        if let s = scripts[app] { return s }
        let source: String
        if app == "Spotify" {
            source = """
            tell application "Spotify"
                try
                    set st to player state as string
                    set nm to name of current track
                    set ar to artist of current track
                    set al to album of current track
                    set art to ""
                    try
                        set art to artwork url of current track
                    end try
                    return st & "|||" & nm & "|||" & ar & "|||" & al & "|||" & art
                end try
                return ""
            end tell
            """
        } else {
            source = """
            tell application "Music"
                try
                    set st to player state as string
                    set nm to name of current track
                    set ar to artist of current track
                    set al to album of current track
                    return st & "|||" & nm & "|||" & ar & "|||" & al & "|||"
                end try
                return ""
            end tell
            """
        }
        let s = NSAppleScript(source: source)
        scripts[app] = s
        return s
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
                Button("Open Lifeboard") { _ = AppModel.shared.openLifeboard() }
                Button("Remove widget", action: onRemove)
            }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .clock: ClockWidget()
        case .lifeboard: LifeboardWidget(feed: feed)
        case .weather: WeatherWidget(feed: feed)
        case .nowPlaying: NowPlayingWidget(music: music)
        case .vinyl: VinylWidget(music: music)
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
            HStack {
                Text(FeedText.tasksHeadline(feed.feed?.tasks)).font(.headline)
                Spacer()
                Button { _ = AppModel.shared.openLifeboard() } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain)
                    .help("Open Lifeboard")
            }
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
