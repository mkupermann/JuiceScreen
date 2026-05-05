import AppKit

public struct TextProps: Equatable, Hashable, Sendable {
    public var origin: CGPoint
    public var text: String
    public var color: NSColor
    public var fontName: String
    public var fontSize: CGFloat

    public init(origin: CGPoint, text: String, color: NSColor, fontName: String, fontSize: CGFloat) {
        self.origin = origin
        self.text = text
        self.color = color
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public func boundingRect() -> CGRect {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGRect(origin: origin, size: size)
    }
}
