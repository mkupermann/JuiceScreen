import AppKit

/// In-memory representation of one capture in the editor: the original bitmap (never mutated)
/// plus an ordered stack of annotation layers and an optional crop applied at export time.
public struct AnnotationDocument: Sendable {

    public let baseImage: NSImage
    public private(set) var layers: [AnnotationLayer]
    public var canvasCrop: CGRect?

    public init(baseImage: NSImage, layers: [AnnotationLayer] = [], canvasCrop: CGRect? = nil) {
        self.baseImage = baseImage
        self.layers = layers
        self.canvasCrop = canvasCrop
    }

    public mutating func append(_ layer: AnnotationLayer) {
        layers.append(layer)
    }

    public mutating func replace(_ layer: AnnotationLayer) {
        guard let idx = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[idx] = layer
    }

    public mutating func remove(id: UUID) {
        layers.removeAll { $0.id == id }
    }

    public func layer(id: UUID) -> AnnotationLayer? {
        layers.first { $0.id == id }
    }
}
