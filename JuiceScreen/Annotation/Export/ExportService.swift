import AppKit
import Foundation

@MainActor
public enum ExportService {

    public enum Format: String, Sendable, CaseIterable {
        case png
        case jpg
    }

    public enum ExportError: Error, Equatable {
        case renderFailed
        case writeFailed(String)
    }

    /// Flattens the document and writes it to `destination`.
    public static func export(document: AnnotationDocument, format: Format, jpegQuality: Double, to destination: URL) throws {
        let flattened = try AnnotationRenderer.render(document)
        let data: Data
        switch format {
        case .png:
            data = try PNGEncoder.encode(flattened)
        case .jpg:
            data = try JPGEncoder.encode(flattened, quality: jpegQuality)
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ExportError.writeFailed("\(error)")
        }
    }
}
