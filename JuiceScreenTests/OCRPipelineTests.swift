import Foundation
import Testing
@testable import JuiceScreen

@Suite("OCRPipeline")
struct OCRPipelineTests {

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    private func tempPNG() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OCRPipelineTest-\(UUID().uuidString).png")
        try Data("not a real png".utf8).write(to: url)
        return url
    }

    @Test("process(captureID:fileURL:) writes sidecar + upserts FTS5 text")
    func process() async throws {
        let paths = makeTempPaths()
        let sidecarStore = OCRSidecarStore(paths: paths)
        let libraryStore = FakeLibraryStore()
        let ocr = FakeOCRService()
        ocr.nextResult = .success(OCRResult(
            regions: [
                OCRRegion(text: "Hello", boundingBox: .zero),
                OCRRegion(text: "World", boundingBox: .zero)
            ],
            extractedAt: Date(timeIntervalSince1970: 1)
        ))

        // Insert a row first so search() can see it
        let row = CaptureRow(
            uuid: UUID(), filePath: "/tmp/x.png", annotationPath: nil, thumbnailPath: "/t",
            mediaType: .image, capturedAt: Date(),
            pixelWidth: 1, pixelHeight: 1, durationMs: nil,
            fileSizeBytes: 0, sourceApp: nil, deletedAt: nil
        )
        try await libraryStore.insert(row)

        let pipeline = OCRPipeline(
            ocrService: ocr,
            sidecarStore: sidecarStore,
            libraryStore: libraryStore
        )

        let url = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        try await pipeline.process(captureID: row.uuid, fileURL: url)

        // Sidecar exists with the result
        let loaded = try sidecarStore.read(for: row.uuid)
        #expect(loaded?.regions.count == 2)

        // FTS5 has the concatenated text
        var q = SearchQuery()
        q.text = "Hello"
        let hits = try await libraryStore.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == row.uuid)
    }

    @Test("OCR failure: pipeline logs but does not propagate the error")
    func failureSwallowed() async throws {
        let paths = makeTempPaths()
        let sidecarStore = OCRSidecarStore(paths: paths)
        let libraryStore = FakeLibraryStore()
        let ocr = FakeOCRService()
        ocr.nextResult = .failure(.imageLoadFailed)

        let pipeline = OCRPipeline(
            ocrService: ocr,
            sidecarStore: sidecarStore,
            libraryStore: libraryStore
        )

        let url = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        // Should not throw — pipeline catches OCRError and logs
        try await pipeline.process(captureID: UUID(), fileURL: url)

        // No sidecar written
        let loaded = try sidecarStore.read(for: UUID())
        #expect(loaded == nil)
    }
}
