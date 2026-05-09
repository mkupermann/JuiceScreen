import AppKit
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// Draws all enabled overlays onto a frame.
///
/// Two paths:
///
/// - `draw(options:frameSize:screenOrigin:in:)` writes overlays directly into a
///   `CGContext` the caller supplies. Used by tests and any caller that owns its
///   own bitmap. Behaviour preserved across versions.
///
/// - `composite(_:options:screenOrigin:)` (added in 1.1.0) takes a captured
///   `CVPixelBuffer`, renders overlays into a separately-allocated bitmap, and
///   uses Core Image's `composited(over:)` to produce a freshly-allocated output
///   `CVPixelBuffer`. The source buffer is **only read** — never locked for write,
///   never drawn into. This avoids the 1.0.5/1.0.6 bug where locking the source
///   buffer's base address while AVAssetWriter held a concurrent reference left
///   the buffer in a state the writer rejected, producing empty MP4s.
public final class FrameCompositor: @unchecked Sendable {

    private let cursorTracker: CursorTracker
    private let clickTracker: ClickTracker
    private let keystrokeTracker: KeystrokeTracker

    /// Reused across frames — `CIContext` is expensive to create. Lazy because
    /// most app code paths never need a CI context (only the recorder does).
    private lazy var ciContext: CIContext = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
    ])

    /// Lazy pool, recreated when frame dimensions change between sessions.
    private var bufferPool: CVPixelBufferPool?
    private var poolDimensions: (width: Int, height: Int)?
    private let poolLock = NSLock()

    public init(cursorTracker: CursorTracker, clickTracker: ClickTracker, keystrokeTracker: KeystrokeTracker) {
        self.cursorTracker = cursorTracker
        self.clickTracker = clickTracker
        self.keystrokeTracker = keystrokeTracker
    }

    // MARK: - draw (legacy CGContext API; preserved for callers + tests)

    /// Draws enabled overlays onto `ctx`. `frameSize` is the pixel size of the frame.
    /// `screenOrigin` is the top-left of the recorded region in global screen coordinates;
    /// pass `.zero` for a full-screen recording starting at the primary display origin.
    public func draw(
        options: VideoRecordingOptions,
        frameSize: CGSize,
        screenOrigin: CGPoint,
        in ctx: CGContext
    ) {
        if options.showCursorHighlight {
            let screenLoc = cursorTracker.currentLocation
            let frameLoc = CGPoint(x: screenLoc.x - screenOrigin.x, y: screenLoc.y - screenOrigin.y)
            // Skip if outside frame
            if frameLoc.x >= 0, frameLoc.y >= 0,
               frameLoc.x <= frameSize.width, frameLoc.y <= frameSize.height {
                CursorHighlightRenderer.draw(at: frameLoc, in: ctx)
            }
        }

        if options.showClickPulse {
            let translated = clickTracker.recentClicks().map { c in
                ClickTracker.Click(
                    location: CGPoint(x: c.location.x - screenOrigin.x, y: c.location.y - screenOrigin.y),
                    timestamp: c.timestamp
                )
            }
            ClickPulseRenderer.draw(clicks: translated, in: ctx)
        }

        if options.showKeystrokes {
            KeystrokeOverlayRenderer.draw(keys: keystrokeTracker.recentKeys(), frameSize: frameSize, in: ctx)
        }
    }

    // MARK: - composite (CVPixelBuffer-safe API; new in 1.1.0)

    /// Composites enabled overlays onto a captured frame and returns a fresh
    /// `CVPixelBuffer`. **Never touches `source`'s base address** — only reads.
    ///
    /// Returns `nil` in two cases the caller treats identically (use the original
    /// `source` buffer):
    /// - All overlay flags are off (no work to do, skip the copy).
    /// - Internal failure (no pool, CI render failed). Recording must continue
    ///   even if a single frame fails to composite.
    public func composite(
        _ source: CVPixelBuffer,
        options: VideoRecordingOptions,
        screenOrigin: CGPoint
    ) -> CVPixelBuffer? {
        guard options.showCursorHighlight || options.showClickPulse || options.showKeystrokes else {
            return nil
        }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)

        guard let overlayCG = renderOverlays(
            options: options,
            frameSize: CGSize(width: width, height: height),
            screenOrigin: screenOrigin
        ) else { return nil }

        // Both inputs are CIImages in CI's coordinate system (bottom-left origin).
        // composited(over:) handles per-pixel alpha blending of the overlay over
        // the captured base, with no access to either source's underlying memory.
        let baseCI = CIImage(cvPixelBuffer: source)
        let overlayCI = CIImage(cgImage: overlayCG)
        let composited = overlayCI.composited(over: baseCI)

        guard let output = makeOutputBuffer(width: width, height: height) else { return nil }
        ciContext.render(composited, to: output)
        return output
    }

    // MARK: - private helpers

    /// Renders enabled overlays into a freshly-allocated 32-bit BGRA bitmap
    /// (transparent background). This is the bitmap composited over the captured
    /// frame; we own its bytes outright — no concurrency with AVAssetWriter.
    ///
    /// Coordinate notes:
    /// - The CGContext is left in CG's default y-bottom orientation so that
    ///   `KeystrokeOverlayRenderer` (which intentionally draws chips in the
    ///   "bottom-right" corner using y=cornerInset) renders to the bottom of
    ///   the eventual video frame, matching its docstring.
    /// - Cursor and click coords are y-flipped from screen (top-left) into CG
    ///   (bottom-left) so that a cursor at screen `(x, 30)` renders at video
    ///   pixel-row 30 from the top, matching what the user sees on-screen.
    private func renderOverlays(
        options: VideoRecordingOptions,
        frameSize: CGSize,
        screenOrigin: CGPoint
    ) -> CGImage? {
        let width = Int(frameSize.width)
        let height = Int(frameSize.height)

        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }

        if options.showCursorHighlight {
            let screen = cursorTracker.currentLocation
            let xInFrame = screen.x - screenOrigin.x
            let yFromTop = screen.y - screenOrigin.y
            // Skip if cursor outside the recorded region
            if xInFrame >= 0, yFromTop >= 0,
               xInFrame <= frameSize.width, yFromTop <= frameSize.height {
                let yInCG = frameSize.height - yFromTop
                CursorHighlightRenderer.draw(at: CGPoint(x: xInFrame, y: yInCG), in: ctx)
            }
        }

        if options.showClickPulse {
            let translated = clickTracker.recentClicks().map { c -> ClickTracker.Click in
                let xInFrame = c.location.x - screenOrigin.x
                let yFromTop = c.location.y - screenOrigin.y
                let yInCG = frameSize.height - yFromTop
                return ClickTracker.Click(
                    location: CGPoint(x: xInFrame, y: yInCG),
                    timestamp: c.timestamp
                )
            }
            ClickPulseRenderer.draw(clicks: translated, in: ctx)
        }

        if options.showKeystrokes {
            // Keystroke renderer is designed for CG y-bottom: chips appear in the
            // bottom-right of the recorded video, matching its public docstring.
            KeystrokeOverlayRenderer.draw(keys: keystrokeTracker.recentKeys(), frameSize: frameSize, in: ctx)
        }

        return ctx.makeImage()
    }

    /// Returns a freshly-allocated `CVPixelBuffer` from a pool sized for the
    /// requested dimensions. Pool is recreated only when dimensions change.
    private func makeOutputBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        poolLock.lock()
        defer { poolLock.unlock() }
        if poolDimensions?.width != width || poolDimensions?.height != height {
            let pixelBufferAttrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ]
            var pool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(nil, nil, pixelBufferAttrs as CFDictionary, &pool)
            guard status == kCVReturnSuccess else { return nil }
            self.bufferPool = pool
            self.poolDimensions = (width, height)
        }
        guard let pool = bufferPool else { return nil }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output)
        return output
    }
}
