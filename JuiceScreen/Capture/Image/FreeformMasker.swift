import CoreGraphics
import Foundation

/// Clips a captured image to an arbitrary path, leaving everything outside the
/// path fully transparent.
///
/// Pure function: no AppKit, no actor isolation, no shared state.
public enum FreeformMasker {

    /// - Parameters:
    ///   - path: The shape to keep, in a **top-left-origin** space of size
    ///     `pathSpaceSize` (i.e. `FreeformSelection.pathInBounds`).
    ///   - pathSpaceSize: The size of that space, in points.
    ///   - image: The captured image, in pixels. May be larger than
    ///     `pathSpaceSize` on Retina displays.
    /// - Returns: A new image of the same pixel dimensions with alpha 0 outside
    ///   the path, or nil if the inputs are degenerate or the context cannot be
    ///   allocated.
    public static func apply(path: CGPath, pathSpaceSize: CGSize, to image: CGImage) -> CGImage? {
        guard pathSpaceSize.width > 0, pathSpaceSize.height > 0,
              image.width > 0, image.height > 0 else {
            return nil
        }

        guard let ctx = maskContext(for: image) else {
            return nil
        }

        // The path is top-left origin, CGContext is bottom-left. Flip once and
        // scale points to pixels in the same transform: a point (x, y) maps to
        // (x * scaleX, height - y * scaleY).
        let scaleX = CGFloat(image.width) / pathSpaceSize.width
        let scaleY = CGFloat(image.height) / pathSpaceSize.height
        var transform = CGAffineTransform(translationX: 0, y: CGFloat(image.height))
            .scaledBy(x: scaleX, y: -scaleY)

        guard let scaledPath = path.copy(using: &transform) else { return nil }

        ctx.addPath(scaledPath)
        ctx.clip()
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// An alpha-carrying context in the source's own colour space, falling back
    /// to Device RGB.
    ///
    /// This is the only place a capture gains alpha, so hardcoding Device RGB
    /// would convert every freeform capture out of the display's profile at
    /// exactly that moment — the same reason `ImageFlattener` was changed to
    /// honour `cg.colorSpace`.
    ///
    /// The retry is not defensive padding: RGB and monochrome spaces can back
    /// an 8-bit `premultipliedLast` context, but CMYK, Lab, XYZ and indexed
    /// ones make `CGContext.init` return nil. Converting such a source into
    /// Device RGB is far better than the alternative, which is `apply`
    /// returning nil and the capture failing outright.
    private static func maskContext(for image: CGImage) -> CGContext? {
        func context(in space: CGColorSpace) -> CGContext? {
            CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        return context(in: space) ?? context(in: CGColorSpaceCreateDeviceRGB())
    }
}
