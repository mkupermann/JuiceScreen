import AppKit
import CoreGraphics
import Foundation

/// Draws all enabled overlays onto a frame's CGContext. Pure per-frame composer:
/// reads from the trackers (which run on their own queues) and renders.
public final class FrameCompositor: @unchecked Sendable {

    private let cursorTracker: CursorTracker
    private let clickTracker: ClickTracker
    private let keystrokeTracker: KeystrokeTracker

    public init(cursorTracker: CursorTracker, clickTracker: ClickTracker, keystrokeTracker: KeystrokeTracker) {
        self.cursorTracker = cursorTracker
        self.clickTracker = clickTracker
        self.keystrokeTracker = keystrokeTracker
    }

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
}
