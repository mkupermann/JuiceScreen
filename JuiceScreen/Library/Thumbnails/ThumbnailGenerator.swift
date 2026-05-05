import AppKit
import Foundation

public enum ThumbnailGeneratorError: Error, Equatable {
    case zeroSize
    case noBitmapRepresentation
    case encodingFailed
}

/// Pure helper: NSImage → JPG `Data` resized so the longest dimension is at most
/// `maxDimension`. Aspect-fit (no cropping). Already-small images pass through unchanged.
public enum ThumbnailGenerator {

    public static func generate(from image: NSImage, maxDimension: Int = 256, quality: Double = 0.8) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw ThumbnailGeneratorError.zeroSize
        }

        // Compute target pixel dimensions
        var srcRect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &srcRect, context: nil, hints: nil) else {
            throw ThumbnailGeneratorError.noBitmapRepresentation
        }
        let srcWidth = cg.width
        let srcHeight = cg.height

        let scale = min(
            CGFloat(maxDimension) / CGFloat(srcWidth),
            CGFloat(maxDimension) / CGFloat(srcHeight),
            1.0
        )
        let targetWidth = max(1, Int(round(CGFloat(srcWidth) * scale)))
        let targetHeight = max(1, Int(round(CGFloat(srcHeight) * scale)))

        // Render into a fresh NSBitmapImageRep at exact target pixel size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth, pixelsHigh: targetHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            throw ThumbnailGeneratorError.noBitmapRepresentation
        }
        rep.size = NSSize(width: targetWidth, height: targetHeight)

        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw ThumbnailGeneratorError.noBitmapRepresentation
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsCtx.imageInterpolation = .high
        nsCtx.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)]) else {
            throw ThumbnailGeneratorError.encodingFailed
        }
        return data
    }
}
