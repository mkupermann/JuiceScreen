import AppKit
import CoreGraphics

/// Draws the most recent keystrokes as monochrome chips in the bottom-right corner of the frame.
public enum KeystrokeOverlayRenderer {

    public static let chipHeight: CGFloat = 28
    public static let chipPadding: CGFloat = 8
    public static let chipGap: CGFloat = 6
    public static let cornerInset: CGFloat = 24
    public static let fontSize: CGFloat = 16

    public static func draw(keys: [KeystrokeTracker.Key], frameSize: CGSize, in ctx: CGContext) {
        guard !keys.isEmpty else { return }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        var x = frameSize.width - cornerInset
        let y = cornerInset

        ctx.saveGState()
        defer { ctx.restoreGState() }

        for key in keys.reversed() {
            let attributedString = NSAttributedString(string: key.label, attributes: textAttributes)
            let textSize = attributedString.size()
            let chipWidth = textSize.width + chipPadding * 2
            let chipRect = CGRect(x: x - chipWidth, y: y, width: chipWidth, height: chipHeight)

            ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            let path = CGPath(roundedRect: chipRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()

            // Draw the text via NSGraphicsContext bridge so we get attributed-string drawing
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            attributedString.draw(at: CGPoint(x: chipRect.minX + chipPadding,
                                              y: chipRect.minY + (chipHeight - textSize.height) / 2))
            NSGraphicsContext.restoreGraphicsState()

            x = chipRect.minX - chipGap
        }
    }
}
