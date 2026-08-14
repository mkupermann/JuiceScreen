import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FreeformMasker")
struct FreeformMaskerTests {

    /// Opaque red image of the given pixel size.
    private func redImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// RGBA of one pixel, addressed from the TOP-LEFT of the image.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let i = (y * image.width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    /// Top-left quadrant, in a 100x100 top-left-origin path space.
    private var topLeftQuadrant: CGPath {
        CGPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50), transform: nil)
    }

    @Test("Pixels inside the path stay opaque, pixels outside become transparent")
    func insideOpaqueOutsideTransparent() throws {
        let source = redImage(width: 100, height: 100)
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 100, height: 100), to: source)
        )
        #expect(pixel(masked, x: 10, y: 10).a == 255)
        #expect(pixel(masked, x: 90, y: 90).a == 0)
    }

    @Test("The mask is not vertically mirrored")
    func noVerticalMirror() throws {
        // Asymmetric on purpose: a mirrored mask would keep the BOTTOM-left
        // quadrant instead, and a symmetric shape would hide the bug entirely.
        let source = redImage(width: 100, height: 100)
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 100, height: 100), to: source)
        )
        #expect(pixel(masked, x: 10, y: 10).a == 255)   // top-left: kept
        #expect(pixel(masked, x: 10, y: 90).a == 0)     // bottom-left: dropped
        #expect(pixel(masked, x: 90, y: 10).a == 0)     // top-right: dropped
    }

    @Test("Path points are scaled to image pixels (Retina 2:1)")
    func retinaScale() throws {
        let source = redImage(width: 200, height: 200)
        // Same quadrant, but the path space is 100x100 points against a 200x200
        // pixel image, so the kept area must cover pixels 0..<100.
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 100, height: 100), to: source)
        )
        #expect(pixel(masked, x: 20, y: 20).a == 255)
        #expect(pixel(masked, x: 120, y: 20).a == 0)
        #expect(pixel(masked, x: 20, y: 120).a == 0)
    }

    @Test("Output keeps the source pixel dimensions")
    func dimensionsPreserved() throws {
        let source = redImage(width: 64, height: 48)
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 64, height: 48), to: source)
        )
        #expect(masked.width == 64)
        #expect(masked.height == 48)
    }

    @Test("Zero-sized path space returns nil rather than dividing by zero")
    func zeroPathSpace() {
        let source = redImage(width: 10, height: 10)
        #expect(FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: .zero, to: source) == nil)
    }
}
