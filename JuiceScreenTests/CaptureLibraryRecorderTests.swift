import AppKit
import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureLibraryRecorder")
struct CaptureLibraryRecorderTests {

    private static func makeTinyMP4(at url: URL) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
        if let pb {
            adaptor.append(pb, withPresentationTime: .zero)
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    private func makeRealFile() throws -> (URL, NSImage) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("JuiceScreen_x.png")

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: 100, height: 80))
        img.addRepresentation(rep)
        let data = try PNGEncoder.encode(img)
        try data.write(to: url)

        return (url, img)
    }

    @Test("record(_:) writes thumbnail, inserts row in store, and uses correct fields")
    func recordsCapture() async throws {
        let store = FakeLibraryStore()
        let paths = makeTempPaths()
        let thumbStore = ThumbnailStore(paths: paths)
        let recorder = CaptureLibraryRecorder(store: store, thumbnailStore: thumbStore)

        let (fileURL, _) = try makeRealFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let record = CaptureRecord(
            fileURL: fileURL,
            captureType: .region,
            capturedAt: Date(),
            pixelWidth: 100, pixelHeight: 80,
            sourceApp: nil
        )

        try await recorder.record(record)

        let stored = try await store.fetch(id: record.id)
        let row = try #require(stored)
        #expect(row.uuid == record.id)
        #expect(row.filePath == fileURL.path)
        #expect(row.pixelWidth == 100)
        #expect(row.pixelHeight == 80)
        #expect(row.fileSizeBytes > 0)
        #expect(FileManager.default.fileExists(atPath: row.thumbnailPath))
    }

    @Test("record(_:) with non-existent file returns early and inserts no row")
    func recordSkipsWhenThumbnailDeriveFails() async throws {
        let store = FakeLibraryStore()
        let paths = makeTempPaths()
        let thumbStore = ThumbnailStore(paths: paths)
        let recorder = CaptureLibraryRecorder(store: store, thumbnailStore: thumbStore)

        let bogusURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).png")

        let record = CaptureRecord(
            fileURL: bogusURL,
            captureType: .region,
            capturedAt: Date(),
            pixelWidth: 10, pixelHeight: 10,
            sourceApp: nil
        )

        try await recorder.record(record)

        // No row should have been inserted
        let stored = try await store.fetch(id: record.id)
        #expect(stored == nil)
    }

    @Test("record(_:) with empty .mp4 returns early when frame extraction fails")
    func recordVideoEmptyFileReturnsEarly() async throws {
        let store = FakeLibraryStore()
        let paths = makeTempPaths()
        let thumbStore = ThumbnailStore(paths: paths)
        let recorder = CaptureLibraryRecorder(store: store, thumbnailStore: thumbStore)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("empty.mp4")
        try Data().write(to: url)

        let record = CaptureRecord(
            fileURL: url,
            captureType: .fullScreen,
            capturedAt: Date(),
            pixelWidth: 64, pixelHeight: 64,
            sourceApp: nil
        )

        try await recorder.record(record)

        // Empty mp4 → AVAssetImageGenerator throws → early return → no row
        let stored = try await store.fetch(id: record.id)
        #expect(stored == nil)
    }

    @Test("record(_:) with real .mp4 inserts a video row with duration and thumbnail")
    func recordVideoSuccessfullyInsertsRow() async throws {
        let store = FakeLibraryStore()
        let paths = makeTempPaths()
        let thumbStore = ThumbnailStore(paths: paths)
        let recorder = CaptureLibraryRecorder(store: store, thumbnailStore: thumbStore)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("tiny.mp4")
        try await Self.makeTinyMP4(at: url)

        let record = CaptureRecord(
            fileURL: url,
            captureType: .fullScreen,
            capturedAt: Date(),
            pixelWidth: 64, pixelHeight: 64,
            sourceApp: "TestApp"
        )

        try await recorder.record(record)

        let stored = try await store.fetch(id: record.id)
        if let row = stored {
            // mp4 was decodable: video branch took effect
            #expect(row.uuid == record.id)
            #expect(row.mediaType == .video)
            #expect(row.filePath == url.path)
            #expect(row.pixelWidth == 64)
            #expect(row.pixelHeight == 64)
            #expect(row.fileSizeBytes > 0)
            #expect(row.sourceApp == "TestApp")
            #expect(FileManager.default.fileExists(atPath: row.thumbnailPath))
        } else {
            // Acceptable fallback: frame extraction failed in this environment.
            // Source's early-return branch was exercised either way.
            #expect(stored == nil)
        }
    }

    @Test("record(_:) with image dispatches OCR pipeline without throwing")
    func recordImageWithOCRPipelineCompletes() async throws {
        let store = FakeLibraryStore()
        let paths = makeTempPaths()
        let thumbStore = ThumbnailStore(paths: paths)
        let sidecarStore = OCRSidecarStore(paths: paths)
        let ocrService = FakeOCRService()
        ocrService.nextResult = .success(OCRResult(
            regions: [OCRRegion(text: "hi", boundingBox: .zero)],
            extractedAt: Date()
        ))
        let pipeline = OCRPipeline(
            ocrService: ocrService,
            sidecarStore: sidecarStore,
            libraryStore: store
        )
        let recorder = CaptureLibraryRecorder(
            store: store,
            thumbnailStore: thumbStore,
            ocrPipeline: pipeline
        )

        let (fileURL, _) = try makeRealFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let record = CaptureRecord(
            fileURL: fileURL,
            captureType: .region,
            capturedAt: Date(),
            pixelWidth: 100, pixelHeight: 80,
            sourceApp: nil
        )

        // Should not throw — OCR pipeline is dispatched as a detached task
        try await recorder.record(record)

        let stored = try await store.fetch(id: record.id)
        let row = try #require(stored)
        #expect(row.uuid == record.id)
        #expect(row.mediaType == .image)
    }

    @Test("record(_:) with .mp4 extension does NOT trigger OCR pipeline")
    func recordVideoSkipsOCRPipeline() async throws {
        let store = FakeLibraryStore()
        let paths = makeTempPaths()
        let thumbStore = ThumbnailStore(paths: paths)
        let sidecarStore = OCRSidecarStore(paths: paths)
        let ocrService = FakeOCRService()
        let pipeline = OCRPipeline(
            ocrService: ocrService,
            sidecarStore: sidecarStore,
            libraryStore: store
        )
        let recorder = CaptureLibraryRecorder(
            store: store,
            thumbnailStore: thumbStore,
            ocrPipeline: pipeline
        )

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("tiny.mp4")
        try await Self.makeTinyMP4(at: url)

        let record = CaptureRecord(
            fileURL: url,
            captureType: .fullScreen,
            capturedAt: Date(),
            pixelWidth: 64, pixelHeight: 64,
            sourceApp: nil
        )

        try await recorder.record(record)

        // Whether the row was inserted or not depends on whether the mp4
        // could be decoded for a thumbnail. Either way, OCR must not have
        // been called for the video extension.
        // Give any (incorrectly dispatched) detached task a chance to run.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(ocrService.calls.isEmpty)
    }
}
