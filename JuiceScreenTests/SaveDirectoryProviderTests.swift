import Foundation
import Testing
@testable import JuiceScreen

@Suite("SaveDirectoryProvider")
struct SaveDirectoryProviderTests {

    private func makeTempRoot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Creates the date subfolder under the configured root and returns its URL")
    func createsDateFolder() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = SaveDirectoryProvider(rootDirectory: root, filenameGenerator: FilenameGenerator())
        let date = Date()
        let folder = try provider.directory(for: date)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
        // Folder name matches FilenameGenerator's dateSubfolderName output
        let expectedName = FilenameGenerator().dateSubfolderName(for: date)
        #expect(folder.lastPathComponent == expectedName)
    }

    @Test("Idempotent: calling twice for same date returns same path and does not error")
    func idempotent() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = SaveDirectoryProvider(rootDirectory: root, filenameGenerator: FilenameGenerator())
        let date = Date()
        let a = try provider.directory(for: date)
        let b = try provider.directory(for: date)
        #expect(a == b)
    }

    @Test("Creates the root directory if absent")
    func createsRootIfMissing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)/Pictures/JuiceScreen", isDirectory: true)
        defer {
            // Clean up a couple of levels
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent())
        }

        let provider = SaveDirectoryProvider(rootDirectory: root, filenameGenerator: FilenameGenerator())
        let folder = try provider.directory(for: Date())

        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
