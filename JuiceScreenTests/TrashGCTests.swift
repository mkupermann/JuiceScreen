import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrashGC")
struct TrashGCTests {

    private func makeTempRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTrashedFile(in root: URL, captureID: UUID, ageInDays: Int) throws -> URL {
        let folder = root.appendingPathComponent(".trash/\(captureID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("file.png")
        try Data("x".utf8).write(to: url)
        let ageDate = Calendar.current.date(byAdding: .day, value: -ageInDays, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: ageDate], ofItemAtPath: url.path)
        return url
    }

    @Test("Files older than 30 days are deleted; younger files remain")
    func sweep() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldFile = try makeTrashedFile(in: root, captureID: UUID(), ageInDays: 60)
        let youngFile = try makeTrashedFile(in: root, captureID: UUID(), ageInDays: 5)

        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        let removed = try await gc.sweep()

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: youngFile.path))
    }

    @Test("Empty .trash directory sweep returns 0 with no error")
    func emptyTrash() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Create empty .trash dir
        let trashDir = root.appendingPathComponent(".trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        let removed = try await gc.sweep()
        #expect(removed == 0)
    }

    @Test("Missing .trash directory sweep returns 0 with no error")
    func missingTrash() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-nonexistent-\(UUID().uuidString)", isDirectory: true)
        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        let removed = try await gc.sweep()
        #expect(removed == 0)
    }

    @Test("Empty per-capture folders are also removed")
    func emptyFoldersRemoved() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let oldFile = try makeTrashedFile(in: root, captureID: id, ageInDays: 60)
        let folder = oldFile.deletingLastPathComponent()

        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        _ = try await gc.sweep()

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
