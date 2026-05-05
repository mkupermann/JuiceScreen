import AppKit
import Foundation

public enum PNGEncoderError: Error, Equatable {
    case zeroSize
    case noBitmapRepresentation
    case encodingFailed
}

/// Pure-function helper: NSImage → PNG Data. Used by `CaptureRecordWriter`
/// (production) and tests directly.
///
/// Encoding strategy: prefer the existing NSBitmapImageRep on the image (which
/// for screen captures wraps the full-resolution CGImage from ScreenCaptureKit
/// and preserves Retina pixel data). Falls back to extracting a fresh CGImage
/// and wrapping it in a new NSBitmapImageRep — this path is what test fixtures
/// built via `NSImage(size:)` + `lockFocus` exercise.
public enum PNGEncoder {

    public static func encode(_ image: NSImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw PNGEncoderError.zeroSize
        }

        if let rep = image.representations.first as? NSBitmapImageRep,
           let data = rep.representation(using: .png, properties: [:]) {
            return data
        }

        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw PNGEncoderError.noBitmapRepresentation
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw PNGEncoderError.encodingFailed
        }
        return data
    }
}
