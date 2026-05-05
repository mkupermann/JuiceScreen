import AppKit
import Foundation
import PDFKit

@MainActor
public enum ExportService {

    public enum Format: String, Sendable, CaseIterable {
        case png
        case jpg
        case pdf
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
        case .pdf:
            data = try PDFEncoder.encode(flattened)
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ExportError.writeFailed("\(error)")
        }
    }

    /// Maps a file extension (lowercased or not, with or without leading dot) to the matching Format.
    /// Defaults to `.png` if the extension is unknown.
    public static func formatForExtension(_ ext: String) -> Format {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch normalized {
        case "jpg", "jpeg": return .jpg
        case "pdf":         return .pdf
        default:            return .png
        }
    }
}
