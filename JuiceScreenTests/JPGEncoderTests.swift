import AppKit
import Testing
@testable import JuiceScreen

@Suite("JPGEncoder")
struct JPGEncoderTests {

    /// Deterministic 1× test fixture (same pattern as PNGEncoderTests).
    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        color.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return img
    }

    @Test("Output starts with the JPEG SOI marker FF D8")
    func jpegSignature() throws {
        let img = solidImage(width: 8, height: 8, color: .red)
        let data = try JPGEncoder.encode(img, quality: 0.9)
        let prefix: [UInt8] = [0xFF, 0xD8]
        #expect(Array(data.prefix(2)) == prefix)
    }

    @Test("Higher quality produces equal-or-larger file than lower quality")
    func qualityImpactsSize() throws {
        let img = solidImage(width: 64, height: 64, color: .blue)
        let high = try JPGEncoder.encode(img, quality: 0.95)
        let low  = try JPGEncoder.encode(img, quality: 0.10)
        #expect(high.count >= low.count)
    }

    @Test("Throws on zero-size image")
    func zeroSize() {
        let bad = NSImage(size: .zero)
        #expect(throws: JPGEncoderError.self) {
            _ = try JPGEncoder.encode(bad, quality: 0.9)
        }
    }
}
