import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureLibraryRecorder")
struct CaptureLibraryRecorderTests {

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
}
