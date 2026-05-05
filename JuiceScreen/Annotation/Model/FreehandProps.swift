import AppKit

public struct FreehandProps: Equatable, Hashable, Sendable {
    public var points: [CGPoint]
    public var color: NSColor
    public var thickness: CGFloat
    public var isHighlighter: Bool

    public init(points: [CGPoint], color: NSColor, thickness: CGFloat, isHighlighter: Bool) {
        self.points = points
        self.color = color
        self.thickness = thickness
        self.isHighlighter = isHighlighter
    }

    public var boundingRect: CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
