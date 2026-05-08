import AppKit
import Foundation
import GRDB
import Testing
@testable import JuiceScreen

/// End-to-end pipeline coverage. Wires the same components a real user hits when
/// they: capture a region → the capture is recorded into the library → they open
/// the library and pick the row → the editor loads it → they export.
///
/// No UI: the data path is identical, but everything runs in-process so the test
/// is deterministic and runs in CI without Screen Recording permission.
@Suite("CapturePipelineE2E")
@MainActor
struct CapturePipelineE2ETests {

    private struct PipelineFixture {
        let recorder: CaptureLibraryRecorder
        let store: LibraryStoreLive
        let thumbnailStore: ThumbnailStore
        let paths: LibraryPaths
        let captureFileURL: URL
        let cleanupRoot: URL
    }

    private static func makeFixture(width: Int = 200, height: Int = 150, fill: NSColor = .systemRed) throws -> PipelineFixture {
        let testRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenE2E-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)

        let captureURL = testRoot.appendingPathComponent("JuiceScreen_e2e.png")
        let imageData = try makeSolidPNG(width: width, height: height, color: fill)
        try imageData.write(to: captureURL)

        let queue = try DatabaseQueue()
        try LibrarySchema.migrator().migrate(queue)
        let store = LibraryStoreLive(databaseQueue: queue)

        let paths = LibraryPaths(rootDirectory: testRoot)
        let thumbnailStore = ThumbnailStore(paths: paths)

        let recorder = CaptureLibraryRecorder(store: store, thumbnailStore: thumbnailStore)

        return PipelineFixture(
            recorder: recorder,
            store: store,
            thumbnailStore: thumbnailStore,
            paths: paths,
            captureFileURL: captureURL,
            cleanupRoot: testRoot
        )
    }

    private static func makeSolidPNG(width: Int, height: Int, color: NSColor) throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        color.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return try PNGEncoder.encode(img)
    }

    @Test("Full user-path: synthetic capture → library insert → library query → editor doc → export PNG")
    func captureToExportPNG() async throws {
        let fx = try Self.makeFixture(width: 200, height: 150, fill: .systemRed)
        defer { try? FileManager.default.removeItem(at: fx.cleanupRoot) }

        // 1. Capture — this is what AppDelegate.fireCapture posts to the recorder.
        let record = CaptureRecord(
            fileURL: fx.captureFileURL,
            captureType: .region,
            capturedAt: Date(),
            pixelWidth: 200, pixelHeight: 150,
            sourceApp: "Safari"
        )
        try await fx.recorder.record(record)

        // 2. Library round-trip — library window pulls rows by .recent(...).
        let recent = try await fx.store.list(filter: .all)
        let row = try #require(recent.first { $0.uuid == record.id })
        #expect(row.filePath == fx.captureFileURL.path)
        #expect(row.pixelWidth == 200)
        #expect(row.pixelHeight == 150)
        #expect(row.sourceApp == "Safari")
        #expect(row.fileSizeBytes > 0)
        #expect(FileManager.default.fileExists(atPath: row.thumbnailPath))

        // 3. Editor opens — same construction the AppDelegate uses (line 130-138).
        let baseImage = try #require(NSImage(contentsOf: URL(fileURLWithPath: row.filePath)))
        let doc = AnnotationDocument(baseImage: baseImage)

        // 4. Export — this is what the editor's "Save As" menu fires.
        let outURL = fx.cleanupRoot.appendingPathComponent("export.png")
        try ExportService.export(document: doc, format: .png, jpegQuality: 0.9, to: outURL)

        // 5. Verify the user actually got a valid PNG with the right dimensions.
        let outData = try Data(contentsOf: outURL)
        #expect(Array(outData.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let outRep = try #require(NSBitmapImageRep(data: outData))
        #expect(outRep.pixelsWide == 200)
        #expect(outRep.pixelsHigh == 150)
    }

    @Test("Full user-path with crop: capture → library → editor crop → export JPG smaller than source")
    func captureCropToExportJPG() async throws {
        let fx = try Self.makeFixture(width: 400, height: 300, fill: .systemBlue)
        defer { try? FileManager.default.removeItem(at: fx.cleanupRoot) }

        let record = CaptureRecord(
            fileURL: fx.captureFileURL,
            captureType: .region,
            capturedAt: Date(),
            pixelWidth: 400, pixelHeight: 300,
            sourceApp: nil
        )
        try await fx.recorder.record(record)

        let baseImage = try #require(NSImage(contentsOf: fx.captureFileURL))
        var doc = AnnotationDocument(baseImage: baseImage)
        doc.canvasCrop = CGRect(x: 0, y: 0, width: 100, height: 100)

        let outURL = fx.cleanupRoot.appendingPathComponent("export.jpg")
        try ExportService.export(document: doc, format: .jpg, jpegQuality: 0.85, to: outURL)

        let outData = try Data(contentsOf: outURL)
        #expect(Array(outData.prefix(2)) == [0xFF, 0xD8])
        let outRep = try #require(NSBitmapImageRep(data: outData))
        #expect(outRep.pixelsWide <= 200 && outRep.pixelsWide >= 50)
        #expect(outRep.pixelsHigh <= 200 && outRep.pixelsHigh >= 50)
    }

    @Test("Library survives multiple captures and returns them in capturedAt-desc order")
    func multipleCapturesOrdered() async throws {
        let fx = try Self.makeFixture(width: 50, height: 50)
        defer { try? FileManager.default.removeItem(at: fx.cleanupRoot) }

        let now = Date()
        for offset in 0..<3 {
            let url = fx.cleanupRoot.appendingPathComponent("cap-\(offset).png")
            try Self.makeSolidPNG(width: 50, height: 50, color: .systemGreen).write(to: url)
            let record = CaptureRecord(
                fileURL: url,
                captureType: .region,
                capturedAt: now.addingTimeInterval(TimeInterval(offset)),
                pixelWidth: 50, pixelHeight: 50,
                sourceApp: "Test\(offset)"
            )
            try await fx.recorder.record(record)
        }

        let rows = try await fx.store.list(filter: .all)
        #expect(rows.count == 3)
        // capturedAt-desc means newest (offset=2) first.
        #expect(rows[0].sourceApp == "Test2")
        #expect(rows[1].sourceApp == "Test1")
        #expect(rows[2].sourceApp == "Test0")
    }
}
