import AppKit
import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// A user-initiated screen or window recording. The capture continues when this window
/// is behind another app; its red indicator and Stop button remain in the menu bar app.
final class RecordingWindowController {
    static let shared = RecordingWindowController()

    private let recorder = ScreenRecorder()
    private var window: NSWindow?

    private init() {}

    func open() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Record screen · Snapboard"
        window.contentView = NSHostingView(rootView: RecordingView(recorder: recorder))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        recorder.refreshSources()
    }

    /// Suitable for the app's menu label, so recording remains visible when the window closes.
    var isRecording: Bool { recorder.isRecording }
    var isBusy: Bool { recorder.isBusy }
    var hasPendingExport: Bool { recorder.hasPendingExport }

    func stop() { recorder.stop() }
}

private struct RecordingSource: Identifiable {
    let id: String
    let title: String
    let display: SCDisplay?
    let window: SCWindow?

    var size: CGSize {
        if let display { return CGSize(width: display.width, height: display.height) }
        return window?.frame.size ?? .zero
    }
}

private enum RecordingAudio: String, CaseIterable, Identifiable {
    case none = "None"
    case system = "System audio"
    case microphone = "Microphone"
    var id: String { rawValue }
}

private final class ScreenRecorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate,
                                    AVCaptureVideoDataOutputSampleBufferDelegate,
                                    AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published private(set) var sources: [RecordingSource] = []
    @Published var selectedSourceID: String?
    @Published var includeCursor = true
    @Published var audioSource: RecordingAudio = .none
    @Published var includeWebcam = false
    @Published var zoom = 1.0
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Choose a display or window, then start recording."
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var lastExport: URL?
    @Published private(set) var hasPendingExport = false
    @Published private(set) var recordedDuration: TimeInterval = 0
    @Published var trimStart: TimeInterval = 0
    @Published var trimEnd: TimeInterval = 0

    private var stream: SCStream?
    private var cameraSession: AVCaptureSession?
    private var cameraOutput: AVCaptureVideoDataOutput?
    private var microphoneOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "com.alexi.snapboard.recording.camera")
    private var timer: Timer?
    private var startDate: Date?
    private var outputURL: URL?

    // ScreenCaptureKit invokes output callbacks off the main queue. Both media types use one
    // serial queue because AVAssetWriter's session and inputs must be updated in order.
    private let sampleQueue = DispatchQueue(label: "com.alexi.snapboard.recording.samples")
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var firstTimestamp: CMTime?
    private var cameraFrame: CVPixelBuffer?
    private let imageContext = CIContext()

    func refreshSources() {
        guard !isRecording && !isBusy else { return }
        status = "Finding displays and windows…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let displays = content.displays.map { display in
                    RecordingSource(id: "display:\(display.displayID)",
                                    title: "Display \(display.displayID) · \(display.width) × \(display.height)",
                                    display: display, window: nil)
                }
                let windows = content.windows
                    .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier &&
                              !($0.title ?? "").isEmpty && $0.frame.width >= 100 && $0.frame.height >= 70 }
                    .map { window in
                        let app = window.owningApplication?.applicationName ?? "App"
                        return RecordingSource(id: "window:\(window.windowID)",
                                               title: "\(app) — \(window.title ?? "Window")",
                                               display: nil, window: window)
                    }
                self.sources = displays + windows
                if !self.sources.contains(where: { $0.id == self.selectedSourceID }) {
                    self.selectedSourceID = nil
                }
                self.status = self.sources.isEmpty ? "No recordable displays or windows were found." :
                    "Choose a display or window, then start recording."
            } catch {
                self.status = "Could not list screens. Allow Screen Recording in System Settings, then refresh. \(error.localizedDescription)"
            }
        }
    }

    @MainActor func start() {
        guard !isRecording && !isBusy && !hasPendingExport,
              let source = sources.first(where: { $0.id == selectedSourceID }) else { return }
        isBusy = true
        status = "Starting recording…"
        lastExport = nil
        recordedDuration = 0
        trimStart = 0
        trimEnd = 0
        Task { @MainActor [weak self] in
            await self?.begin(source: source)
        }
    }

    @MainActor private func begin(source: RecordingSource) async {
        do {
            let filter: SCContentFilter
            if let display = source.display {
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else if let window = source.window {
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else {
                throw RecordingError.invalidSource
            }

            let configuration = SCStreamConfiguration()
            let scale = source.display.flatMap { display in
                NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID })?.backingScaleFactor
            } ?? NSScreen.main?.backingScaleFactor ?? 2
            let width = max(2, Int(source.size.width * scale) & ~1)
            let height = max(2, Int(source.size.height * scale) & ~1)
            configuration.width = width
            configuration.height = height
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 5
            configuration.showsCursor = includeCursor
            configuration.capturesAudio = audioSource == .system
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            if zoom > 1 {
                let cropWidth = source.size.width / zoom
                let cropHeight = source.size.height / zoom
                configuration.sourceRect = CGRect(x: (source.size.width - cropWidth) / 2,
                                                  y: (source.size.height - cropHeight) / 2,
                                                  width: cropWidth, height: cropHeight)
                configuration.scalesToFit = true
            }

            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("snapboard-\(UUID().uuidString)")
                .appendingPathExtension("mov")
            let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ])
            video.expectsMediaDataInRealTime = true
            guard writer.canAdd(video) else { throw RecordingError.writerSetup }
            writer.add(video)
            let adaptor: AVAssetWriterInputPixelBufferAdaptor? = includeWebcam ?
                AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video,
                    sourcePixelBufferAttributes: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                        kCVPixelBufferWidthKey as String: width,
                        kCVPixelBufferHeightKey as String: height
                    ]) : nil
            var audio: AVAssetWriterInput?
            if audioSource != .none {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ])
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw RecordingError.writerSetup }
                writer.add(input)
                audio = input
            }

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if audioSource == .system {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            if includeWebcam || audioSource == .microphone {
                try await prepareCameraSession(webcam: includeWebcam, microphone: audioSource == .microphone)
            }
            self.writer = writer
            videoInput = video
            videoAdaptor = adaptor
            audioInput = audio
            firstTimestamp = nil
            outputURL = destination
            self.stream = stream
            if let cameraSession {
                await withCheckedContinuation { continuation in
                    captureQueue.async {
                        cameraSession.startRunning()
                        continuation.resume()
                    }
                }
                guard cameraSession.isRunning else { throw RecordingError.deviceStart }
            }
            try await stream.startCapture()
            isBusy = false
            isRecording = true
            startDate = Date()
            elapsed = 0
            status = "Recording in progress. Stop to export a movie."
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let startDate = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(startDate)
            }
        } catch {
            stream = nil
            if let cameraSession {
                captureQueue.async { cameraSession.stopRunning() }
            }
            cameraSession = nil
            cameraOutput = nil
            microphoneOutput = nil
            sampleQueue.async { [weak self] in
                self?.writer = nil
                self?.videoInput = nil
                self?.videoAdaptor = nil
                self?.audioInput = nil
                self?.firstTimestamp = nil
                self?.cameraFrame = nil
            }
            if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
            outputURL = nil
            isBusy = false
            status = "Recording could not start: \(error.localizedDescription)"
        }
    }

    @MainActor private func prepareCameraSession(webcam: Bool, microphone: Bool) async throws {
        if webcam {
            guard await isAuthorized(for: .video) else { throw RecordingError.cameraPermission }
        }
        if microphone {
            guard await isAuthorized(for: .audio) else { throw RecordingError.microphonePermission }
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if webcam {
            guard let device = AVCaptureDevice.default(for: .video) else { throw RecordingError.noCamera }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw RecordingError.deviceStart }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            output.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(output) else { throw RecordingError.deviceStart }
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: sampleQueue)
            cameraOutput = output
        }
        if microphone {
            guard let device = AVCaptureDevice.default(for: .audio) else { throw RecordingError.noMicrophone }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw RecordingError.deviceStart }
            session.addInput(input)
            let output = AVCaptureAudioDataOutput()
            guard session.canAddOutput(output) else { throw RecordingError.deviceStart }
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: sampleQueue)
            microphoneOutput = output
        }
        cameraSession = session
    }

    @MainActor private func isAuthorized(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording && !self.isBusy, let stream = self.stream else { return }
            self.isBusy = true
            self.status = "Finishing recording…"
            self.timer?.invalidate()
            self.timer = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await stream.stopCapture() }
                catch { self.status = "Capture stopped with an error: \(error.localizedDescription). Finishing available video…" }
                self.stream = nil
                self.isRecording = false
                if let cameraSession = self.cameraSession {
                    self.captureQueue.async { [weak self] in
                        cameraSession.stopRunning()
                        self?.sampleQueue.async { [weak self] in self?.finishWriter() }
                    }
                } else {
                    self.sampleQueue.async { [weak self] in self?.finishWriter() }
                }
                self.cameraSession = nil
            }
        }
    }

    private func finishWriter() {
        guard let writer, let outputURL else { return }
        guard writer.status == .writing else {
            DispatchQueue.main.async { [weak self] in
                self?.isBusy = false
                self?.writer = nil
                self?.videoInput = nil
                self?.videoAdaptor = nil
                self?.audioInput = nil
                self?.firstTimestamp = nil
                self?.cameraFrame = nil
                self?.cameraOutput = nil
                self?.microphoneOutput = nil
                self?.outputURL = nil
                try? FileManager.default.removeItem(at: outputURL)
                self?.status = "No video frames were captured. Try recording again."
            }
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                self.startDate = nil
                self.writer = nil
                self.videoInput = nil
                self.videoAdaptor = nil
                self.audioInput = nil
                self.firstTimestamp = nil
                self.cameraFrame = nil
                self.cameraOutput = nil
                self.microphoneOutput = nil
                if writer.status == .completed {
                    self.outputURL = outputURL
                    self.hasPendingExport = true
                    Task { @MainActor in
                        let durationTime = try? await AVURLAsset(url: outputURL).load(.duration)
                        let duration = durationTime?.seconds ?? self.elapsed
                        self.recordedDuration = max(0, duration.isFinite ? duration : self.elapsed)
                        self.trimStart = 0
                        self.trimEnd = self.recordedDuration
                        self.status = "Recording ready. Adjust the trim range, then export."
                    }
                } else {
                    self.outputURL = nil
                    try? FileManager.default.removeItem(at: outputURL)
                    self.status = "Recording could not finish: \(writer.error?.localizedDescription ?? "Unknown error")"
                }
            }
        }
    }

    @MainActor func export() {
        guard !isRecording && !isBusy, let outputURL else { return }
        let panel = NSSavePanel()
        panel.title = "Export Snapboard recording"
        panel.nameFieldStringValue = "Snapboard Recording.mov"
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isBusy = true
        status = "Exporting recording…"
        Task { @MainActor [weak self] in
            await self?.exportRecording(from: outputURL, to: destination)
        }
    }

    @MainActor func discard() {
        guard !isRecording && !isBusy && hasPendingExport, let outputURL else { return }
        let alert = NSAlert()
        alert.messageText = "Discard this recording?"
        alert.informativeText = "The unsaved movie will be removed."
        alert.addButton(withTitle: "Keep recording")
        alert.addButton(withTitle: "Discard")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            try FileManager.default.removeItem(at: outputURL)
            self.outputURL = nil
            hasPendingExport = false
            recordedDuration = 0
            trimStart = 0
            trimEnd = 0
            status = "Recording discarded."
        } catch {
            status = "Could not discard recording: \(error.localizedDescription)"
        }
    }

    @MainActor private func exportRecording(from original: URL, to destination: URL) async {
        var prepared: URL = original
        do {
            let start = max(0, min(trimStart, recordedDuration))
            let end = max(start, min(trimEnd, recordedDuration))
            if recordedDuration > 0.25 && (start > 0.01 || end < recordedDuration - 0.01) {
                guard end - start >= 0.25 else { throw RecordingError.trimTooShort }
                let asset = AVURLAsset(url: original)
                guard let exporter = AVAssetExportSession(asset: asset,
                                                          presetName: AVAssetExportPresetHighestQuality) else {
                    throw RecordingError.exportSetup
                }
                prepared = FileManager.default.temporaryDirectory
                    .appendingPathComponent("snapboard-trim-\(UUID().uuidString)")
                    .appendingPathExtension("mov")
                exporter.outputURL = prepared
                exporter.outputFileType = .mov
                exporter.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                                 duration: CMTime(seconds: end - start, preferredTimescale: 600))
                await withCheckedContinuation { continuation in
                    exporter.exportAsynchronously { continuation.resume() }
                }
                guard exporter.status == .completed else {
                    throw exporter.error ?? RecordingError.exportSetup
                }
            }

            // The save panel has already asked the user to confirm an overwrite.
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: prepared)
            } else {
                try FileManager.default.moveItem(at: prepared, to: destination)
            }
            if prepared != original { try? FileManager.default.removeItem(at: original) }
            outputURL = nil
            hasPendingExport = false
            lastExport = destination
            status = "Saved \(destination.lastPathComponent)."
        } catch {
            if prepared != original { try? FileManager.default.removeItem(at: prepared) }
            status = "Export failed: \(error.localizedDescription). The recording is still available here."
        }
        isBusy = false
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer else { return }
        if type == .screen && CMSampleBufferGetImageBuffer(sampleBuffer) == nil { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstTimestamp == nil {
            guard type == .screen, writer.startWriting() else { return }
            writer.startSession(atSourceTime: timestamp)
            firstTimestamp = timestamp
        }
        guard writer.status == .writing,
              let firstTimestamp, CMTimeCompare(timestamp, firstTimestamp) >= 0 else { return }
        switch type {
        case .screen:
            if let videoInput, videoInput.isReadyForMoreMediaData {
                if let videoAdaptor {
                    appendCompositedFrame(sampleBuffer, at: timestamp, using: videoAdaptor)
                } else {
                    _ = videoInput.append(sampleBuffer)
                }
            }
        case .audio:
            if let audioInput, audioInput.isReadyForMoreMediaData {
                _ = audioInput.append(sampleBuffer)
            }
        default: break
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === cameraOutput {
            cameraFrame = CMSampleBufferGetImageBuffer(sampleBuffer)
        } else if output === microphoneOutput, let audioInput,
                  let writer, writer.status == .writing,
                  let firstTimestamp, audioInput.isReadyForMoreMediaData,
                  CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), firstTimestamp) >= 0 {
            _ = audioInput.append(sampleBuffer)
        }
    }

    private func appendCompositedFrame(_ sampleBuffer: CMSampleBuffer, at timestamp: CMTime,
                                       using adaptor: AVAssetWriterInputPixelBufferAdaptor) {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let pool = adaptor.pixelBufferPool else { return }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess,
              let output else { return }
        let screen = CIImage(cvPixelBuffer: source)
        var image = screen
        if let cameraFrame {
            let webcam = CIImage(cvPixelBuffer: cameraFrame)
            if webcam.extent.width > 0 && webcam.extent.height > 0 {
                let targetWidth = screen.extent.width * 0.22
                let targetHeight = screen.extent.height * 0.32
                let scale = min(targetWidth / webcam.extent.width, targetHeight / webcam.extent.height)
                let scaled = webcam.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let margin = min(screen.extent.width, screen.extent.height) * 0.025
                let position = CGAffineTransform(translationX: screen.extent.maxX - scaled.extent.maxX - margin,
                                                 y: screen.extent.minY - scaled.extent.minY + margin)
                image = scaled.transformed(by: position).composited(over: screen)
            }
        }
        imageContext.render(image, to: output, bounds: screen.extent,
                            colorSpace: CGColorSpaceCreateDeviceRGB())
        _ = adaptor.append(output, withPresentationTime: timestamp)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.status = "Capture stopped: \(error.localizedDescription)"
            self?.stop()
        }
    }
}

