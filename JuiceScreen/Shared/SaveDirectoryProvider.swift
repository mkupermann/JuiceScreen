import Foundation

/// Ensures the dated capture folder exists under the configured root
/// (default `~/Pictures/JuiceScreen/`) and returns its URL.
///
/// Layout:
///   <root>/2026-05-04/
///   <root>/2026-05-05/
public struct SaveDirectoryProvider: @unchecked Sendable {

    public let rootDirectory: URL
    public let filenameGenerator: FilenameGenerator
    public let fileManager: FileManager

    public init(
        rootDirectory: URL,
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.filenameGenerator = filenameGenerator
        self.fileManager = fileManager
    }

    /// Returns the URL of the date-subfolder, creating it (and any missing intermediates) if needed.
    public func directory(for date: Date) throws -> URL {
        let folder = rootDirectory.appendingPathComponent(
            filenameGenerator.dateSubfolderName(for: date),
            isDirectory: true
        )
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
