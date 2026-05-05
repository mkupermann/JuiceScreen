import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("LibraryViewModel")
@MainActor
struct LibraryViewModelTests {

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

    @Test("Initial state: filter .all, no captures, no selection")
    func initial() async {
        let store = FakeLibraryStore()
        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        #expect(vm.filter == .all)
        #expect(vm.captures.isEmpty)
        #expect(vm.selectedID == nil)
    }

    @Test("reload() pulls captures matching the current filter")
    func reload() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)

        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        await vm.reload()
        #expect(vm.captures.count == 1)
        #expect(vm.captures.first?.uuid == row.uuid)
    }

    @Test("Changing filter triggers reload of new filter")
    func filterChange() async throws {
        let store = FakeLibraryStore()
        let live = makeRow()
        let trashed = makeRow(deleted: true)
        try await store.insert(live)
        try await store.insert(trashed)

        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        await vm.setFilter(.trash)
        #expect(vm.filter == .trash)
        #expect(vm.captures.count == 1)
        #expect(vm.captures.first?.uuid == trashed.uuid)
    }

    @Test("moveSelectedToTrash soft-deletes the selected capture and reloads")
    func moveToTrash() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)

        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        await vm.reload()
        vm.selectedID = row.uuid

        await vm.moveSelectedToTrash()
        #expect(vm.captures.isEmpty)
        #expect(vm.selectedID == nil)

        await vm.setFilter(.trash)
        #expect(vm.captures.count == 1)
        #expect(vm.captures.first?.deletedAt != nil)
    }
}
