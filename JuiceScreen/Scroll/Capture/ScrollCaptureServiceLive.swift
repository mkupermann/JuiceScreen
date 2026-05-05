import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
public final class ScrollCaptureServiceLive: NSObject, ScrollCaptureService {

    public private(set) var isRunning: Bool = false

    private var stream: SCStream?
    private var output: StreamOutput?
    private let log = AppLog.logger(category: "ScrollCaptureServiceLive")

    public override init() { super.init() }

    public func start(region: CGRect, handler: @escaping FrameHandler) async throws {
        guard !isRunning else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScrollCaptureError.streamConfigurationFailed("No displays available")
        }

        let pixelDensity = 2
        let cfg = SCStreamConfiguration()
        cfg.width = Int(region.width) * pixelDensity
        cfg.height = Int(region.height) * pixelDensity
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 10)   // 10fps target
        cfg.queueDepth = 4
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.sourceRect = region

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let output = StreamOutput(handler: handler)
        self.output = output
        let stream = SCStream(filter: filter, configuration: cfg, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)

        try await stream.startCapture()
        self.stream = stream
        isRunning = true
        log.info("Scroll capture started — \(cfg.width)x\(cfg.height) @ 10fps")
    }

    public func stop() async throws {
        guard isRunning, let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
        self.output = nil
        isRunning = false
        log.info("Scroll capture stopped")
    }
}

private final class StreamOutput: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {

    let queue = DispatchQueue(label: "com.bks-lab.juicescreen.scroll-output")
    let handler: ScrollCaptureService.FrameHandler

    init(handler: @escaping ScrollCaptureService.FrameHandler) {
        self.handler = handler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        // Snapshot the pixel buffer to a CGImage for safe handoff to the main actor.
        guard let cgImage = makeCGImage(from: pixelBuffer) else { return }
        Task { @MainActor in
            handler(cgImage)
        }
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: base,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }
        return ctx.makeImage()
    }
}
