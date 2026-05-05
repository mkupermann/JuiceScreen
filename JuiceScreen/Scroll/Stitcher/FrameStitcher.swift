import CoreGraphics
import Foundation

/// Pure pixel math: given two consecutive frames from a scroll capture, find the
/// vertical offset (how many pixels the user scrolled) by brute-force SSD over a
/// horizontal mid-strip.
///
/// Algorithm:
/// 1. Convert both frames to grayscale `PixelGrid`s.
/// 2. Pick a single horizontal "anchor" row from the middle of `previous`.
/// 3. For each candidate offset y in [minOffset, maxOffset], compute SSD between
///    that anchor row and the corresponding row in `current` (shifted up by y).
/// 4. The offset with minimum SSD is the detected scroll amount.
///
/// Known failure modes (documented honestly per spec):
/// - Sticky headers/footers: the anchor row may be inside the header strip, which
///   doesn't move when the user scrolls — SSD reports offset = 0 (rejected).
/// - Lazy-loaded content: the row at the new position may have changed pixels
///   (e.g. an image just loaded), inflating SSD past the threshold — returns nil.
/// - Parallax: similar — SSD will be high.
public struct FrameStitcher: Sendable {

    /// Smallest scroll amount we'll consider. Below this, we treat as no-scroll.
    public static let minOffset: Int = 5

    /// Largest scroll amount we'll consider. Beyond this, the user scrolled too fast
    /// for our 10fps capture rate.
    public static let maxOffset: Int = 600

    public init() {}

    /// Detect the vertical scroll offset between `previous` and `current` frames.
    ///
    /// The anchor row is taken from the middle of `previous`. We then search upward
    /// in `previous` (i.e., toward lower row indices) for the same content in `current`,
    /// because scrolling down moves content up in viewport coordinates.
    ///
    /// Returns `nil` when no valid offset is found (no scroll, mismatched sizes,
    /// or images too small to search).
    public func detectOffset(previous: CGImage, current: CGImage) -> StitchOffset? {
        guard let prev = PixelGrid(cgImage: previous),
              let curr = PixelGrid(cgImage: current) else {
            return nil
        }
        guard prev.width == curr.width,
              prev.height == curr.height,
              prev.height > Self.minOffset + 2 else {
            return nil
        }

        // Anchor row: middle of `previous`. When the user scrolls down, content moves
        // up in viewport coordinates. The same content that was at `anchorY` in previous
        // is now at `anchorY - offset` in current (shifted toward the top).
        let anchorY = prev.height / 2
        let maxOff = min(Self.maxOffset, anchorY - 1)

        var bestSSD = Double.infinity
        var bestOffset = 0

        for offset in Self.minOffset...maxOff {
            let candidateY = anchorY - offset
            guard candidateY >= 0, candidateY < curr.height else { continue }
            let ssd = prev.rowSSD(y1: anchorY, other: curr, y2: candidateY)
            if ssd < bestSSD {
                bestSSD = ssd
                bestOffset = offset
            }
        }

        guard bestOffset > 0 else { return nil }
        return StitchOffset(pixelsScrolled: bestOffset, ssdScore: bestSSD)
    }
}
