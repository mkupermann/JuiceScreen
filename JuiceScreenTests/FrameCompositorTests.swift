import AppKit
import CoreVideo
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

    // MARK: - composite() — Core Image rebuild (1.1.0)
    //
    // The CGContext-on-pixel-buffer-base-address approach intermittently corrupted
    // captured frames (1.0.7 CHANGELOG explains why). The replacement path:
    //   1. Render overlays to a fresh in-memory bitmap (we own the bytes).
    //   2. Wrap as CIImage; composite over CIImage(cvPixelBuffer:) of the source.
    //   3. Render the composite to a freshly-allocated output CVPixelBuffer.
    // The source buffer is only READ — never locked-for-write, never drawn-into.

    /// Builds a 200x200 BGRA pixel buffer filled with `fill` (0–255 per channel, A=255).
    private func makeBuffer(width: Int = 200, height: Int = 200,
                            fillR: UInt8 = 51, fillG: UInt8 = 51, fillB: UInt8 = 51) -> CVPixelBuffer {
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let off = y * bpr + x * 4
                base[off + 0] = fillB  // B
                base[off + 1] = fillG  // G
                base[off + 2] = fillR  // R
                base[off + 3] = 255    // A
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// Reads (r, g, b) at (x, y) — top-left origin, normalized 0..1.
    private func pixelColor(of buffer: CVPixelBuffer, x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let off = y * bpr + x * 4
        return (CGFloat(base[off + 2]) / 255, CGFloat(base[off + 1]) / 255, CGFloat(base[off + 0]) / 255)
    }

    @Test("composite returns nil (pass-through signal) when no overlay flags are enabled")
    func compositePassThrough() {
        let compositor = FrameCompositor(
            cursorTracker: CursorTracker(),
            clickTracker: ClickTracker(),
            keystrokeTracker: KeystrokeTracker()
        )
        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = false
        options.showClickPulse = false
        options.showKeystrokes = false
        let input = makeBuffer()
        #expect(compositor.composite(input, options: options, screenOrigin: .zero) == nil)
    }

    @Test("composite returns a fresh same-size buffer when overlays are enabled")
    func compositeReturnsBuffer() {
        let cursor = CursorTracker()
        cursor._setLocationForTesting(CGPoint(x: 100, y: 100))
        let compositor = FrameCompositor(
            cursorTracker: cursor,
            clickTracker: ClickTracker(),
            keystrokeTracker: KeystrokeTracker()
        )
        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = true
        let input = makeBuffer()
        guard let output = compositor.composite(input, options: options, screenOrigin: .zero) else {
            Issue.record("composite returned nil; expected non-nil"); return
        }
        #expect(CVPixelBufferGetWidth(output) == 200)
        #expect(CVPixelBufferGetHeight(output) == 200)
        // Output must be a NEW buffer — same identity would mean we mutated the source.
        #expect(input !== output)
    }

    @Test("composite output has the cursor ring rendered at the cursor location (top-left coord)")
    func compositeCursorRingAppears() {
        let cursor = CursorTracker()
        cursor._setLocationForTesting(CGPoint(x: 100, y: 100))
        let compositor = FrameCompositor(
            cursorTracker: cursor,
            clickTracker: ClickTracker(),
            keystrokeTracker: KeystrokeTracker()
        )
        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = true
        options.showClickPulse = false
        options.showKeystrokes = false
        let input = makeBuffer(fillR: 51, fillG: 51, fillB: 51)   // dark grey
        guard let output = compositor.composite(input, options: options, screenOrigin: .zero) else {
            Issue.record("composite returned nil; expected non-nil"); return
        }
        // Ring radius 14, stroke 3 → sampling (114, 100) hits the right edge of the ring.
        let (r, g, _) = pixelColor(of: output, x: 114, y: 100)
        #expect(r > 0.6, "expected ring pixel red high (yellow ring), got r=\(r)")
        #expect(g > 0.6, "expected ring pixel green high (yellow ring), got g=\(g)")
    }

    @Test("composite does NOT mutate the input buffer (the bug 1.0.7 CHANGELOG warned about)")
    func compositeDoesNotMutateInput() {
        let cursor = CursorTracker()
        cursor._setLocationForTesting(CGPoint(x: 100, y: 100))
        let compositor = FrameCompositor(
            cursorTracker: cursor,
            clickTracker: ClickTracker(),
            keystrokeTracker: KeystrokeTracker()
        )
        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = true
        let input = makeBuffer(fillR: 51, fillG: 51, fillB: 51)
        let before = pixelColor(of: input, x: 114, y: 100)
        _ = compositor.composite(input, options: options, screenOrigin: .zero)
        let after = pixelColor(of: input, x: 114, y: 100)
        #expect(before.r == after.r && before.g == after.g && before.b == after.b,
                "Input buffer was mutated — composite must produce a NEW buffer, never overwrite the source.")
    }

    @Test("composite respects screenOrigin: cursor at screen (300, 100) with origin (200, 0) draws at frame (100, 100)")
    func compositeRespectsScreenOrigin() {
        let cursor = CursorTracker()
        cursor._setLocationForTesting(CGPoint(x: 300, y: 100))
        let compositor = FrameCompositor(
            cursorTracker: cursor,
            clickTracker: ClickTracker(),
            keystrokeTracker: KeystrokeTracker()
        )
        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = true
        let input = makeBuffer()
        guard let output = compositor.composite(input, options: options, screenOrigin: CGPoint(x: 200, y: 0)) else {
            Issue.record("composite returned nil"); return
        }
        // Same expectation as compositeCursorRingAppears — ring lands at frame (100, 100).
        let (r, g, _) = pixelColor(of: output, x: 114, y: 100)
        #expect(r > 0.6 && g > 0.6, "ring should appear at frame (100,100) when origin shifts cursor by (200,0)")
    }
}
