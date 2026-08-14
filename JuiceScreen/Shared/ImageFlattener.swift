import AppKit
import Foundation

/// Composites an image onto opaque white.
///
/// PNG carries alpha; JPEG and PDF do not. Leaving the flattening to AppKit
/// produces a **black** background for transparent areas, which is the wrong
/// default for a screenshot tool — so every lossy path flattens explicitly.
public enum ImageFlattener {

    public static func onWhite(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0,
              let ctx = CGContext(
                data: nil,
                width: cg.width,
                height: cg.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return image
        }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(full)
        ctx.draw(cg, in: full)
        guard let flattened = ctx.makeImage() else { return image }
        return NSImage(cgImage: flattened, size: image.size)
    }
}
