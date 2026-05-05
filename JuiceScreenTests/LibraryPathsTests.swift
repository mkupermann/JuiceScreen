import Foundation
import Testing
@testable import JuiceScreen

@Suite("LibraryPaths")
struct LibraryPathsTests {

    @Test("appSupportDirectory points at ~/Library/Application Support/JuiceScreen")
    func appSupportPath() throws {
        let paths = LibraryPaths()
        let dir = try paths.appSupportDirectory()
        #expect(dir.path.hasSuffix("Application Support/JuiceScreen"))
    }

    @Test("databaseURL is library.sqlite under appSupportDirectory")
    func dbPath() throws {
        let paths = LibraryPaths()
        let url = try paths.databaseURL()
        #expect(url.lastPathComponent == "library.sqlite")
    }

    @Test("thumbnailsDirectory is thumbnails/ under appSupportDirectory and is created on access")
    func thumbnailsPath() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = LibraryPaths(rootDirectory: tempRoot)
        let dir = try paths.thumbnailsDirectory()
        #expect(dir.lastPathComponent == "thumbnails")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("thumbnailURL(for:) returns <thumbnails>/<uuid>.jpg")
    func thumbnailURL() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let paths = LibraryPaths(rootDirectory: tempRoot)
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let url = try paths.thumbnailURL(for: id)
        #expect(url.lastPathComponent == "11111111-2222-3333-4444-555555555555.jpg")
        #expect(url.path.contains("/thumbnails/"))
    }
}
