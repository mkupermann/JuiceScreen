import CoreGraphics
import Foundation

public struct OCRRegion: Equatable, Hashable, Sendable, Codable {
    public var text: String
    public var boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}
