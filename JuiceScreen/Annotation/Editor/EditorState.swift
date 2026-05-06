import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class EditorState {

    public let captureRecord: CaptureRecord

    public var currentTool: ToolType = .select
    public var currentColor: NSColor = .systemRed
    public var currentThickness: CGFloat = 3
    public var currentFontName: String = "Helvetica"
    public var currentFontSize: CGFloat = 18
    public var currentFilled: Bool = false
    public var currentBlurStyle: BlurProps.Style = .gaussian
    public var currentBlurIntensity: CGFloat = 12
    public var currentText: String = ""

    public var selectedLayerID: UUID? = nil
    public var isEdited: Bool = false   // tracks whether anything has been added since open

    private var undoStack: UndoStack<AnnotationDocument>

    public init(captureRecord: CaptureRecord, baseImage: NSImage) {
        self.captureRecord = captureRecord
        self.undoStack = UndoStack(initial: AnnotationDocument(baseImage: baseImage))
    }

    /// Canvas drawing area in points (Retina captures render at half pixel size).
    public var canvasSize: CGSize {
        CGSize(width: CGFloat(captureRecord.pixelWidth) / 2,
               height: CGFloat(captureRecord.pixelHeight) / 2)
    }

    /// Drops a text layer at the centre of the canvas using the current text/style,
    /// switches to the Select tool, and clears the buffered text. Switching tools
    /// also moves keyboard focus off the TextField so the next canvas click is not
    /// eaten by macOS dismissing the field.
    public func placeTextAtCanvasCenter() {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let body = currentText.isEmpty ? "Text" : currentText
        let layer = AnnotationLayer.text(TextProps(
            origin: center,
            text: body,
            color: currentColor,
            fontName: currentFontName,
            fontSize: currentFontSize
        ))
        add(layer)
        selectedLayerID = layer.id
        currentText = ""
        currentTool = .select
    }

    public var document: AnnotationDocument { undoStack.current }
    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }

    // MARK: - Mutations (each pushes onto the undo stack)

    public func add(_ layer: AnnotationLayer) {
        var next = undoStack.current
        next.append(layer)
        undoStack.push(next)
        isEdited = true
    }

    public func replace(_ layer: AnnotationLayer) {
        var next = undoStack.current
        next.replace(layer)
        undoStack.push(next)
        isEdited = true
    }

    public func deleteSelected() {
        guard let id = selectedLayerID else { return }
        var next = undoStack.current
        next.remove(id: id)
        undoStack.push(next)
        selectedLayerID = nil
        isEdited = true
    }

    public func duplicateSelected() {
        guard let id = selectedLayerID,
              let layer = undoStack.current.layer(id: id) else { return }
        let copy = duplicate(layer)
        var next = undoStack.current
        next.append(copy)
        undoStack.push(next)
        selectedLayerID = copy.id
        isEdited = true
    }

    public func setCrop(_ rect: CGRect?) {
        var next = undoStack.current
        next.canvasCrop = rect
        undoStack.push(next)
        isEdited = true
    }

    public func undo() {
        undoStack.undo()
    }

    public func redo() {
        undoStack.redo()
    }

    // MARK: - Helpers

    private func duplicate(_ layer: AnnotationLayer) -> AnnotationLayer {
        let offset = CGSize(width: 12, height: 12)
        switch layer {
        case .arrow(let p, _):
            return .arrow(ArrowProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                     color: p.color, thickness: p.thickness, doubleHeaded: p.doubleHeaded))
        case .line(let p, _):
            return .line(LineProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                   color: p.color, thickness: p.thickness))
        case .rectangle(let p, _):
            return .rectangle(ShapeProps(rect: p.rect.offsetBy(offset), color: p.color, thickness: p.thickness, filled: p.filled))
        case .ellipse(let p, _):
            return .ellipse(ShapeProps(rect: p.rect.offsetBy(offset), color: p.color, thickness: p.thickness, filled: p.filled))
        case .freehand(let p, _):
            return .freehand(FreehandProps(points: p.points.map { $0.offsetBy(offset) },
                                           color: p.color, thickness: p.thickness, isHighlighter: p.isHighlighter))
        case .text(let p, _):
            return .text(TextProps(origin: p.origin.offsetBy(offset), text: p.text,
                                   color: p.color, fontName: p.fontName, fontSize: p.fontSize))
        case .blur(let p, _):
            return .blur(BlurProps(rect: p.rect.offsetBy(offset), style: p.style, intensity: p.intensity))
        }
    }
}

// MARK: - Geometry helpers (shared with CanvasGestures.translate in Task 10)

extension CGPoint {
    func offsetBy(_ s: CGSize) -> CGPoint { CGPoint(x: x + s.width, y: y + s.height) }
}

extension CGRect {
    func offsetBy(_ s: CGSize) -> CGRect { offsetBy(dx: s.width, dy: s.height) }
}
