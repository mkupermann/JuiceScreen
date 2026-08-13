import Foundation
import Testing
@testable import JuiceScreen

@Suite("OrphanReaper")
struct OrphanReaperTests {

    private func makeTempRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ url: URL) throws {
        try Data("payload".utf8).write(to: url)
    }

    @Test("sweep deletes sidecar + thumbnail whose UUID has no library row, keeps known ones")
    func reapsOrphans() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LibraryPaths(rootDirectory: root)

        let known = UUID()
        let orphan = UUID()

        try write(paths.ocrSidecarURL(for: known))
        try write(paths.ocrSidecarURL(for: orphan))
        try write(paths.thumbnailURL(for: known))
        try write(paths.thumbnailURL(for: orphan))

        let removed = try OrphanReaper(paths: paths).sweep(knownIDs: [known])

        #expect(removed == 2)
        #expect(FileManager.default.fileExists(atPath: try paths.ocrSidecarURL(for: known).path))
        #expect(FileManager.default.fileExists(atPath: try paths.thumbnailURL(for: known).path))
        #expect(!FileManager.default.fileExists(atPath: try paths.ocrSidecarURL(for: orphan).path))
        #expect(!FileManager.default.fileExists(atPath: try paths.thumbnailURL(for: orphan).path))
    }

    @Test("sweep leaves files whose name is not a bare capture UUID untouched")
    func ignoresNonUUIDFiles() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LibraryPaths(rootDirectory: root)

        let notes = try paths.ocrDirectory().appendingPathComponent("notes.json", isDirectory: false)
        try write(notes)

        let removed = try OrphanReaper(paths: paths).sweep(knownIDs: [])

        #expect(removed == 0)
        #expect(FileManager.default.fileExists(atPath: notes.path))
    }

    @Test("sweep with all IDs known removes nothing")
    func keepsEverythingKnown() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LibraryPaths(rootDirectory: root)

        let a = UUID(), b = UUID()
        try write(paths.ocrSidecarURL(for: a))
        try write(paths.thumbnailURL(for: b))

        let removed = try OrphanReaper(paths: paths).sweep(knownIDs: [a, b])

        #expect(removed == 0)
        #expect(FileManager.default.fileExists(atPath: try paths.ocrSidecarURL(for: a).path))
        #expect(FileManager.default.fileExists(atPath: try paths.thumbnailURL(for: b).path))
    }
}
