import AppKit

public struct BlurProps: Equatable, Hashable, Sendable {

    public enum Style: String, Sendable, CaseIterable {
        case gaussian
        case pixelate
    }

    public var rect: CGRect
    public var style: Style
    public var intensity: CGFloat   // gaussian: blur radius; pixelate: cell size

    public init(rect: CGRect, style: Style, intensity: CGFloat) {
        self.rect = rect
        self.style = style
        self.intensity = intensity
    }

    public var boundingRect: CGRect { rect }
}
