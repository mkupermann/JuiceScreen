import AppKit

public struct ArrowProps: Equatable, Hashable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var color: NSColor
    public var thickness: CGFloat
    public var doubleHeaded: Bool

    public init(start: CGPoint, end: CGPoint, color: NSColor, thickness: CGFloat, doubleHeaded: Bool) {
        self.start = start
        self.end = end
        self.color = color
        self.thickness = thickness
        self.doubleHeaded = doubleHeaded
    }

    public var boundingRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
