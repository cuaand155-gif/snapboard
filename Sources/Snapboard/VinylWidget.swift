import AppKit
import Combine
import SwiftUI
import SnapboardCore

/// A photorealistic, animated desktop turntable widget inspired by Vinyl.
/// Features a spinning grooved record, dynamic album art, a physical moving tonearm,
/// interactive playback controls, and transparent/solid deck background modes.
struct VinylWidget: View {
    @ObservedObject var music: NowPlayingModel
    @State private var rotationAngle: Double = 0
    @State private var timer: Timer?
    @State private var deckStyle: DeckStyle = .matteDark

    enum DeckStyle: String, CaseIterable, Identifiable {
        case matteDark = "Matte Dark"
        case warmWood = "Walnut Wood"
        case transparent = "Transparent"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Turntable Platter Deck
                turntableDeck

                // Spinning Vinyl Platter
                turntablePlatter
                    .frame(width: 220, height: 220)
                    .offset(x: -24, y: 0)

                // Tonearm mechanism
                tonearm
                    .offset(x: 104, y: -8)
            }
            .frame(width: 290, height: 230)

            // Track info and playback controls
            bottomBar
        }
        .padding(14)
        .frame(width: 320, height: 320)
        .background(deckBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(deckStyle == .transparent ? 0.2 : 0.4), radius: 14, x: 0, y: 6)
        .onAppear {
            startRotationTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .contextMenu {
            Picker("Deck Style", selection: $deckStyle) {
                ForEach(DeckStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            Divider()
            Button("Previous Track") { music.previousTrack() }
            Button(music.isPlaying ? "Pause" : "Play") { music.playPause() }
            Button("Next Track") { music.nextTrack() }
        }
    }

    // MARK: - Deck Background

    @ViewBuilder
    private var deckBackground: some View {
        switch deckStyle {
        case .matteDark:
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        case .warmWood:
            LinearGradient(colors: [Color(red: 0.28, green: 0.16, blue: 0.10), Color(red: 0.18, green: 0.10, blue: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color(red: 0.45, green: 0.30, blue: 0.20).opacity(0.3), lineWidth: 1)
                )
        case .transparent:
            Color.clear
        }
    }

    private var turntableDeck: some View {
        ZStack {
            if deckStyle != .transparent {
                // Platter recess ring
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 2)
                    .background(Circle().fill(Color.black.opacity(0.35)))
                    .frame(width: 232, height: 232)
                    .offset(x: -24, y: 0)

                // Strobe dots indicator around rim
                Circle()
                    .strokeBorder(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
                    .frame(width: 228, height: 228)
                    .offset(x: -24, y: 0)

                // Power & 33 RPM badge
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(music.isPlaying ? Color.red : Color.gray.opacity(0.5))
                            .frame(width: 5, height: 5)
                            .shadow(color: music.isPlaying ? .red.opacity(0.8) : .clear, radius: 4)
                        Text("33 RPM")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .offset(x: -110, y: 92)
            }
        }
    }

    // MARK: - Vinyl Platter

    private var turntablePlatter: some View {
        ZStack {
            // Main heavy vinyl body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.08), Color(white: 0.03), Color(white: 0.05), Color.black],
                        center: .center,
                        startRadius: 20,
                        endRadius: 110
                    )
                )

            // Micro-grooves concentric rings
            ForEach([35, 45, 55, 65, 75, 85, 95, 103], id: \.self) { r in
                Circle()
                    .strokeBorder(Color.white.opacity(0.035), lineWidth: 0.8)
                    .frame(width: CGFloat(r * 2), height: CGFloat(r * 2))
            }

            // Specular sheen light reflections (bowtie reflections)
            AngularGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear,
                    Color.white.opacity(0.08),
                    Color.clear,
                    Color.white.opacity(0.12),
                    Color.clear,
                    Color.white.opacity(0.08),
                    Color.clear
                ],
                center: .center
            )
            .blendMode(.screen)
            .clipShape(Circle())

            // Center album label
            centerLabel
                .frame(width: 76, height: 76)

            // Center spindle
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)

            Circle()
                .fill(Color.black)
                .frame(width: 4, height: 4)
        }
        .rotationEffect(.degrees(rotationAngle))
        .shadow(color: .black.opacity(0.5), radius: 10, x: 2, y: 4)
    }

    private var centerLabel: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.orange.opacity(0.85), Color.red.opacity(0.9)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            if let img = music.artworkImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(music.trackTitle.isEmpty ? "SNAPBOARD" : music.trackTitle.uppercased())
                        .font(.system(size: 6, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                }
            }

            // Outer ring of center label
            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Tonearm

    private var tonearm: some View {
        ZStack(alignment: .top) {
            // Tonearm pivot base
            Circle()
                .fill(
                    RadialGradient(colors: [Color(white: 0.45), Color(white: 0.25)],
                                   center: .center, startRadius: 0, endRadius: 16)
                )
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 4, x: 1, y: 2)

            // Arm rod with cartridge and needle
            ZStack(alignment: .top) {
                // Curved metallic arm
                Capsule()
                    .fill(
                        LinearGradient(colors: [Color(white: 0.8), Color(white: 0.45)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 4.5, height: 110)
                    .offset(y: 12)

                // Cartridge / headshell at tip
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.15))
                    .frame(width: 10, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .rotationEffect(.degrees(14))
                    .offset(x: -3, y: 118)
            }
            .rotationEffect(.degrees(music.isPlaying ? 22 : -8), anchor: .top)
            .animation(.spring(response: 0.8, dampingFraction: 0.7), value: music.isPlaying)
        }
    }

    // MARK: - Bottom Controls Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(music.trackTitle.isEmpty ? "No track playing" : music.trackTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(music.artist.isEmpty ? "Open Spotify or Music" : music.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Playback controls
            HStack(spacing: 10) {
                Button(action: { music.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)

                Button(action: { music.playPause() }) {
                    Image(systemName: music.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(music.isPlaying ? .orange : .white)
                }
                .buttonStyle(.plain)

                Button(action: { music.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Rotation Animation Loop

    private func startRotationTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [self] _ in
            if music.isPlaying {
                rotationAngle = (rotationAngle + 1.2).truncatingRemainder(dividingBy: 360)
            }
        }
    }
}
