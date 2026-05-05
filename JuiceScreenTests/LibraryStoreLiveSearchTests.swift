import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibraryStoreLive — search + OCR")
struct LibraryStoreLiveSearchTests {

    private func makeStore() throws -> LibraryStoreLive {
        let queue = try DatabaseQueue()
        try LibrarySchema.migrator().migrate(queue)
        return LibraryStoreLive(databaseQueue: queue)
    }

    private func makeRow(daysAgo: Int = 0, mediaType: MediaType = .image, sourceApp: String? = nil) -> CaptureRow {
        // Truncate to whole seconds so SQLite int round-trip preserves equality
        let secs = floor(Date().timeIntervalSince1970)
            - Double(daysAgo) * 86400
        return CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/\(UUID().uuidString).png",
            annotationPath: nil,
            thumbnailPath: "/tmp/thumb-\(UUID().uuidString).jpg",
            mediaType: mediaType,
            capturedAt: Date(timeIntervalSince1970: secs),
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil, fileSizeBytes: 100,
            sourceApp: sourceApp, deletedAt: nil
        )
    }

    @Test("upsertOCRText then search by free text returns the row")
    func upsertAndSearch() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "AWS error message at 12:34")

        var q = SearchQuery()
        q.text = "AWS"
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == row.uuid)
    }

    @Test("upsertOCRText is idempotent")
    func upsertReplaces() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "first")
        try await store.upsertOCRText(id: row.uuid, text: "second")

        var q = SearchQuery()
        q.text = "second"
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)

        q.text = "first"
        let stale = try await store.search(query: q)
        #expect(stale.isEmpty)
    }

    @Test("Empty query returns all live captures, ordered by captured_at desc")
    func emptyQueryAll() async throws {
        let store = try makeStore()
        let oldest = makeRow(daysAgo: 5)
        let newest = makeRow(daysAgo: 0)
        try await store.insert(oldest)
        try await store.insert(newest)

        let hits = try await store.search(query: SearchQuery())
        #expect(hits.map { $0.uuid } == [newest.uuid, oldest.uuid])
    }

    @Test("from:Safari + type:image filters apply alongside FTS5 MATCH")
    func combinedFilters() async throws {
        let store = try makeStore()
        let safari = makeRow(sourceApp: "Safari")
        let chrome = makeRow(sourceApp: "Chrome")
        try await store.insert(safari)
        try await store.insert(chrome)
        try await store.upsertOCRText(id: safari.uuid, text: "Hello AWS")
        try await store.upsertOCRText(id: chrome.uuid, text: "Hello AWS")

        var q = SearchQuery()
        q.text = "AWS"
        q.sourceApp = "Safari"
        q.mediaType = .image
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == safari.uuid)
    }

    @Test("after + before filters bound captured_at range")
    func dateRange() async throws {
        let store = try makeStore()
        let cal = Calendar.current
        let dayOld = makeRow(daysAgo: 1)
        let weekOld = makeRow(daysAgo: 7)
        try await store.insert(dayOld)
        try await store.insert(weekOld)

        var q = SearchQuery()
        q.after = cal.date(byAdding: .day, value: -3, to: Date())
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == dayOld.uuid)
    }

    @Test("Soft-deleted rows are excluded from search")
    func excludeDeleted() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "find me")
        try await store.softDelete(id: row.uuid)

        var q = SearchQuery()
        q.text = "find me"
        let hits = try await store.search(query: q)
        #expect(hits.isEmpty)
    }
}
