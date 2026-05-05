import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("PNGEncoder")
struct PNGEncoderTests {

    /// Builds a deterministic-pixel-size NSImage by drawing into a 1× NSBitmapImageRep.
    /// Avoids `lockFocus` which produces 2× backing on Retina screens and would make
    /// pixel-dimension assertions display-dependent.
    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        color.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    @Test("Encodes a small solid-color image and returns PNG bytes starting with the PNG signature")
    func pngSignature() throws {
        let img = solidImage(width: 4, height: 4, color: .red)
        let data = try PNGEncoder.encode(img)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let prefix = Array(data.prefix(signature.count))
        #expect(prefix == signature)
    }

    @Test("Round-trip: encode then decode produces an image with the same pixel dimensions")
    func roundTripDimensions() throws {
        let original = solidImage(width: 17, height: 11, color: .blue)
        let data = try PNGEncoder.encode(original)
        guard let rep = NSBitmapImageRep(data: data) else {
            Issue.record("Failed to decode PNG data back into NSBitmapImageRep")
            return
        }
        #expect(rep.pixelsWide == 17)
        #expect(rep.pixelsHigh == 11)
    }

    @Test("Throws on a zero-size image")
    func zeroSize() {
        let bad = NSImage(size: .zero)
        #expect(throws: PNGEncoderError.self) {
            _ = try PNGEncoder.encode(bad)
        }
    }
}
