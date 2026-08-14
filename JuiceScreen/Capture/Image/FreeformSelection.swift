import CoreGraphics
import Foundation

/// Which drawing interaction produced a `FreeformSelection`.
public enum FreeformMode: String, Sendable, CaseIterable {
    case freehand
    case polygon
}

/// A non-rectangular selection in overlay-local, top-left-origin points.
///
/// Pure value type: no AppKit, no actor isolation. The picker view mutates it
/// during the gesture; `FreeformPickerController` converts `bounds` to global
/// screen coordinates once, at commit time.
public struct FreeformSelection: Equatable, Sendable {

    /// Freehand points closer together than this are dropped. A slow drag
    /// otherwise accumulates thousands of collinear points that carry no
    /// information and slow down both the live mask and the final clip.
    public static let minimumPointSpacing: CGFloat = 2

    public private(set) var mode: FreeformMode
    public private(set) var points: [CGPoint]

    public init(mode: FreeformMode, points: [CGPoint] = []) {
        self.mode = mode
        self.points = points
    }

    /// Switching modes mid-shape would leave the points half-freehand and
    /// half-polygon, so it is only allowed before the first point.
    public mutating func setMode(_ newMode: FreeformMode) {
        guard points.isEmpty else { return }
        mode = newMode
    }

    /// Freehand: appends `point` unless it is within `minimumPointSpacing` of
    /// the previous one.
    public mutating func append(_ point: CGPoint) {
        guard let last = points.last else {
            points.append(point)
            return
        }
        let dx = point.x - last.x
        let dy = point.y - last.y
        guard (dx * dx + dy * dy) >= (Self.minimumPointSpacing * Self.minimumPointSpacing) else {
            return
        }
        points.append(point)
    }

    /// Polygon: appends a deliberate vertex, unfiltered.
    public mutating func appendVertex(_ point: CGPoint) {
        points.append(point)
    }

    public mutating func removeLastVertex() {
        guard !points.isEmpty else { return }
        points.removeLast()
    }

    /// Bounding box of every point, rounded outward to whole points so the
    /// captured rect never clips the shape by a sub-point sliver.
    public var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    public var isUsable: Bool {
        points.count >= 3 && bounds.width >= 1 && bounds.height >= 1
    }

    /// The selection as a closed path, in overlay-local top-left coordinates.
    public var closedPath: CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() {
            path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    /// `closedPath` translated so that `bounds.origin` becomes (0, 0). This is
    /// the form handed to `FreeformMasker` — the path is never expressed in
    /// global screen coordinates.
    public var pathInBounds: CGPath {
        let origin = bounds.origin
        var transform = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        return closedPath.copy(using: &transform) ?? closedPath
    }
}
