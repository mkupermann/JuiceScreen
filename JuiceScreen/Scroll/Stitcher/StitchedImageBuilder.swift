import CoreGraphics
import Foundation

/// Accumulates frames into a growing tall image. Each `append` adds the bottom
/// `offset.pixelsScrolled` rows of the new frame to the bottom of the running image.
///
/// Implementation: stores a list of (CGImage, sliceOffset) and reconstructs the
/// final image in `finalImage` by drawing into a fresh `CGContext` of the
/// accumulated height. Called once at end-of-session, so the cost of rebuilding is
/// amortized — keeps the per-frame append O(1).
public final class StitchedImageBuilder: @unchecked Sendable {

    private struct Slice {
        let image: CGImage
        /// How many bottom rows of `image` to take. Equal to `offset.pixelsScrolled`
        /// for non-first slices; equal to full height for the first frame.
        let bottomRows: Int
    }

    private let lock = NSLock()
    private var slices: [Slice] = []
    private let frameWidth: Int

    public init(firstFrame: CGImage) {
        self.frameWidth = firstFrame.width
        slices.append(Slice(image: firstFrame, bottomRows: firstFrame.height))
    }

    public func append(frame: CGImage, offset: StitchOffset) {
        guard frame.width == frameWidth, offset.pixelsScrolled > 0 else { return }
        let rows = min(offset.pixelsScrolled, frame.height)
        lock.lock()
        slices.append(Slice(image: frame, bottomRows: rows))
        lock.unlock()
    }

    /// Total height the final image would have, given the slices accumulated so far.
    public var totalHeight: Int {
        lock.lock(); defer { lock.unlock() }
        return slices.reduce(0) { $0 + $1.bottomRows }
    }

    public var frameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return slices.count
    }

    public var finalImage: CGImage? {
        lock.lock()
        let snapshot = slices
        lock.unlock()

        let totalH = snapshot.reduce(0) { $0 + $1.bottomRows }
        guard totalH > 0, frameWidth > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: frameWidth,
            height: totalH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // CGContext origin is bottom-left. We want the first slice at the TOP of
        // the final image. So we draw slices from index 0 → N at decreasing y.
        var yCursor = totalH

        for slice in snapshot {
            let h = slice.bottomRows
            yCursor -= h
            // Take the BOTTOM `bottomRows` rows of slice.image and draw at (0, yCursor).
            // CGImage.cropping uses top-left convention; we crop the bottom strip.
            let cropY = slice.image.height - h
            let cropRect = CGRect(x: 0, y: cropY, width: frameWidth, height: h)
            guard let cropped = slice.image.cropping(to: cropRect) else { continue }
            ctx.draw(cropped, in: CGRect(x: 0, y: yCursor, width: frameWidth, height: h))
        }

        return ctx.makeImage()
    }
}
