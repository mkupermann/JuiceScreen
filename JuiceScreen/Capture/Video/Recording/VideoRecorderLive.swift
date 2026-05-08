import AVFoundation
import AppKit
import CoreMedia
import Foundation
import os
import ScreenCaptureKit

@MainActor
public final class VideoRecorderLive: NSObject, VideoRecorder {

    // MARK: - Public state

    public private(set) var isRecording: Bool = false
    public var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    // MARK: - Dependencies

    private let permissions: PermissionsService
    private let cursorTracker = CursorTracker()
    private let clickTracker = ClickTracker()
    private let keystrokeTracker = KeystrokeTracker()
    private lazy var compositor = FrameCompositor(
        cursorTracker: cursorTracker,
        clickTracker: clickTracker,
        keystrokeTracker: keystrokeTracker
    )
    private let microphone = MicrophoneCapture()
    private let log = AppLog.logger(category: "VideoRecorderLive")

    // MARK: - Recording state

    private var stream: SCStream?
    private var writer: VideoFileWriter?
    private var streamOutput: StreamOutput?
    private var startedAt: Date?
    private var options: VideoRecordingOptions = .defaults
    private var screenOrigin: CGPoint = .zero
    private var outputURL: URL?
    private var captureMode: VideoRecordingMode = .fullScreen

    public init(permissions: PermissionsService) {
        self.permissions = permissions
    }

    // MARK: - VideoRecorder

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        guard !isRecording else { return }

        self.options = options
        self.outputURL = outputURL
        self.captureMode = mode

        // Permissions
        guard permissions.status(for: .screenRecording) == .granted else {
            throw VideoRecordingError.missingScreenRecordingPermission
        }
        if options.captureMicrophone {
            let mic = await permissions.request(.microphone)
            if mic != .granted { throw VideoRecordingError.missingMicrophonePermission }
        }
        if options.requiresInputMonitoring {
            let im = await permissions.request(.inputMonitoring)
            if im != .granted { throw VideoRecordingError.missingInputMonitoringPermission }
        }

        // SCDisplay + filter + region rect
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw VideoRecordingError.noDisplaysAvailable
        }

        // SCDisplay.width / .height are in pixels. SCStreamConfiguration.sourceRect
        // is in points. Mixing the two (the original code did) asks SC for a region
        // twice the size of the display on a Retina screen, so zero frames are
        // produced and the resulting MP4 is empty.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: Int32(options.targetFps))
        cfg.queueDepth = 6
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false   // we composite our own ring
        cfg.capturesAudio = options.captureSystemAudio

        switch mode {
        case .fullScreen:
            // No sourceRect → SC captures the entire display by default. Match
            // output pixel dimensions to the display's native pixel size.
            cfg.width = display.width
            cfg.height = display.height
            screenOrigin = .zero
        case .region(let r):
            // Region rects come from the picker in points (display-local).
            // Output at 2× for Retina sharpness; SC documents sourceRect as points.
            let pixelDensity = 2
            cfg.width = Int(r.width) * pixelDensity
            cfg.height = Int(r.height) * pixelDensity
            cfg.sourceRect = r
            screenOrigin = r.origin
        }

        // Writer
        let frameSize = CGSize(width: cfg.width, height: cfg.height)
        let writer = try VideoFileWriter(
            outputURL: outputURL,
            frameSize: frameSize,
            includesAudio: options.captureSystemAudio || options.captureMicrophone
        )
        self.writer = writer

        // Stream + output
        let output = StreamOutput(
            writer: writer,
            compositor: compositor,
            options: options,
            screenOrigin: screenOrigin,
            frameSize: frameSize,
            log: log
        )
        self.streamOutput = output
        let stream = SCStream(filter: filter, configuration: cfg, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        if options.captureSystemAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        }
        self.stream = stream

        // Trackers
        cursorTracker.start()
        if options.showClickPulse { clickTracker.start() }
        if options.showKeystrokes { keystrokeTracker.start() }

        // Microphone
        if options.captureMicrophone {
            try microphone.start { [weak self] sb in
                self?.streamOutput?.handleMicrophoneSampleBuffer(sb)
            }
        }

        try await stream.startCapture()
        startedAt = Date()
        isRecording = true
        log.info("Recording started — frame \(cfg.width)x\(cfg.height) @ \(options.targetFps)fps")
    }

    public func stop() async throws -> CaptureRecord {
        guard isRecording, let stream, let writer, let outputURL else {
            throw VideoRecordingError.streamFailed("stop() called without active recording")
        }

        try await stream.stopCapture()
        cursorTracker.stop()
        clickTracker.stop()
        keystrokeTracker.stop()
        if options.captureMicrophone { microphone.stop() }

        _ = try await writer.finish()

        let duration = elapsed
        let pw: Int
        let ph: Int
        switch captureMode {
        case .fullScreen:
            pw = streamOutput?.frameSize.width.intValue ?? 0
            ph = streamOutput?.frameSize.height.intValue ?? 0
        case .region(let r):
            pw = Int(r.width * 2)
            ph = Int(r.height * 2)
        }

        let record = CaptureRecord(
            id: UUID(),
            fileURL: outputURL,
            captureType: .fullScreen,   // semantics: video; library tags it via mediaType in CaptureRow
            capturedAt: startedAt ?? Date(),
            pixelWidth: pw,
            pixelHeight: ph,
            sourceApp: nil
        )
        // We can't fully express duration in CaptureRecord (it has no durationMs);
        // CaptureLibraryRecorder will include duration via fileSize and sidecar later.
        log.info("Recording stopped — duration \(duration)s, file \(outputURL.path)")

        // Reset
        self.stream = nil
        self.writer = nil
        self.streamOutput = nil
        self.startedAt = nil
        self.outputURL = nil
        self.isRecording = false

        return record
    }

    public func toggleMicrophoneMute() {
        // For v0.6.0 we treat mic toggle at start time only; mid-recording mute is a v1.1 polish.
    }
}

