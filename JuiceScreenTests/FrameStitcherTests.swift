import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FrameStitcher")
struct FrameStitcherTests {

    /// Builds a CGImage of `height` rows where PixelGrid row `r` has a distinct gray value
    /// derived from `(seedRow + r) % 100 * 2 + 30`. Filling the CGContext with reversed y so
    /// that PixelGrid row 0 (top-left origin) maps to the intended value.
    ///
    /// The value formula uses a step of 2, giving per-row differences large enough that
    /// the SSD threshold (500 000) reliably rejects false-positive matches while still
    /// producing an exact (SSD = 0) match when `seedRow` is shifted by the scroll offset.
    private func makeRowSeededImage(width: Int, height: Int, seedRow: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        for y in 0..<height {
            // Reversed fill: CGContext y=(height-1-y) so that PixelGrid row y (top-left) equals
            // (seedRow + y) % 100 * 2 + 30, preserving the shift property needed by the tests.
            let v = Double((seedRow + y) % 100 * 2 + 30) / 255.0
            ctx.setFillColor(NSColor(white: v, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: height - 1 - y, width: width, height: 1))
        }
        return ctx.makeImage()!
    }

    @Test("Detects a clear scroll offset of N pixels between two synthetic frames")
    func detectScroll() throws {
        // Frame A starts at seed=0 (PixelGrid rows 0..99 have values derived from 0..99)
        // Frame B starts at seed=20 (PixelGrid rows 0..99 have values derived from 20..119)
        // Because seed_B = seed_A + 20, row (anchorY - 20) of B matches row anchorY of A exactly.
        // Interpretation: content that was at row 50 in A is now at row 30 in B — user scrolled down 20px.
        let frameA = makeRowSeededImage(width: 100, height: 100, seedRow: 0)
        let frameB = makeRowSeededImage(width: 100, height: 100, seedRow: 20)

        let stitcher = FrameStitcher()
        let offset = stitcher.detectOffset(previous: frameA, current: frameB)
        let resolved = try #require(offset)
        #expect(resolved.pixelsScrolled == 20)
        #expect(resolved.isUsable)
    }

    @Test("Returns nil or unusable for unrelated frames")
    func unrelatedFrames() {
        // A seeded image vs a checker-board pattern share no content — SSD will be very high
        // at every candidate offset.
        let a = makeRowSeededImage(width: 100, height: 100, seedRow: 0)
        let bSize = 100
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: bSize, height: bSize,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        for y in 0..<bSize {
            for x in 0..<bSize {
                let v: Double = ((x + y) % 2 == 0) ? 1.0 : 0.0
                ctx.setFillColor(NSColor(white: v, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let b = ctx.makeImage()!
        let stitcher = FrameStitcher()
        let offset = stitcher.detectOffset(previous: a, current: b)
        if let result = offset {
            #expect(!result.isUsable)
        }
    }

    @Test("Returns nil or unusable for identical frames (no scroll happened)")
    func identicalFrames() {
        // Same image vs itself: the true minimum SSD is at offset = 0, which is outside the
        // search range [minOffset, maxOffset]. The best in-range SSD exceeds the usability
        // threshold, so isUsable is false.
        let img = makeRowSeededImage(width: 100, height: 100, seedRow: 50)
        let stitcher = FrameStitcher()
        let offset = stitcher.detectOffset(previous: img, current: img)
        if let result = offset {
            #expect(!result.isUsable)
        }
    }
}
