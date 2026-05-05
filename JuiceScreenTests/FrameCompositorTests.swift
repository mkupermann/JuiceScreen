import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FrameCompositor")
struct FrameCompositorTests {

    /// Draws into a fresh context and returns the resulting CGImage.
    private func renderToFixture(_ block: (CGContext, CGSize) -> Void, size: CGSize = CGSize(width: 200, height: 200)) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        // Fill with a known background
        ctx.setFillColor(NSColor.darkGray.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        block(ctx, size)
        return ctx.makeImage()
    }

    @Test("Empty options: composer draws no overlays")
    func emptyOptions() {
        let cursor = CursorTracker()
        let click = ClickTracker()
        let keys = KeystrokeTracker()
        cursor._setLocationForTesting(CGPoint(x: 100, y: 100))

        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = false
        options.showClickPulse = false
        options.showKeystrokes = false

        let composer = FrameCompositor(cursorTracker: cursor, clickTracker: click, keystrokeTracker: keys)

        let img = renderToFixture { ctx, size in
            composer.draw(options: options, frameSize: size, screenOrigin: .zero, in: ctx)
        }
        #expect(img != nil)
        // Pixel at center should still be the dark-gray background (no cursor ring drawn)
        // Spot-check by using NSBitmapImageRep
        let rep = NSBitmapImageRep(cgImage: img!)
        let color = rep.colorAt(x: 100, y: 100)
        #expect(color != nil)
        // dark gray rgb(85, 85, 85) approximately — alpha may be 1.0
        #expect((color?.redComponent ?? 1.0) < 0.5)
    }

    @Test("Cursor highlight enabled: ring is drawn around cursor location (in screen coords)")
    func cursorRing() {
        let cursor = CursorTracker()
        let click = ClickTracker()
        let keys = KeystrokeTracker()
        // Cursor is at screen point (100, 100); screenOrigin is (0,0) so frame point is also (100,100)
        cursor._setLocationForTesting(CGPoint(x: 100, y: 100))

        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = true
        options.showClickPulse = false
        options.showKeystrokes = false

        let composer = FrameCompositor(cursorTracker: cursor, clickTracker: click, keystrokeTracker: keys)

        let img = renderToFixture { ctx, size in
            composer.draw(options: options, frameSize: size, screenOrigin: .zero, in: ctx)
        }
        #expect(img != nil)
        // Check that a pixel on the ring perimeter shifted toward yellow
        let rep = NSBitmapImageRep(cgImage: img!)
        // 14pt right of cursor center is on the ring (radius 14, stroke 3)
        let onRing = rep.colorAt(x: 114, y: 100)
        #expect(onRing != nil)
        let r = onRing!.redComponent
        let g = onRing!.greenComponent
        // yellow → high R + high G + low B
        #expect(r > 0.6 && g > 0.6)
    }
}
