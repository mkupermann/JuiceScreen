import Foundation
import Testing
@testable import JuiceScreen

@Suite("OCRBackfill")
struct OCRBackfillTests {

    // MARK: - Test-only LibraryStore stub
    //
    // Purpose: drive `OCRBackfill.run(...)` deterministically by controlling
    // the `captureIDsWithoutOCR()` return value and optional thrown error.
    // FakeLibraryStore (the project-wide fake) doesn't expose error injection
    // for that call, so we use a small private stub here. Other LibraryStore
    // methods are unused by OCRBackfill — they no-op or return defaults.
    private final class StubLibraryStore: LibraryStore, @unchecked Sendable {

        private let lock = NSLock()
        private var _pending: [(id: UUID, filePath: String)]
        private let throwOnFetch: Bool

        init(pending: [(id: UUID, filePath: String)] = [], throwOnFetch: Bool = false) {
            self._pending = pending
            self.throwOnFetch = throwOnFetch
        }

        var pending: [(id: UUID, filePath: String)] {
            get { lock.lock(); defer { lock.unlock() }; return _pending }
            set { lock.lock(); _pending = newValue; lock.unlock() }
        }

        func captureIDsWithoutOCR() async throws -> [(id: UUID, filePath: String)] {
            if throwOnFetch {
                throw LibraryStoreError.databaseError("simulated failure")
            }
            return pending
        }

        // Unused by OCRBackfill — minimal no-op conformance.
        func insert(_ row: CaptureRow) async throws {}
        func fetch(id: UUID) async throws -> CaptureRow? { nil }
        func list(filter: SmartFilter) async throws -> [CaptureRow] { [] }
        func softDelete(id: UUID) async throws {}
        func restore(id: UUID) async throws {}
        func permanentlyDelete(id: UUID) async throws {}
        func updateThumbnailPath(id: UUID, thumbnailPath: String) async throws {}
        func updateAnnotationPath(id: UUID, annotationPath: String?) async throws {}
        func upsertOCRText(id: UUID, text: String) async throws {}
        func search(query: SearchQuery) async throws -> [CaptureRow] { [] }
        func emptyTrash() async throws -> Int { 0 }
    }

    // MARK: - Helpers

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OCRBackfillTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    private func makePipeline(
        ocr: FakeOCRService,
        libraryStore: LibraryStore
    ) -> OCRPipeline {
        let paths = makeTempPaths()
        let sidecar = OCRSidecarStore(paths: paths)
        return OCRPipeline(ocrService: ocr, sidecarStore: sidecar, libraryStore: libraryStore)
    }

    private func makePending(count: Int) -> [(id: UUID, filePath: String)] {
        (0 ..< count).map { i in
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("OCRBackfillTests-pending-\(i)-\(UUID().uuidString).png")
            // Write a tiny placeholder so the file exists. Pipeline will likely fail OCR
            // on it (not a real image), but FakeOCRService doesn't actually decode it.
            try? Data("placeholder".utf8).write(to: url)
            return (UUID(), url.path)
        }
    }

    // MARK: - Tests

    @Test("Empty pending list: run() returns without invoking pipeline")
    func emptyPending() async {
        let store = StubLibraryStore(pending: [])
        let ocr = FakeOCRService()
        let pipeline = makePipeline(ocr: ocr, libraryStore: store)
        let backfill = OCRBackfill(store: store, pipeline: pipeline)

        await backfill.run()

        #expect(ocr.calls.isEmpty)
    }

    @Test("Store throws on fetch: run() returns gracefully without crashing")
    func storeThrows() async {
        let store = StubLibraryStore(throwOnFetch: true)
        let ocr = FakeOCRService()
        let pipeline = makePipeline(ocr: ocr, libraryStore: store)
        let backfill = OCRBackfill(store: store, pipeline: pipeline)

        await backfill.run()

        // Nothing should have been processed — fetch failed before the pipeline ran.
        #expect(ocr.calls.isEmpty)
    }

    @Test("Single pending item: pipeline.process is invoked once")
    func singlePending() async {
        let pending = makePending(count: 1)
        let store = StubLibraryStore(pending: pending)
        let ocr = FakeOCRService()
        let pipeline = makePipeline(ocr: ocr, libraryStore: store)
        let backfill = OCRBackfill(store: store, pipeline: pipeline)

        await backfill.run()

        #expect(ocr.calls.count == 1)
        #expect(ocr.calls.first?.path == pending[0].filePath)

        // Cleanup
        for item in pending { try? FileManager.default.removeItem(atPath: item.filePath) }
    }

    @Test("Multiple pending items at default maxConcurrency=2: all processed")
    func multipleDefaultConcurrency() async {
        let pending = makePending(count: 5)
        let store = StubLibraryStore(pending: pending)
        let ocr = FakeOCRService()
        let pipeline = makePipeline(ocr: ocr, libraryStore: store)
        let backfill = OCRBackfill(store: store, pipeline: pipeline)

        await backfill.run()

        #expect(ocr.calls.count == 5)
        let calledPaths = Set(ocr.calls.map(\.path))
        let expectedPaths = Set(pending.map(\.filePath))
        #expect(calledPaths == expectedPaths)

        for item in pending { try? FileManager.default.removeItem(atPath: item.filePath) }
    }

    @Test("maxConcurrency = 1 processes all items sequentially")
    func sequentialConcurrency() async {
        let pending = makePending(count: 3)
        let store = StubLibraryStore(pending: pending)
        let ocr = FakeOCRService()
        let pipeline = makePipeline(ocr: ocr, libraryStore: store)
        let backfill = OCRBackfill(store: store, pipeline: pipeline)

        await backfill.run(maxConcurrency: 1)

        #expect(ocr.calls.count == 3)
        let calledPaths = Set(ocr.calls.map(\.path))
        let expectedPaths = Set(pending.map(\.filePath))
        #expect(calledPaths == expectedPaths)

        for item in pending { try? FileManager.default.removeItem(atPath: item.filePath) }
    }

    @Test("maxConcurrency greater than pending.count caps spawned tasks at pending.count")
    func concurrencyCap() async {
        let pending = makePending(count: 2)
        let store = StubLibraryStore(pending: pending)
        let ocr = FakeOCRService()
        let pipeline = makePipeline(ocr: ocr, libraryStore: store)
        let backfill = OCRBackfill(store: store, pipeline: pipeline)

        await backfill.run(maxConcurrency: 10)

        // Exactly 2 calls — one per pending item, no over-spawn.
        #expect(ocr.calls.count == 2)
        let calledPaths = Set(ocr.calls.map(\.path))
        let expectedPaths = Set(pending.map(\.filePath))
        #expect(calledPaths == expectedPaths)

        for item in pending { try? FileManager.default.removeItem(atPath: item.filePath) }
    }
}
