import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("StitchedImageBuilder")
struct StitchedImageBuilderTests {

    private func makeSolidImage(width: Int, height: Int, brightness: Double) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.setFillColor(NSColor(white: brightness, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    @Test("Initial finalImage is the first frame, unchanged")
    func initialIsFirstFrame() throws {
        let first = makeSolidImage(width: 100, height: 200, brightness: 0.5)
        let builder = StitchedImageBuilder(firstFrame: first)
        let final = try #require(builder.finalImage)
        #expect(final.width == 100)
        #expect(final.height == 200)
    }

    @Test("Appending an offset slice grows the image height by exactly that many pixels")
    func appendGrowsHeight() throws {
        let first = makeSolidImage(width: 100, height: 200, brightness: 0.3)
        let next = makeSolidImage(width: 100, height: 200, brightness: 0.8)
        let builder = StitchedImageBuilder(firstFrame: first)
        builder.append(frame: next, offset: StitchOffset(pixelsScrolled: 50, ssdScore: 100))

        let final = try #require(builder.finalImage)
        #expect(final.width == 100)
        #expect(final.height == 250)   // 200 + 50
    }

    @Test("Multiple appends accumulate")
    func multipleAppends() throws {
        let first = makeSolidImage(width: 100, height: 200, brightness: 0.3)
        let f2 = makeSolidImage(width: 100, height: 200, brightness: 0.5)
        let f3 = makeSolidImage(width: 100, height: 200, brightness: 0.7)
        let builder = StitchedImageBuilder(firstFrame: first)
        builder.append(frame: f2, offset: StitchOffset(pixelsScrolled: 30, ssdScore: 50))
        builder.append(frame: f3, offset: StitchOffset(pixelsScrolled: 40, ssdScore: 50))
        let final = try #require(builder.finalImage)
        #expect(final.height == 270)   // 200 + 30 + 40
    }
}
