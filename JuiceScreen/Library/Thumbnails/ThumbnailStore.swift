import AppKit
import Foundation

public struct ThumbnailStore: Sendable {

    private let paths: LibraryPaths
    private let fileManager: FileManager

    public init(paths: LibraryPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    /// Generates a thumbnail for `image` and writes it to `<thumbnails>/<id>.jpg`,
    /// overwriting any existing file. Returns the absolute file path.
    @discardableResult
    public func write(image: NSImage, for id: UUID, maxDimension: Int = 256) throws -> String {
        let data = try ThumbnailGenerator.generate(from: image, maxDimension: maxDimension)
        let url = try paths.thumbnailURL(for: id)
        try data.write(to: url, options: .atomic)
        return url.path
    }

    public func delete(for id: UUID) throws {
        let url = try paths.thumbnailURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func url(for id: UUID) throws -> URL {
        try paths.thumbnailURL(for: id)
    }
}
