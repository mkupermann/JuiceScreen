import Foundation

/// Deletes OCR sidecar JSONs and thumbnail JPGs that no longer have a matching
/// row in the capture library.
///
/// These files live under `~/Library/Application Support/JuiceScreen/` keyed by
/// capture UUID — *outside* the capture folder that `TrashService` manages — so
/// without this sweep they survive "Empty trash" and permanent deletes
/// indefinitely. That includes the OCR sidecar, which is a full text transcript
/// of the captured screen, so leaving them behind is a privacy defect, not just
/// wasted disk.
///
/// Fail-safe by contract: callers must pass the set of known IDs only when the
/// library query actually succeeded. An empty or uncertain set would delete
/// everything, so on any error the caller must skip the sweep, never call it
/// with a partial set.
public struct OrphanReaper: @unchecked Sendable {
    private let paths: LibraryPaths
    private let fileManager: FileManager

    public init(paths: LibraryPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    /// Removes sidecar/thumbnail files whose UUID is not in `knownIDs`.
    /// Returns the number of files deleted.
    @discardableResult
    public func sweep(knownIDs: Set<UUID>) throws -> Int {
        var removed = 0
        removed += reap(directory: try paths.ocrDirectory(), ext: "json", knownIDs: knownIDs)
        removed += reap(directory: try paths.thumbnailsDirectory(), ext: "jpg", knownIDs: knownIDs)
        return removed
    }

    private func reap(directory: URL, ext: String, knownIDs: Set<UUID>) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for url in entries where url.pathExtension == ext {
            let stem = url.deletingPathExtension().lastPathComponent
            // Leave anything whose name is not a bare capture UUID untouched.
            guard let id = UUID(uuidString: stem) else { continue }
            if !knownIDs.contains(id) {
                try? fileManager.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }
}
