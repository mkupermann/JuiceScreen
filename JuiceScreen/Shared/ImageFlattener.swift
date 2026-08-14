import AppKit
import Foundation

/// Composites an image onto opaque white.
///
/// PNG carries alpha; JPEG and PDF do not. Leaving the flattening to AppKit
/// produces a **black** background for transparent areas, which is the wrong
/// default for a screenshot tool — so every lossy path flattens explicitly.
///
/// Only images that actually carry an alpha channel are touched; opaque
/// input is returned unmodified so this never forces an unwanted colour
/// conversion on captures that had nothing to flatten. If the context this
/// needs cannot be allocated, the fallback degrades to AppKit's default
/// (black) compositing — the failure is logged, not silent.
public enum ImageFlattener {

    private static let log = AppLog.logger(category: "ImageFlattener")

    public static func onWhite(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else {
            return image
        }

        // Confine this function's effect to images that actually carry alpha.
        // Every capture taken before FreeForm is opaque, and redrawing it here
        // would force a ColorSync conversion into the working colour space for
        // no gain — including on the wide-gamut profiles real displays produce.
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }

        guard let ctx = CGContext(
            data: nil,
            width: cg.width,
            height: cg.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cg.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            log.error("Failed to allocate flatten context; falling back to AppKit's default (black) compositing")
            return image
        }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(full)
        ctx.draw(cg, in: full)
        guard let flattened = ctx.makeImage() else {
            log.error("Failed to create flattened image; falling back to AppKit's default (black) compositing")
            return image
        }
        return NSImage(cgImage: flattened, size: image.size)
    }
}
