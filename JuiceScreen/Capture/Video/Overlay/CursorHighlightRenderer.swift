import AppKit
import CoreGraphics

/// Renders a translucent yellow ring around the cursor position into a `CGContext`.
/// Pure function — no state.
public enum CursorHighlightRenderer {

    public static let ringDiameter: CGFloat = 28
    public static let ringStrokeWidth: CGFloat = 3
    public static let ringColor = NSColor.systemYellow.withAlphaComponent(0.85)

    /// Draws a ring centered at `point` (in CGContext coordinates — caller is responsible
    /// for converting from screen coordinates to frame-pixel coordinates).
    public static func draw(at point: CGPoint, in ctx: CGContext) {
        let radius = ringDiameter / 2
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: ringDiameter,
            height: ringDiameter
        )
        ctx.saveGState()
        ctx.setStrokeColor(ringColor.cgColor)
        ctx.setLineWidth(ringStrokeWidth)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }
}
