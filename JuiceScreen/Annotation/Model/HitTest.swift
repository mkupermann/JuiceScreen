import AppKit

/// Pure point-in-layer hit testing. Used by the Select tool to figure out which
/// layer the user clicked on.
public enum HitTest {

    /// Returns true if `point` is inside (or close to, for stroke-based layers) the layer.
    public static func contains(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        switch layer {
        case .rectangle(let p, _):
            return p.rect.contains(point)

        case .ellipse(let p, _):
            return ellipseContains(rect: p.rect, point: point)

        case .blur(let p, _):
            return p.rect.contains(point)

        case .text(let p, _):
            return p.boundingRect().contains(point)

        case .arrow(let p, _):
            return distanceFromSegment(point: point, a: p.start, b: p.end) <= max(p.thickness / 2 + 4, 6)

        case .line(let p, _):
            return distanceFromSegment(point: point, a: p.start, b: p.end) <= max(p.thickness / 2 + 4, 6)

        case .freehand(let p, _):
            for i in 1..<p.points.count {
                if distanceFromSegment(point: point, a: p.points[i - 1], b: p.points[i]) <= max(p.thickness / 2 + 4, 6) {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Geometry helpers

    private static func ellipseContains(rect: CGRect, point: CGPoint) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let nx = (point.x - cx) / rx
        let ny = (point.y - cy) / ry
        return (nx * nx + ny * ny) <= 1
    }

    /// Shortest distance from `point` to segment `a→b`.
    private static func distanceFromSegment(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 {
            let dxp = point.x - a.x, dyp = point.y - a.y
            return (dxp * dxp + dyp * dyp).squareRoot()
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let pdx = point.x - projX, pdy = point.y - projY
        return (pdx * pdx + pdy * pdy).squareRoot()
    }
}
