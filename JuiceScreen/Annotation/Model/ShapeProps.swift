import AppKit

/// Shared by Rectangle and Ellipse layers. Differentiated by which `AnnotationLayer` case wraps it.
public struct ShapeProps: Equatable, Hashable, Sendable {
    public var rect: CGRect
    public var color: NSColor
    public var thickness: CGFloat
    public var filled: Bool

    public init(rect: CGRect, color: NSColor, thickness: CGFloat, filled: Bool) {
        self.rect = rect
        self.color = color
        self.thickness = thickness
        self.filled = filled
    }

    public var boundingRect: CGRect { rect }
}
