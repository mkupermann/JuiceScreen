import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("ImageFlattener")
struct ImageFlattenerTests {

    /// A 20x20 image: left half opaque red, right half fully transparent.
    private func halfTransparentImage() -> NSImage {
        let ctx = CGContext(
            data: nil, width: 20, height: 20,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1, 0, 0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 20, height: 20))
    }

    private func pixel(_ image: NSImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        let i = (y * cg.width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    @Test("Transparent areas become white, not black")
    func transparentBecomesWhite() {
        let flat = ImageFlattener.onWhite(halfTransparentImage())
        let right = pixel(flat, x: 15, y: 10)
        #expect(right.a == 255)
        #expect(right.r == 255)
        #expect(right.g == 255)
        #expect(right.b == 255)
    }

    @Test("Opaque areas are untouched")
    func opaqueUnchanged() {
        let flat = ImageFlattener.onWhite(halfTransparentImage())
        let left = pixel(flat, x: 5, y: 10)
        #expect(left.r == 255)
        #expect(left.g == 0)
        #expect(left.b == 0)
        #expect(left.a == 255)
    }

    @Test("Pixel dimensions are preserved")
    func dimensionsPreserved() {
        let flat = ImageFlattener.onWhite(halfTransparentImage())
        let cg = flat.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        #expect(cg.width == 20)
        #expect(cg.height == 20)
    }

    @Test("JPGEncoder renders transparent source areas white")
    func jpgIsWhiteNotBlack() throws {
        let data = try JPGEncoder.encode(halfTransparentImage(), quality: 1.0)
        let decoded = NSImage(data: data)!
        let right = pixel(decoded, x: 15, y: 10)
        // JPEG is lossy — assert "bright", not exactly 255.
        #expect(right.r > 240)
        #expect(right.g > 240)
        #expect(right.b > 240)
    }

    @Test("PNGEncoder preserves the alpha channel")
    func pngKeepsAlpha() throws {
        let data = try PNGEncoder.encode(halfTransparentImage())
        let decoded = NSImage(data: data)!
        #expect(pixel(decoded, x: 15, y: 10).a == 0)     // transparent half stays transparent
        #expect(pixel(decoded, x: 5, y: 10).a == 255)    // opaque half stays opaque
    }

    @Test("ThumbnailGenerator renders transparent areas white, not black")
    func thumbnailIsWhiteNotBlack() throws {
        let data = try ThumbnailGenerator.generate(from: halfTransparentImage(), maxDimension: 20, quality: 1.0)
        let decoded = NSImage(data: data)!
        let right = pixel(decoded, x: 15, y: 10)
        #expect(right.r > 240)
        #expect(right.g > 240)
        #expect(right.b > 240)
    }

    /// Opaque, alpha-free input must never enter the flatten path at all.
    /// Pre-fix, `onWhite` unconditionally redrew every image into a Device
    /// RGB context, so an sRGB-tagged opaque image would come out Device
    /// RGB — a colour-space identity change with no purpose, since nothing
    /// needed flattening. Post-fix, the alpha gate returns it untouched.
    @Test("Opaque image is returned untouched, in its own colour space")
    func opaqueImageIsReturnedUntouchedInItsOwnColorSpace() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: 20, height: 20,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        ctx.setFillColor(CGColor(colorSpace: srgb, components: [0.2, 0.6, 0.4, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let opaqueImage = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 20, height: 20))

        let flat = ImageFlattener.onWhite(opaqueImage)
        let resultSpace = flat.cgImage(forProposedRect: nil, context: nil, hints: nil)!.colorSpace
        #expect(resultSpace?.name == CGColorSpace.sRGB)
    }

    /// Flattening alpha-carrying input must preserve the source's colour
    /// space rather than hardcoding Device RGB — that hardcoding is wrong
    /// for the wide-gamut profiles real captures carry once they gain alpha.
    @Test("Flattened output keeps the source's colour space")
    func flattenedOutputKeepsSourceColorSpace() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: 20, height: 20,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(colorSpace: srgb, components: [1, 0, 0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        let halfTransparentSRGBImage = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 20, height: 20))

        let flat = ImageFlattener.onWhite(halfTransparentSRGBImage)
        let resultCG = flat.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        #expect(resultCG.colorSpace?.name == CGColorSpace.sRGB)
        let right = pixel(flat, x: 15, y: 10)
        #expect(right.r == 255)
        #expect(right.g == 255)
        #expect(right.b == 255)
        #expect(right.a == 255)
    }
}
