import AppKit
import SwiftUI

/// Drag handlers per tool. Dispatches based on `state.currentTool`.
/// Held by `EditorView` and overlaid on top of `AnnotationCanvas`.
struct CanvasGestures: View {

    @Bindable var state: EditorState
    @State private var dragStart: CGPoint? = nil
    @State private var freehandPoints: [CGPoint] = []
    @State private var inProgressLayerID: UUID? = nil
    @State private var moveOriginalLayer: AnnotationLayer? = nil  // snapshot of selected layer at drag start

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in handleChanged(value) }
                    .onEnded { value in handleEnded(value) }
            )
            .onTapGesture { location in handleTap(at: location) }
    }

    // MARK: - Tap (Select + Text)

    private func handleTap(at location: CGPoint) {
        switch state.currentTool {
        case .select:
            // Hit-test top-down (last drawn = topmost)
            for layer in state.document.layers.reversed() {
                if HitTest.contains(layer, point: location) {
                    state.selectedLayerID = layer.id
                    return
                }
            }
            state.selectedLayerID = nil

        case .text:
            // Drop a text layer with placeholder text — user can edit via inspector or by typing
            let layer = AnnotationLayer.text(TextProps(
                origin: location,
                text: "Text",
                color: state.currentColor,
                fontName: state.currentFontName,
                fontSize: state.currentFontSize
            ))
            state.add(layer)
            state.selectedLayerID = layer.id

        default:
            break
        }
    }

    // MARK: - Drag dispatch

    private func handleChanged(_ value: DragGesture.Value) {
        switch state.currentTool {
        case .arrow, .doubleArrow, .line, .rectangle, .ellipse, .blur, .crop:
            updateDragShape(start: value.startLocation, current: value.location)
        case .pen, .highlighter:
            updateFreehand(point: value.location)
        case .select:
            updateSelectMove(start: value.startLocation, current: value.location)
        case .text:
            break
        }
    }

    private func handleEnded(_ value: DragGesture.Value) {
        switch state.currentTool {
        case .arrow, .doubleArrow, .line, .rectangle, .ellipse, .blur:
            // Layer was added incrementally during onChanged; nothing more to do
            inProgressLayerID = nil
        case .pen, .highlighter:
            inProgressLayerID = nil
            freehandPoints = []
        case .crop:
            // Crop sets canvasCrop instead of adding a layer
            let rect = normalizedRect(from: value.startLocation, to: value.location)
            state.setCrop(rect.width >= 4 && rect.height >= 4 ? rect : nil)
        case .select:
            moveOriginalLayer = nil
        case .text:
            break
        }
    }

    // MARK: - Select tool: drag-to-move the currently selected layer

    private func updateSelectMove(start: CGPoint, current: CGPoint) {
        // First tick of the drag: snapshot the selected layer if the drag started inside its bounds.
        if moveOriginalLayer == nil {
            guard let id = state.selectedLayerID,
                  let layer = state.document.layer(id: id),
                  HitTest.contains(layer, point: start) else {
                return
            }
            moveOriginalLayer = layer
        }
        guard let original = moveOriginalLayer else { return }
        let offset = CGSize(width: current.x - start.x, height: current.y - start.y)
        let translated = translate(layer: original, by: offset)
        state.replace(translated)
    }

    private func translate(layer: AnnotationLayer, by offset: CGSize) -> AnnotationLayer {
        switch layer {
        case .arrow(let p, let id):
            return .arrow(ArrowProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                     color: p.color, thickness: p.thickness, doubleHeaded: p.doubleHeaded), id: id)
        case .line(let p, let id):
            return .line(LineProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                   color: p.color, thickness: p.thickness), id: id)
        case .rectangle(let p, let id):
            return .rectangle(ShapeProps(rect: p.rect.offsetBy(offset),
                                         color: p.color, thickness: p.thickness, filled: p.filled), id: id)
        case .ellipse(let p, let id):
            return .ellipse(ShapeProps(rect: p.rect.offsetBy(offset),
                                       color: p.color, thickness: p.thickness, filled: p.filled), id: id)
        case .freehand(let p, let id):
            return .freehand(FreehandProps(points: p.points.map { $0.offsetBy(offset) },
                                           color: p.color, thickness: p.thickness, isHighlighter: p.isHighlighter), id: id)
        case .text(let p, let id):
            return .text(TextProps(origin: p.origin.offsetBy(offset), text: p.text,
                                   color: p.color, fontName: p.fontName, fontSize: p.fontSize), id: id)
        case .blur(let p, let id):
            return .blur(BlurProps(rect: p.rect.offsetBy(offset),
                                   style: p.style, intensity: p.intensity), id: id)
        }
    }

    // MARK: - Helpers — drag-to-create shape (in-progress layer is updated on each onChanged tick)

    private func updateDragShape(start: CGPoint, current: CGPoint) {
        let rect = normalizedRect(from: start, to: current)
        let line = (start: start, end: current)

        let newLayer = makeLayerForCurrentTool(rect: rect, line: line)

        if let id = inProgressLayerID,
           let existingIdx = state.document.layers.firstIndex(where: { $0.id == id }) {
            // Replace in place
            let layerWithSameID = newLayer.withID(id)
            state.replace(layerWithSameID)
            _ = existingIdx
        } else {
            state.add(newLayer)
            inProgressLayerID = newLayer.id
        }
    }

    private func makeLayerForCurrentTool(rect: CGRect, line: (start: CGPoint, end: CGPoint)) -> AnnotationLayer {
        switch state.currentTool {
        case .arrow:
            return .arrow(ArrowProps(start: line.start, end: line.end, color: state.currentColor,
                                     thickness: state.currentThickness, doubleHeaded: false))
        case .doubleArrow:
            return .arrow(ArrowProps(start: line.start, end: line.end, color: state.currentColor,
                                     thickness: state.currentThickness, doubleHeaded: true))
        case .line:
            return .line(LineProps(start: line.start, end: line.end, color: state.currentColor,
                                   thickness: state.currentThickness))
        case .rectangle:
            return .rectangle(ShapeProps(rect: rect, color: state.currentColor,
                                         thickness: state.currentThickness, filled: state.currentFilled))
        case .ellipse:
            return .ellipse(ShapeProps(rect: rect, color: state.currentColor,
                                       thickness: state.currentThickness, filled: state.currentFilled))
        case .blur:
            return .blur(BlurProps(rect: rect, style: state.currentBlurStyle, intensity: state.currentBlurIntensity))
        default:
            return .rectangle(ShapeProps(rect: rect, color: state.currentColor,
                                         thickness: state.currentThickness, filled: false))
        }
    }

    // MARK: - Freehand (pen / highlighter)

    private func updateFreehand(point: CGPoint) {
        if inProgressLayerID == nil {
            freehandPoints = [point]
            let layer = AnnotationLayer.freehand(FreehandProps(
                points: freehandPoints,
                color: state.currentColor,
                thickness: state.currentTool == .highlighter ? max(state.currentThickness, 12) : state.currentThickness,
                isHighlighter: state.currentTool == .highlighter
            ))
            state.add(layer)
            inProgressLayerID = layer.id
        } else {
            freehandPoints.append(point)
            let updated = AnnotationLayer.freehand(FreehandProps(
                points: freehandPoints,
                color: state.currentColor,
                thickness: state.currentTool == .highlighter ? max(state.currentThickness, 12) : state.currentThickness,
                isHighlighter: state.currentTool == .highlighter
            ), id: inProgressLayerID!)
            state.replace(updated)
        }
    }

    // MARK: - Geometry

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

// Helper: rebuild a layer with a specific id (preserves identity during in-progress drag)
private extension AnnotationLayer {
    func withID(_ id: UUID) -> AnnotationLayer {
        switch self {
        case .arrow(let p, _):     return .arrow(p, id: id)
        case .line(let p, _):      return .line(p, id: id)
        case .rectangle(let p, _): return .rectangle(p, id: id)
        case .ellipse(let p, _):   return .ellipse(p, id: id)
        case .freehand(let p, _):  return .freehand(p, id: id)
        case .text(let p, _):      return .text(p, id: id)
        case .blur(let p, _):      return .blur(p, id: id)
        }
    }
}
