import CoreGraphics

/// Pure value type representing an in-progress region selection on the picker overlay.
/// Coordinates are in the overlay window's coordinate space (which spans all displays).
public struct RegionSelection: Equatable, Sendable {

    public var start: CGPoint
    public var current: CGPoint

    public init(start: CGPoint, current: CGPoint) {
        self.start = start
        self.current = current
    }

    public var normalized: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    public var isUsable: Bool {
        normalized.width >= 1 && normalized.height >= 1
    }

    /// Returns a new selection translated by `offset`. Used for arrow-key nudging.
    public func nudged(by offset: CGSize) -> RegionSelection {
        RegionSelection(
            start: CGPoint(x: start.x + offset.width, y: start.y + offset.height),
            current: CGPoint(x: current.x + offset.width, y: current.y + offset.height)
        )
    }
}
