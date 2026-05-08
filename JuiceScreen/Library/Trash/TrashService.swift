import Foundation

/// Manages move-to-trash, restore, and permanent-delete for capture files
/// under `<captureRoot>/.trash/<captureID>/<basename>`.
public struct TrashService: @unchecked Sendable {

    private let captureRoot: URL
    private let fileManager: FileManager

    public init(captureRoot: URL, fileManager: FileManager = .default) {
        self.captureRoot = captureRoot
        self.fileManager = fileManager
    }

    public var trashRoot: URL {
        captureRoot.appendingPathComponent(".trash", isDirectory: true)
    }

    @discardableResult
    public func moveToTrash(file source: URL, captureID: UUID) throws -> URL {
        let folder = trashRoot.appendingPathComponent(captureID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(source.lastPathComponent, isDirectory: false)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: source, to: dest)
        return dest
    }

    @discardableResult
    public func restore(trashedFile trashed: URL, originalPath: String) throws -> URL {
        let dest = URL(fileURLWithPath: originalPath)
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: trashed, to: dest)
        // Clean up empty per-capture folder
        let captureFolder = trashed.deletingLastPathComponent()
        if let contents = try? fileManager.contentsOfDirectory(atPath: captureFolder.path),
           contents.isEmpty {
            try? fileManager.removeItem(at: captureFolder)
        }
        return dest
    }

    public func permanentlyDelete(trashedFile trashed: URL) throws {
        let captureFolder = trashed.deletingLastPathComponent()
        try fileManager.removeItem(at: trashed)
        if let contents = try? fileManager.contentsOfDirectory(atPath: captureFolder.path),
           contents.isEmpty {
            try? fileManager.removeItem(at: captureFolder)
        }
    }
}
