import AppKit
import Foundation
import PDFKit

public enum PDFEncoder {

    public enum PDFEncoderError: Error, Equatable {
        case noRepresentations
        case pageCreationFailed
        case zeroSize
        case serializationFailed
    }

    /// Wraps the flattened NSImage as a single-page PDFDocument and returns its data.
    /// Page size in points equals image size in pixels (so a 1× capture renders 1:1).
    public static func encode(_ image: NSImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw PDFEncoderError.zeroSize
        }
        guard !image.representations.isEmpty else {
            throw PDFEncoderError.noRepresentations
        }
        let pixelSize: CGSize
        if let rep = image.representations.first as? NSBitmapImageRep {
            pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            pixelSize = image.size
        }
        let sized = NSImage(size: pixelSize)
        sized.addRepresentations(image.representations)
        guard let page = PDFPage(image: sized) else {
            throw PDFEncoderError.pageCreationFailed
        }
        page.setBounds(CGRect(origin: .zero, size: pixelSize), for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        guard let data = doc.dataRepresentation() else {
            throw PDFEncoderError.serializationFailed
        }
        return data
    }
}
