import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrashService")
struct TrashServiceTests {

    private func makeTempCaptureRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touchFile(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: url)
    }

    @Test("moveToTrash relocates file under .trash/<uuid>/<basename> and returns new URL")
    func move() throws {
        let captureRoot = makeTempCaptureRoot()
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let original = captureRoot.appendingPathComponent("2026-05-05/JuiceScreen_x.png")
        try touchFile(at: original)

        let id = UUID()
        let svc = TrashService(captureRoot: captureRoot)
        let trashedURL = try svc.moveToTrash(file: original, captureID: id)

        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))
        #expect(trashedURL.path.contains("/.trash/\(id.uuidString)/"))
        #expect(trashedURL.lastPathComponent == "JuiceScreen_x.png")
    }

    @Test("restore moves file from trash back to <captureRoot>/<original date folder>/")
    func restoreFile() throws {
        let captureRoot = makeTempCaptureRoot()
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let original = captureRoot.appendingPathComponent("2026-05-05/JuiceScreen_x.png")
        try touchFile(at: original)

        let id = UUID()
        let svc = TrashService(captureRoot: captureRoot)
        let trashedURL = try svc.moveToTrash(file: original, captureID: id)
        let restored = try svc.restore(trashedFile: trashedURL, originalPath: original.path)

        #expect(FileManager.default.fileExists(atPath: restored.path))
        #expect(restored.path == original.path)
        #expect(!FileManager.default.fileExists(atPath: trashedURL.path))
    }

    @Test("permanentlyDelete removes the file and its containing capture-id folder")
    func permanent() throws {
        let captureRoot = makeTempCaptureRoot()
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let original = captureRoot.appendingPathComponent("2026-05-05/JuiceScreen_x.png")
        try touchFile(at: original)
        let id = UUID()
        let svc = TrashService(captureRoot: captureRoot)
        let trashedURL = try svc.moveToTrash(file: original, captureID: id)
        try svc.permanentlyDelete(trashedFile: trashedURL)

        #expect(!FileManager.default.fileExists(atPath: trashedURL.path))
        let captureFolder = trashedURL.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: captureFolder.path))
    }
}
