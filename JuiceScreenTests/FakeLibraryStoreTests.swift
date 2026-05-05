import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeLibraryStore")
struct FakeLibraryStoreTests {

    private func makeRow(daysAgo: Int = 0, mediaType: MediaType = .image, deleted: Bool = false) -> CaptureRow {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/x.png",
            annotationPath: nil,
            thumbnailPath: "/tmp/t.jpg",
            mediaType: mediaType,
            capturedAt: date,
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil,
            fileSizeBytes: 1234,
            sourceApp: nil,
            deletedAt: deleted ? Date() : nil
        )
    }

    @Test("Insert + fetch round-trip")
    func insertFetch() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)
        let fetched = try await store.fetch(id: row.uuid)
        #expect(fetched == row)
    }

    @Test(".all returns live captures ordered by captured_at descending")
    func filterAll() async throws {
        let store = FakeLibraryStore()
        let oldest = makeRow(daysAgo: 5)
        let newest = makeRow(daysAgo: 0)
        let middle = makeRow(daysAgo: 2)
        try await store.insert(oldest)
        try await store.insert(newest)
        try await store.insert(middle)

        let live = try await store.list(filter: .all)
        #expect(live.map { $0.uuid } == [newest.uuid, middle.uuid, oldest.uuid])
    }

    @Test(".today returns only captures from today")
    func filterToday() async throws {
        let store = FakeLibraryStore()
        let today = makeRow(daysAgo: 0)
        let yesterday = makeRow(daysAgo: 1)
        try await store.insert(today)
        try await store.insert(yesterday)

        let result = try await store.list(filter: .today)
        #expect(result.map { $0.uuid } == [today.uuid])
    }

    @Test(".images excludes videos and vice versa")
    func filterByMediaType() async throws {
        let store = FakeLibraryStore()
        let image = makeRow(mediaType: .image)
        let video = makeRow(mediaType: .video)
        try await store.insert(image)
        try await store.insert(video)

        let images = try await store.list(filter: .images)
        let videos = try await store.list(filter: .videos)
        #expect(images.map { $0.uuid } == [image.uuid])
        #expect(videos.map { $0.uuid } == [video.uuid])
    }

    @Test(".trash returns only soft-deleted captures; non-trash filters exclude them")
    func filterTrash() async throws {
        let store = FakeLibraryStore()
        let live = makeRow()
        let trashed = makeRow(deleted: true)
        try await store.insert(live)
        try await store.insert(trashed)

        let allLive = try await store.list(filter: .all)
        let trash = try await store.list(filter: .trash)
        #expect(allLive.map { $0.uuid } == [live.uuid])
        #expect(trash.map { $0.uuid } == [trashed.uuid])
    }

    @Test("softDelete sets deletedAt and removes row from .all but adds it to .trash")
    func softDelete() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)

        let allLive = try await store.list(filter: .all)
        let trash = try await store.list(filter: .trash)
        #expect(allLive.isEmpty)
        #expect(trash.count == 1)
        #expect(trash.first!.uuid == row.uuid)
        #expect(trash.first!.isDeleted == true)
    }

    @Test("restore clears deletedAt and returns row to .all")
    func restore() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)
        try await store.restore(id: row.uuid)

        let allLive = try await store.list(filter: .all)
        #expect(allLive.count == 1)
        #expect(allLive.first!.isDeleted == false)
    }

    @Test("permanentlyDelete removes the row entirely")
    func permanentlyDelete() async throws {
        let store = FakeLibraryStore()
        let row = makeRow(deleted: true)
        try await store.insert(row)
        try await store.permanentlyDelete(id: row.uuid)

        let trash = try await store.list(filter: .trash)
        #expect(trash.isEmpty)
    }

    @Test("Fetching non-existent id returns nil")
    func fetchMissing() async throws {
        let store = FakeLibraryStore()
        let result = try await store.fetch(id: UUID())
        #expect(result == nil)
    }
}