private enum RecordingError: LocalizedError {
    case invalidSource, writerSetup, cameraPermission, microphonePermission,
         noCamera, noMicrophone, deviceStart, exportSetup, trimTooShort
    var errorDescription: String? {
        switch self {
        case .invalidSource: return "The selected display or window is no longer available. Refresh the list."
        case .writerSetup: return "The movie writer could not accept the capture format."
        case .cameraPermission: return "Camera access was denied. Enable it in System Settings to add a webcam overlay."
        case .microphonePermission: return "Microphone access was denied. Enable it in System Settings to record your voice."
        case .noCamera: return "No camera was found."
        case .noMicrophone: return "No microphone was found."
        case .deviceStart: return "The camera or microphone could not start."
        case .exportSetup: return "The trimmed movie could not be exported."
        case .trimTooShort: return "Keep at least a quarter second of video."
        }
    }
}

private struct RecordingView: View {
    @ObservedObject var recorder: ScreenRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Circle().fill(recorder.isRecording ? Color.red : Color.gray.opacity(0.5))
                    .frame(width: 12, height: 12)
                    .accessibilityLabel(recorder.isRecording ? "Recording active" : "Not recording")
                Text(recorder.isRecording ? "Recording · \(duration)" : "Screen recorder")
                    .font(.headline)
                Spacer()
            }
            Text("Record one display or app window. macOS may ask for Screen Recording access when you refresh sources or start.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Picker("Source", selection: $recorder.selectedSourceID) {
                    Text("Choose a source").tag(nil as String?)
                    ForEach(recorder.sources) { source in
                        Text(source.title).tag(source.id as String?)
                    }
                }
                .disabled(recorder.isRecording || recorder.isBusy)
                Button("Refresh") { recorder.refreshSources() }
                    .disabled(recorder.isRecording || recorder.isBusy)
            }

            Toggle("Show cursor", isOn: $recorder.includeCursor)
                .disabled(recorder.isRecording || recorder.isBusy)
            Picker("Audio", selection: $recorder.audioSource) {
                ForEach(RecordingAudio.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
                .disabled(recorder.isRecording || recorder.isBusy)
            Toggle("Add webcam in corner", isOn: $recorder.includeWebcam)
                .disabled(recorder.isRecording || recorder.isBusy)
            HStack {
                Text("Center zoom")
                Slider(value: $recorder.zoom, in: 1...2, step: 0.25)
                    .disabled(recorder.isRecording || recorder.isBusy)
                Text(String(format: "%.2f×", recorder.zoom)).monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            Text("Zoom crops around the center for the entire recording.")
                .font(.caption).foregroundStyle(.secondary)

            if recorder.hasPendingExport && recorder.recordedDuration > 0.5 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trim export · \(time(recorder.trimStart)) to \(time(recorder.trimEnd))")
                    Slider(value: $recorder.trimStart, in: 0...max(0.01, recorder.trimEnd - 0.25))
                    Slider(value: $recorder.trimEnd,
                           in: min(recorder.recordedDuration, recorder.trimStart + 0.25)...recorder.recordedDuration)
                }
                .disabled(recorder.isBusy)
            }

            Text(recorder.status).font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recordingStatus")
            Spacer(minLength: 0)
            HStack {
                if let export = recorder.lastExport {
                    Text(export.lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
                }
                Spacer()
                if recorder.hasPendingExport && !recorder.isRecording && !recorder.isBusy {
                    Button("Discard…") { recorder.discard() }
                    Button("Export…") { recorder.export() }
                }
                if recorder.isRecording {
                    Button("Stop recording") { recorder.stop() }
                        .keyboardShortcut(".", modifiers: [.command])
                        .tint(.red)
                } else {
                    Button(recorder.isBusy ? "Working…" : "Start recording") { recorder.start() }
                        .disabled(recorder.isBusy || recorder.hasPendingExport || recorder.selectedSourceID == nil)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 500)
    }

    private var duration: String {
        let value = Int(recorder.elapsed)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
