import Foundation

public struct OCRSidecarStore: @unchecked Sendable {

    private let paths: LibraryPaths
    private let fileManager: FileManager

    public init(paths: LibraryPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func write(_ result: OCRResult, for id: UUID) throws {
        let url = try paths.ocrSidecarURL(for: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(result)
        try data.write(to: url, options: .atomic)
    }

    public func read(for id: UUID) throws -> OCRResult? {
        let url = try paths.ocrSidecarURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(OCRResult.self, from: data)
    }

    public func delete(for id: UUID) throws {
        let url = try paths.ocrSidecarURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
