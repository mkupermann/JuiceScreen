import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class ScrollCaptureSession {

    private let service: ScrollCaptureService
    private let stitcher: FrameStitcher
    private let saveDirectory: SaveDirectoryProvider
    private let filenameGenerator: FilenameGenerator
    private let onComplete: (CaptureRecord) -> Void
    private let onError: (ScrollCaptureError) -> Void

    private var promptWindow: ScrollPromptWindow?
    private var controlWindow: ScrollControlWindow?
    private var regionPicker: RegionPickerController?
    private var builder: StitchedImageBuilder?
    private var lastFrame: CGImage?
    private var region: CGRect = .zero
    private var startedAt: Date = .distantPast

    private let log = AppLog.logger(category: "ScrollCaptureSession")

    public init(
        service: ScrollCaptureService,
        stitcher: FrameStitcher = FrameStitcher(),
        saveDirectory: SaveDirectoryProvider,
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        onComplete: @escaping (CaptureRecord) -> Void,
        onError: @escaping (ScrollCaptureError) -> Void
    ) {
        self.service = service
        self.stitcher = stitcher
        self.saveDirectory = saveDirectory
        self.filenameGenerator = filenameGenerator
        self.onComplete = onComplete
        self.onError = onError
    }

    public func begin() {
        let prompt = ScrollPromptWindow()
        promptWindow = prompt
        prompt.show(
            onStart: { [weak self] in
                Task { @MainActor in await self?.pickRegionThenStart() }
            },
            onCancel: { [weak self] in
                self?.onError(.userCancelled)
            }
        )
    }

    private func pickRegionThenStart() async {
        let picker = RegionPickerController()
        regionPicker = picker
        do {
            let chosen = try await picker.pickRegion()
            self.region = chosen
            try await startCollecting()
        } catch {
            onError(.userCancelled)
        }
    }

    private func startCollecting() async throws {
        let win = ScrollControlWindow(onStop: { [weak self] in
            Task { @MainActor in await self?.stopAndStitch() }
        })
        controlWindow = win
        win.show()
        startedAt = Date()

        try await service.start(region: region) { [weak self] frame in
            self?.handleFrame(frame)
        }
    }

    private func handleFrame(_ frame: CGImage) {
        if builder == nil {
            builder = StitchedImageBuilder(firstFrame: frame)
            lastFrame = frame
            controlWindow?.update(frameCount: 1, onStop: { [weak self] in
                Task { @MainActor in await self?.stopAndStitch() }
            })
            return
        }

        guard let last = lastFrame, let builder else { return }

        if let offset = stitcher.detectOffset(previous: last, current: frame), offset.isUsable {
            builder.append(frame: frame, offset: offset)
            lastFrame = frame
        }
        // Else: this frame is a no-scroll or unreliable match; we keep `lastFrame`
        // unchanged so the next frame is compared against the same anchor. This
        // makes us robust to tiny user pauses without inserting bad slices.

        controlWindow?.update(frameCount: builder.frameCount, onStop: { [weak self] in
            Task { @MainActor in await self?.stopAndStitch() }
        })
    }

    private func stopAndStitch() async {
        do { try await service.stop() } catch {
            log.error("Service stop failed: \(String(describing: error))")
        }
        controlWindow?.close()
        controlWindow = nil

        guard let builder, builder.frameCount > 0,
              let final = builder.finalImage else {
            onError(.noFramesCaptured)
            return
        }

        // Save PNG
        do {
            let date = Date()
            let folder = try saveDirectory.directory(for: date)
            let filename = filenameGenerator.filename(for: date, extension: "png")
            let url = folder.appendingPathComponent(filename)
            try writePNG(final, to: url)

            let record = CaptureRecord(
                id: UUID(),
                fileURL: url,
                captureType: .scroll,
                capturedAt: date,
                pixelWidth: final.width,
                pixelHeight: final.height,
                sourceApp: nil
            )
            onComplete(record)
        } catch {
            onError(.writeFailed("\(error)"))
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let data = try PNGEncoder.encode(nsImage)
        try data.write(to: url, options: .atomic)
    }
}
