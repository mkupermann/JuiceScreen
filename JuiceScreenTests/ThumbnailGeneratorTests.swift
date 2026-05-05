import AppKit
import Testing
@testable import JuiceScreen

@Suite("ThumbnailGenerator")
struct ThumbnailGeneratorTests {

    /// Deterministic 1× test fixture (matches Plan 2/3 PNG/JPG encoder pattern).
    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
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

    @Test("Output starts with JPEG signature")
    func jpegSignature() throws {
        let img = solidImage(width: 1024, height: 768, color: .red)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        #expect(Array(data.prefix(2)) == [0xFF, 0xD8])
    }

    @Test("Wide image scales so longest dimension == 256, aspect preserved")
    func wideAspectFit() throws {
        let img = solidImage(width: 1024, height: 512, color: .blue)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 256)
        #expect(rep.pixelsHigh == 128)
    }

    @Test("Tall image scales so longest dimension == 256")
    func tallAspectFit() throws {
        let img = solidImage(width: 400, height: 800, color: .green)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 128)
        #expect(rep.pixelsHigh == 256)
    }

    @Test("Already-small image is not upscaled")
    func noUpscale() throws {
        let img = solidImage(width: 100, height: 50, color: .yellow)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 100)
        #expect(rep.pixelsHigh == 50)
    }

    @Test("Throws on zero-size image")
    func zeroSize() {
        let bad = NSImage(size: .zero)
        #expect(throws: ThumbnailGeneratorError.self) {
            _ = try ThumbnailGenerator.generate(from: bad, maxDimension: 256)
        }
    }
}
