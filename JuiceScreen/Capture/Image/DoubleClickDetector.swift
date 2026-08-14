import CoreGraphics
import Foundation

/// Decides whether a click continues a polygon or closes it.
///
/// The double-click is detected here rather than by a SwiftUI `TapGesture(count: 2)`,
/// because that recognizer competes in the same exclusive pool as the freehand
/// `DragGesture(minimumDistance: 0)` — which is satisfied on mouse-down and tends to
/// win — and because a count-1 `SpatialTapGesture` fires on *both* halves of a
/// double-click, appending two coincident vertices as a side effect.
struct DoubleClickDetector {
    static let maximumDistance: CGFloat = 4

    private var lastPoint: CGPoint?
    private var lastTime: TimeInterval?

    /// Returns true when this click should close the shape rather than add a vertex.
    mutating func isSecondClick(at point: CGPoint, time: TimeInterval, interval: TimeInterval) -> Bool {
        if let lastPoint, let lastTime,
           time - lastTime <= interval,
           distance(point, lastPoint) <= Self.maximumDistance {
            self.lastPoint = nil
            self.lastTime = nil
            return true
        }
        lastPoint = point
        lastTime = time
        return false
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
