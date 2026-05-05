import Foundation

/// Sweeps `<captureRoot>/.trash/` and removes files (and their containing
/// per-capture folders, if empty afterward) older than `maxAgeDays`.
/// Returns the number of files deleted.
public struct TrashGC: Sendable {

    private let captureRoot: URL
    private let maxAgeDays: Int
    private let fileManager: FileManager

    public init(captureRoot: URL, maxAgeDays: Int = 30, fileManager: FileManager = .default) {
        self.captureRoot = captureRoot
        self.maxAgeDays = maxAgeDays
        self.fileManager = fileManager
    }

    public func sweep() async throws -> Int {
        let trashRoot = captureRoot.appendingPathComponent(".trash", isDirectory: true)
        guard fileManager.fileExists(atPath: trashRoot.path) else { return 0 }

        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
        var deletedCount = 0

        let captureFolders = (try? fileManager.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in captureFolders {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let attrs = try? fileManager.attributesOfItem(atPath: file.path)
                let mDate = attrs?[.modificationDate] as? Date ?? Date.distantFuture
                if mDate < cutoff {
                    try fileManager.removeItem(at: file)
                    deletedCount += 1
                }
            }

            // Remove now-empty per-capture folder
            if let remaining = try? fileManager.contentsOfDirectory(atPath: folder.path), remaining.isEmpty {
                try? fileManager.removeItem(at: folder)
            }
        }

        return deletedCount
    }
}
