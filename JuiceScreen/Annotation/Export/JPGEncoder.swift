import AppKit

public enum JPGEncoderError: Error, Equatable {
    case zeroSize
    case noBitmapRepresentation
    case encodingFailed
}

public enum JPGEncoder {

    public static func encode(_ image: NSImage, quality: Double) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw JPGEncoderError.zeroSize
        }

        if let rep = image.representations.first as? NSBitmapImageRep,
           let data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)]) {
            return data
        }

        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw JPGEncoderError.noBitmapRepresentation
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)]) else {
            throw JPGEncoderError.encodingFailed
        }
        return data
    }
}
