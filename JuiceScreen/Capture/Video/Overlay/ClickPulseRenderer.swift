import AppKit
import CoreGraphics

/// Renders an expanding ring at each recent click location, fading out over `ClickTracker.clickLifetime`.
public enum ClickPulseRenderer {

    public static let maxRadius: CGFloat = 36
    public static let strokeWidth: CGFloat = 4
    public static let pulseColor = NSColor.systemBlue

    public static func draw(clicks: [ClickTracker.Click], in ctx: CGContext, now: Date = Date()) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        for click in clicks {
            let age = now.timeIntervalSince(click.timestamp)
            let progress = min(max(age / ClickTracker.clickLifetime, 0), 1)
            let radius = maxRadius * CGFloat(progress)
            let alpha = (1.0 - CGFloat(progress)) * 0.85
            let rect = CGRect(
                x: click.location.x - radius,
                y: click.location.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            ctx.setStrokeColor(pulseColor.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(strokeWidth)
            ctx.strokeEllipse(in: rect)
        }
    }
}
