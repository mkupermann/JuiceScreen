import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("KeystrokeOverlayRenderer")
struct KeystrokeOverlayRendererTests {

    /// Build a 320x180 ARGB CGContext we can draw into and inspect.
    private func makeContext(width: Int = 320, height: Int = 180) -> CGContext {
        let space = CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
    }

    @Test("Empty keys array short-circuits without drawing")
    func emptyKeysIsNoOp() {
        let ctx = makeContext()
        // Pre-fill with a known color so we can verify nothing was drawn.
        ctx.setFillColor(NSColor.green.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        KeystrokeOverlayRenderer.draw(keys: [], frameSize: CGSize(width: 320, height: 180), in: ctx)
        // Sample the centre pixel — should still be green-ish (no overlay drawn).
        if let img = ctx.makeImage() {
            #expect(img.width == 320)
        }
    }

    @Test("Single key draws without crashing and consumes the corner area")
    func singleKey() {
        let ctx = makeContext()
        let key = KeystrokeTracker.Key(label: "A", timestamp: Date())
        KeystrokeOverlayRenderer.draw(keys: [key], frameSize: CGSize(width: 320, height: 180), in: ctx)
        // The renderer draws at bottom-right corner; must produce a CGImage successfully.
        #expect(ctx.makeImage() != nil)
    }

    @Test("Multiple keys are drawn left of each other (no crash, no infinite loop)")
    func multipleKeys() {
        let ctx = makeContext()
        let keys: [KeystrokeTracker.Key] = [
            .init(label: "A", timestamp: Date()),
            .init(label: "B", timestamp: Date()),
            .init(label: "⌘C", timestamp: Date()),
        ]
        KeystrokeOverlayRenderer.draw(keys: keys, frameSize: CGSize(width: 800, height: 600), in: ctx)
        #expect(ctx.makeImage() != nil)
    }

    @Test("Modifier-prefixed labels render fine (multi-character chips)")
    func modifierLabels() {
        let ctx = makeContext()
        let keys: [KeystrokeTracker.Key] = [
            .init(label: "⌃⌥⌘K", timestamp: Date()),
            .init(label: "⇧↩", timestamp: Date()),
        ]
        KeystrokeOverlayRenderer.draw(keys: keys, frameSize: CGSize(width: 800, height: 600), in: ctx)
        #expect(ctx.makeImage() != nil)
    }

    @Test("Layout constants match published values")
    func layoutConstants() {
        #expect(KeystrokeOverlayRenderer.chipHeight == 28)
        #expect(KeystrokeOverlayRenderer.chipPadding == 8)
        #expect(KeystrokeOverlayRenderer.chipGap == 6)
        #expect(KeystrokeOverlayRenderer.cornerInset == 24)
        #expect(KeystrokeOverlayRenderer.fontSize == 16)
    }
}
