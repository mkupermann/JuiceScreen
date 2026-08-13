import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibraryStoreLive.permanentlyDelete")
struct LibraryStoreLivePermanentDeleteTests {

    private func makeStore() throws -> LibraryStoreLive {
        let queue = try DatabaseQueue()
        try LibrarySchema.migrator().migrate(queue)
        return LibraryStoreLive(databaseQueue: queue)
    }

    private func makeRow() -> CaptureRow {
        CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/\(UUID().uuidString).png",
            annotationPath: nil,
            thumbnailPath: "/tmp/thumb-\(UUID().uuidString).jpg",
            mediaType: .image,
            capturedAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil,
            fileSizeBytes: 1234,
            sourceApp: nil,
            deletedAt: nil
        )
    }

    @Test("permanentlyDelete purges the row's OCR text from the FTS index")
    func purgesFTS() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "peculiartoken invoice total")

        var q = SearchQuery()
        q.text = "peculiartoken"
        #expect(try await store.search(query: q).count == 1)

        try await store.permanentlyDelete(id: row.uuid)

        // The row is gone AND its OCR text is no longer searchable in FTS5.
        #expect(try await store.fetch(id: row.uuid) == nil)
        #expect(try await store.search(query: q).isEmpty)
    }
}
