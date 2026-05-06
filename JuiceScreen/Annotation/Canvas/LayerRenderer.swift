import AppKit
import SwiftUI

/// Pure draw routines: given a SwiftUI `GraphicsContext`, render a single annotation layer.
/// No state, no view tree — used by `AnnotationCanvas` (live editor) and
/// `AnnotationRenderer` (export flatten via a pixel-backed CGContext).
public enum LayerRenderer {

    public static func draw(_ layer: AnnotationLayer, in ctx: inout GraphicsContext) {
        switch layer {
        case .arrow(let p, _):
            drawArrow(p, in: &ctx)
        case .line(let p, _):
            drawLine(p, in: &ctx)
        case .rectangle(let p, _):
            drawRectangle(p, in: &ctx)
        case .ellipse(let p, _):
            drawEllipse(p, in: &ctx)
        case .freehand(let p, _):
            drawFreehand(p, in: &ctx)
        case .text(let p, _):
            drawText(p, in: &ctx)
        case .blur:
            // Blur is destructive at export. In the live editor it shows as a
            // semi-transparent overlay so the user knows where it will be applied.
            drawBlurPlaceholder(layer, in: &ctx)
        }
    }

    // MARK: - Per-layer

    private static func drawLine(_ p: LineProps, in ctx: inout GraphicsContext) {
        var path = Path()
        path.move(to: p.start)
        path.addLine(to: p.end)
        ctx.stroke(path, with: .color(Color(p.color)), style: StrokeStyle(lineWidth: p.thickness, lineCap: .round))
    }

    private static func drawArrow(_ p: ArrowProps, in ctx: inout GraphicsContext) {
        // Shaft
        var shaft = Path()
        shaft.move(to: p.start)
        shaft.addLine(to: p.end)
        ctx.stroke(shaft, with: .color(Color(p.color)), style: StrokeStyle(lineWidth: p.thickness, lineCap: .round))

        // Head at end
        ctx.fill(arrowHeadPath(at: p.end, from: p.start, length: max(p.thickness * 4, 12)),
                 with: .color(Color(p.color)))
        if p.doubleHeaded {
            ctx.fill(arrowHeadPath(at: p.start, from: p.end, length: max(p.thickness * 4, 12)),
                     with: .color(Color(p.color)))
        }
    }

    private static func arrowHeadPath(at tip: CGPoint, from origin: CGPoint, length: CGFloat) -> Path {
        let dx = tip.x - origin.x, dy = tip.y - origin.y
        let angle = atan2(dy, dx)
        let h = length
        let w = length * 0.7
        let baseX = tip.x - cos(angle) * h
        let baseY = tip.y - sin(angle) * h
        let leftX = baseX + cos(angle + .pi / 2) * (w / 2)
        let leftY = baseY + sin(angle + .pi / 2) * (w / 2)
        let rightX = baseX - cos(angle + .pi / 2) * (w / 2)
        let rightY = baseY - sin(angle + .pi / 2) * (w / 2)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: leftX, y: leftY))
        path.addLine(to: CGPoint(x: rightX, y: rightY))
        path.closeSubpath()
        return path
    }

    private static func drawRectangle(_ p: ShapeProps, in ctx: inout GraphicsContext) {
        let path = Path(p.rect)
        if p.filled {
            ctx.fill(path, with: .color(Color(p.color)))
        } else {
            ctx.stroke(path, with: .color(Color(p.color)), lineWidth: p.thickness)
        }
    }

    private static func drawEllipse(_ p: ShapeProps, in ctx: inout GraphicsContext) {
        let path = Path(ellipseIn: p.rect)
        if p.filled {
            ctx.fill(path, with: .color(Color(p.color)))
        } else {
            ctx.stroke(path, with: .color(Color(p.color)), lineWidth: p.thickness)
        }
    }

    private static func drawFreehand(_ p: FreehandProps, in ctx: inout GraphicsContext) {
        guard p.points.count >= 2 else { return }
        var path = Path()
        path.move(to: p.points[0])
        for pt in p.points.dropFirst() { path.addLine(to: pt) }
        var color = Color(p.color)
        if p.isHighlighter {
            color = color.opacity(0.45)
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: p.thickness, lineCap: .round, lineJoin: .round))
    }

    private static func drawText(_ p: TextProps, in ctx: inout GraphicsContext) {
        let font = NSFont(name: p.fontName, size: p.fontSize) ?? NSFont.systemFont(ofSize: p.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: p.color
        ]
        let attributed = NSAttributedString(string: p.text, attributes: attrs)
        let resolved = ctx.resolve(Text(AttributedString(attributed)))
        ctx.draw(resolved, at: p.origin, anchor: .topLeading)
    }

    private static func drawBlurPlaceholder(_ layer: AnnotationLayer, in ctx: inout GraphicsContext) {
        // Blur and pixelate layers render as a live SwiftUI overlay (BlurPreviewOverlay)
        // — no in-canvas placeholder needed. This stub exists so the switch in `draw`
        // stays exhaustive without flickering a grey box behind the real preview.
        _ = layer
        _ = ctx
    }
}
