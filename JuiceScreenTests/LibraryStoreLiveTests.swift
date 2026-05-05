import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibraryStoreLive")
struct LibraryStoreLiveTests {

    /// Builds an in-memory GRDB DatabaseQueue with the v1 schema applied.
    private func makeStore() throws -> LibraryStoreLive {
        let queue = try DatabaseQueue()
        try LibrarySchema.migrator().migrate(queue)
        return LibraryStoreLive(databaseQueue: queue)
    }

    private func makeRow(daysAgo: Int = 0, mediaType: MediaType = .image, deleted: Bool = false, sourceApp: String? = nil) -> CaptureRow {
        let rawDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        // Truncate to whole seconds so SQLite integer round-trip preserves equality.
        let date = Date(timeIntervalSince1970: floor(rawDate.timeIntervalSince1970))
        let deletedAt: Date? = deleted ? Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)) : nil
        return CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/\(UUID().uuidString).png",
            annotationPath: nil,
            thumbnailPath: "/tmp/thumb-\(UUID().uuidString).jpg",
            mediaType: mediaType,
            capturedAt: date,
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil,
            fileSizeBytes: 1234,
            sourceApp: sourceApp,
            deletedAt: deletedAt
        )
    }

    @Test("Insert + fetch round-trip preserves all fields")
    func insertFetch() async throws {
        let store = try makeStore()
        let row = makeRow(sourceApp: "Safari")
        try await store.insert(row)
        let fetched = try await store.fetch(id: row.uuid)
        #expect(fetched == row)
    }

    @Test(".all is ordered by captured_at descending and excludes soft-deleted")
    func listAll() async throws {
        let store = try makeStore()
        let live1 = makeRow(daysAgo: 1)
        let live2 = makeRow(daysAgo: 0)
        let trashed = makeRow(daysAgo: 0, deleted: true)
        try await store.insert(live1)
        try await store.insert(live2)
        try await store.insert(trashed)

        let result = try await store.list(filter: .all)
        #expect(result.map { $0.uuid } == [live2.uuid, live1.uuid])
    }

    @Test("softDelete then list .trash returns the trashed row")
    func softDeleteThenTrash() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)
        let trash = try await store.list(filter: .trash)
        #expect(trash.count == 1)
        #expect(trash.first!.isDeleted == true)
    }

    @Test("restore removes deletedAt")
    func restore() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)
        try await store.restore(id: row.uuid)
        let live = try await store.list(filter: .all)
        #expect(live.count == 1)
        #expect(live.first!.isDeleted == false)
    }

    @Test("permanentlyDelete removes the row")
    func permanent() async throws {
        let store = try makeStore()
        let row = makeRow(deleted: true)
        try await store.insert(row)
        try await store.permanentlyDelete(id: row.uuid)
        #expect(try await store.fetch(id: row.uuid) == nil)
    }

    @Test("updateThumbnailPath persists the change")
    func updateThumb() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.updateThumbnailPath(id: row.uuid, thumbnailPath: "/new/thumb.jpg")
        let fetched = try await store.fetch(id: row.uuid)
        #expect(fetched?.thumbnailPath == "/new/thumb.jpg")
    }

    @Test("Filter .videos and .images segregate correctly")
    func mediaTypeFilter() async throws {
        let store = try makeStore()
        let image = makeRow(mediaType: .image)
        let video = makeRow(mediaType: .video)
        try await store.insert(image)
        try await store.insert(video)

        let images = try await store.list(filter: .images)
        let videos = try await store.list(filter: .videos)
        #expect(images.map { $0.uuid } == [image.uuid])
        #expect(videos.map { $0.uuid } == [video.uuid])
    }
}
