import Foundation

/// Computes (and creates on first access) the JuiceScreen library paths under
/// `~/Library/Application Support/JuiceScreen/`. Tests can inject a different
/// `rootDirectory` to redirect into a temp directory.
public struct LibraryPaths: @unchecked Sendable {

    private let rootDirectoryOverride: URL?
    private let fileManager: FileManager

    public init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.rootDirectoryOverride = rootDirectory
        self.fileManager = fileManager
    }

    public func appSupportDirectory() throws -> URL {
        if let override = rootDirectoryOverride {
            try fileManager.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("JuiceScreen", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func databaseURL() throws -> URL {
        try appSupportDirectory().appendingPathComponent("library.sqlite", isDirectory: false)
    }

    public func thumbnailsDirectory() throws -> URL {
        let dir = try appSupportDirectory().appendingPathComponent("thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func thumbnailURL(for id: UUID) throws -> URL {
        try thumbnailsDirectory()
            .appendingPathComponent("\(id.uuidString).jpg", isDirectory: false)
    }

    public func ocrDirectory() throws -> URL {
        let dir = try appSupportDirectory().appendingPathComponent("ocr", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func ocrSidecarURL(for id: UUID) throws -> URL {
        try ocrDirectory().appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }
}