// MARK: - Stream output

private final class StreamOutput: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {

    let queue = DispatchQueue(label: "com.bks-lab.juicescreen.video-output")
    let writer: VideoFileWriter
    let compositor: FrameCompositor
    let options: VideoRecordingOptions
    let screenOrigin: CGPoint
    let frameSize: CGSize
    let log: Logger

    init(writer: VideoFileWriter, compositor: FrameCompositor, options: VideoRecordingOptions,
         screenOrigin: CGPoint, frameSize: CGSize, log: Logger) {
        self.writer = writer
        self.compositor = compositor
        self.options = options
        self.screenOrigin = screenOrigin
        self.frameSize = frameSize
        self.log = log
    }

    // SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            handleVideoSample(sampleBuffer)
        case .audio:
            writer.appendAudio(sampleBuffer)
        @unknown default:
            break
        }
    }

    func handleMicrophoneSampleBuffer(_ buffer: CMSampleBuffer) {
        writer.appendAudio(buffer)
    }

    private func handleVideoSample(_ sb: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sb), CMSampleBufferGetNumSamples(sb) > 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sb) else { return }

        framesReceived += 1
        if framesReceived == 1 {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            log.info("First video sample: \(w)x\(h), expected frame=\(Int(self.frameSize.width))x\(Int(self.frameSize.height))")
        }

        // Skip the compositor for now — it locks the pixel buffer, draws via a
        // CGContext over its base address, then unlocks. Any glitch there
        // (wrong row stride, wrong colour space, simultaneous read by AVAssetWriter)
        // can leave the buffer in a state where `videoAdaptor.append` rejects it
        // and the resulting MP4 is empty. v1.0.x ships without overlays in the
        // recording until the compositor is rebuilt to draw via Core Image
        // (which composes safely without locking the underlying buffer).
        // _ = compositor   // keep the reference live

        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        writer.appendVideo(pixelBuffer: pixelBuffer, presentationTime: pts)
    }

    private var framesReceived: Int = 0

    private func makeContext(for pixelBuffer: CVPixelBuffer) -> CGContext? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)

        let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    }
}

// Helper accessor used by stop() above
private extension CGFloat {
    var intValue: Int { Int(self) }
}
