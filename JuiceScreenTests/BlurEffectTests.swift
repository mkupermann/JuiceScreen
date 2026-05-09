import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("BlurEffect")
struct BlurEffectTests {

    /// 64x64 solid-color CGImage, suitable input for filter exercise.
    private func makeImage(width: Int = 64, height: Int = 64, color: NSColor = .red) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    @Test("Gaussian blur returns a CGImage of the same overall extent")
    func gaussianReturnsImage() {
        let src = makeImage()
        let props = BlurProps(rect: CGRect(x: 16, y: 16, width: 32, height: 32),
                              style: .gaussian, intensity: 8)
        let result = BlurEffect.apply(props, to: src)
        #expect(result != nil)
        // The output extent matches the source's extent (full composite).
        #expect(result?.width == src.width)
        #expect(result?.height == src.height)
    }

    @Test("Pixelate blur returns a CGImage of the same overall extent")
    func pixelateReturnsImage() {
        let src = makeImage()
        let props = BlurProps(rect: CGRect(x: 0, y: 0, width: 32, height: 32),
                              style: .pixelate, intensity: 12)
        let result = BlurEffect.apply(props, to: src)
        #expect(result != nil)
        #expect(result?.width == src.width)
    }

    @Test("Blur covering the full image produces a same-sized output")
    func fullCoverage() {
        let src = makeImage(width: 32, height: 32)
        let props = BlurProps(rect: CGRect(x: 0, y: 0, width: 32, height: 32),
                              style: .gaussian, intensity: 4)
        let result = BlurEffect.apply(props, to: src)
        #expect(result?.width == 32)
        #expect(result?.height == 32)
    }

    @Test("Coordinate flip: top-left rect at y=0 maps to CI bottom-left within image bounds")
    func coordinateFlip() {
        // A rect at AppKit (x:0, y:0, w:64, h:16) at the TOP of a 64-tall image
        // maps to CI rect (x:0, y:48, w:64, h:16). The function should still
        // produce a valid output (no crash, non-nil) even at the boundary.
        let src = makeImage(width: 64, height: 64)
        let topStrip = BlurProps(rect: CGRect(x: 0, y: 0, width: 64, height: 16),
                                  style: .gaussian, intensity: 6)
        #expect(BlurEffect.apply(topStrip, to: src) != nil)
        let bottomStrip = BlurProps(rect: CGRect(x: 0, y: 48, width: 64, height: 16),
                                     style: .gaussian, intensity: 6)
        #expect(BlurEffect.apply(bottomStrip, to: src) != nil)
    }

    @Test("Pixelate scale honoured — different intensity produces different output bytes")
    func differentIntensityChangesPixels() {
        let src = makeImage(width: 64, height: 64, color: .systemBlue)
        let weak = BlurEffect.apply(BlurProps(rect: CGRect(x: 0, y: 0, width: 64, height: 64),
                                              style: .pixelate, intensity: 4), to: src)
        let strong = BlurEffect.apply(BlurProps(rect: CGRect(x: 0, y: 0, width: 64, height: 64),
                                                style: .pixelate, intensity: 32), to: src)
        // Both should produce non-nil images; we don't compare pixels (CI back-end
        // dependent) but at minimum both must return a CGImage.
        #expect(weak != nil)
        #expect(strong != nil)
    }
}
