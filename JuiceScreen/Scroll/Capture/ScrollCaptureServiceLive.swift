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

    /// `region` is in global bottom-left screen coordinates, exactly as
    /// `RegionPickerController.pickRegion()` returns it.
    public func start(region: CGRect, handler: @escaping FrameHandler) async throws {
        guard !isRunning else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Pick the display holding the selection's centre, not just the first one —
        // on a multi-display setup the region rarely lives on displays[0].
        let center = CGPoint(x: region.midX, y: region.midY)
        guard let display = ScreenCaptureKitHelpers.display(containing: center, in: content)
                ?? content.displays.first else {
            throw ScrollCaptureError.streamConfigurationFailed("No displays available")
        }

        // sourceRect is display-local and top-left origin; the picker's rect is
        // global and bottom-left origin. Without the flip the captured band sits
        // mirrored about the display's horizontal centre.
        let sourceRect = ScreenCaptureKitHelpers.displayLocalTopLeft(
            globalBL: region,
            displayFrame: ScreenCaptureKitHelpers.globalFrame(of: display)
        )

        let pixelDensity = 2
        let cfg = SCStreamConfiguration()
        cfg.width = Int(sourceRect.width) * pixelDensity
        cfg.height = Int(sourceRect.height) * pixelDensity
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 10)   // 10fps target
        cfg.queueDepth = 4
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.sourceRect = sourceRect

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
