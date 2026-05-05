import AppKit
import Foundation

/// Writes an `NSImage` to disk as PNG and returns the resulting `CaptureRecord`.
/// Combines `SaveDirectoryProvider` (creates the dated subfolder) and
/// `FilenameGenerator` (produces the filename). On filename collision, appends
/// `-1`, `-2`, … until a free name is found.
public struct CaptureRecordWriter {

    private let saveDirectory: SaveDirectoryProvider
    private let filenameGenerator: FilenameGenerator
    private let fileManager: FileManager

    public init(
        saveDirectory: SaveDirectoryProvider,
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        fileManager: FileManager = .default
    ) {
        self.saveDirectory = saveDirectory
        self.filenameGenerator = filenameGenerator
        self.fileManager = fileManager
    }

    public func write(
        image: NSImage,
        captureType: CaptureType,
        capturedAt: Date,
        sourceApp: String?
    ) throws -> CaptureRecord {
        let folder = try saveDirectory.directory(for: capturedAt)
        let baseName = filenameGenerator.filename(for: capturedAt, extension: "png")
        let url = uniqueURL(in: folder, preferredName: baseName)

        let data = try PNGEncoder.encode(image)
        try data.write(to: url, options: .atomic)

        // Pixel dimensions: prefer the actual encoded representation, fall back to image.size.
        let (pw, ph) = pixelDimensions(of: image)

        return CaptureRecord(
            fileURL: url,
            captureType: captureType,
            capturedAt: capturedAt,
            pixelWidth: pw,
            pixelHeight: ph,
            sourceApp: sourceApp
        )
    }

    // MARK: - Helpers

    private func uniqueURL(in folder: URL, preferredName: String) -> URL {
        let candidate = folder.appendingPathComponent(preferredName)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        let stem = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var n = 1
        while true {
            let suffixed = "\(stem)-\(n).\(ext)"
            let url = folder.appendingPathComponent(suffixed)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            n += 1
        }
    }

    private func pixelDimensions(of image: NSImage) -> (Int, Int) {
        var rect = CGRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return (cg.width, cg.height)
        }
        return (Int(image.size.width), Int(image.size.height))
    }
}
