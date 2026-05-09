import AppKit
import Testing
@testable import JuiceScreen

@Suite("EditorState")
@MainActor
struct EditorStateTests {

    private func makeImage() -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.addRepresentation(rep)
        return img
    }

    private func makeRecord(at url: URL = URL(fileURLWithPath: "/tmp/x.png")) -> CaptureRecord {
        CaptureRecord(fileURL: url, captureType: .region, capturedAt: Date(),
                      pixelWidth: 100, pixelHeight: 100, sourceApp: nil)
    }

    @Test("Initial state: select tool, no selection, empty document")
    func initial() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        #expect(state.currentTool == .select)
        #expect(state.selectedLayerID == nil)
        #expect(state.document.layers.isEmpty)
    }

    @Test("addLayer pushes onto document and undo stack")
    func addLayer() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        state.add(layer)
        #expect(state.document.layers.count == 1)
        #expect(state.canUndo == true)
    }

    @Test("Undo pops the last add")
    func undo() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        state.add(layer)
        state.undo()
        #expect(state.document.layers.isEmpty)
        #expect(state.canUndo == false)
        #expect(state.canRedo == true)
    }

    @Test("Setting selectedLayerID updates state but does not affect undo stack")
    func selectionDoesNotPushUndo() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 2))
        state.add(layer)
        let undoBefore = state.canUndo
        state.selectedLayerID = layer.id
        #expect(state.selectedLayerID == layer.id)
        #expect(state.canUndo == undoBefore)
    }

    @Test("Delete selected layer mutates document and pushes undo")
    func deleteSelected() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 2))
        state.add(layer)
        state.selectedLayerID = layer.id
        state.deleteSelected()
        #expect(state.document.layers.isEmpty)
        #expect(state.selectedLayerID == nil)
    }

    @Test("Duplicate selected adds a copy with a new id")
    func duplicateSelected() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 0, y: 0, width: 10, height: 10), color: .red, thickness: 2, filled: false))
        state.add(layer)
        state.selectedLayerID = layer.id
        state.duplicateSelected()
        #expect(state.document.layers.count == 2)
        #expect(state.document.layers[0].id != state.document.layers[1].id)
    }

    // MARK: - canvasSize

    @Test("canvasSize is half pixel dimensions (Retina)")
    func canvasSize() {
        let record = CaptureRecord(fileURL: URL(fileURLWithPath: "/tmp/x.png"),
                                   captureType: .region, capturedAt: Date(),
                                   pixelWidth: 200, pixelHeight: 80, sourceApp: nil)
        let state = EditorState(captureRecord: record, baseImage: makeImage())
        #expect(state.canvasSize == CGSize(width: 100, height: 40))
    }

    // MARK: - placeTextAtCanvasCenter

    @Test("placeTextAtCanvasCenter inserts text at canvas centre, switches to select, clears buffer, pushes undo")
    func placeTextAtCenter() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        state.currentText = "Hello"
        state.currentTool = .text
        state.placeTextAtCanvasCenter()

        #expect(state.document.layers.count == 1)
        guard case let .text(props, _) = state.document.layers[0] else {
            Issue.record("Expected text layer"); return
        }
        #expect(props.text == "Hello")
        // canvasSize for 100x100 record is 50x50 → centre is (25, 25)
        #expect(props.origin == CGPoint(x: 25, y: 25))
        #expect(state.currentText == "")
        #expect(state.currentTool == .select)
        #expect(state.selectedLayerID != nil)
        #expect(state.canUndo == true)
        #expect(state.isEdited == true)
    }

    @Test("placeTextAtCanvasCenter falls back to 'Text' when buffer is empty")
    func placeTextAtCenterEmptyFallback() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        state.currentText = ""
        state.placeTextAtCanvasCenter()
        guard case let .text(props, _) = state.document.layers[0] else {
            Issue.record("Expected text layer"); return
        }
        #expect(props.text == "Text")
    }

    // MARK: - replace

    @Test("replace swaps an existing layer in place and pushes undo")
    func replaceLayer() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let original = AnnotationLayer.line(LineProps(start: .zero, end: CGPoint(x: 5, y: 5), color: .red, thickness: 1))
        state.add(original)
        // Replacement keeps the same id but changes coordinates.
        let replacement: AnnotationLayer = .line(LineProps(start: CGPoint(x: 1, y: 1),
                                                            end: CGPoint(x: 9, y: 9),
                                                            color: .blue, thickness: 4),
                                                  id: original.id)
        state.replace(replacement)
        #expect(state.document.layers.count == 1)
        #expect(state.document.layers[0].id == original.id)
        guard case let .line(props, _) = state.document.layers[0] else {
            Issue.record("Expected line layer"); return
        }
        #expect(props.thickness == 4)
        // Both add and replace pushed onto the undo stack.
        state.undo()
        guard case let .line(rolledBackProps, _) = state.document.layers[0] else {
            Issue.record("Expected line layer after undo"); return
        }
        #expect(rolledBackProps.thickness == 1)
    }

    // MARK: - drag session lifecycle

    @Test("Drag session: addLive + commit produces ONE undo entry")
    func dragSessionAddLiveCommitsOneEntry() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let undoCountBefore = state.canUndo
        // Three live updates simulate the gesture's onChanged ticks; only the final
        // commitDragSession should push a single undo entry.
        let layer1 = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 0, y: 0, width: 1, height: 1), color: .red, thickness: 1, filled: false))
        let layer2 = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 0, y: 0, width: 5, height: 5), color: .red, thickness: 1, filled: false))
        let layer3 = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 0, y: 0, width: 9, height: 9), color: .red, thickness: 1, filled: false))
        state.addLive(layer1)
        #expect(state.hasActiveDragSession == true)
        state.replaceLive(layer2)
        state.replaceLive(layer3)
        state.commitDragSession()
        #expect(state.hasActiveDragSession == false)
        #expect(state.document.layers.count == 1)
        // Single undo should restore to the pre-drag empty state.
        state.undo()
        #expect(state.document.layers.isEmpty)
        #expect(undoCountBefore == false)
    }

    @Test("Cancel drag session restores pre-drag snapshot and does NOT push undo")
    func cancelDragSession() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let preDrag = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 1))
        state.add(preDrag)   // undoStack now has 1 entry
        let liveLayer = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 0, y: 0, width: 5, height: 5), color: .blue, thickness: 1, filled: false))
        state.addLive(liveLayer)
        #expect(state.document.layers.count == 2)
        state.cancelDragSession()
        #expect(state.document.layers.count == 1)
        #expect(state.hasActiveDragSession == false)
        // Cancel must not push: undoing once should return to the empty state.
        state.undo()
        #expect(state.document.layers.isEmpty)
    }

    @Test("commitDragSession with no actual change does NOT push undo")
    func commitDragSessionNoChange() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let preDrag = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 1))
        state.add(preDrag)
        state.beginDragSession()
        // No live mutations — just commit immediately.
        state.commitDragSession()
        // Undoing once should remove the original add, not a phantom drag.
        state.undo()
        #expect(state.document.layers.isEmpty)
    }

    // MARK: - setCrop / redo

    @Test("setCrop assigns rect, pushes undo, and is reversible")
    func setCropPushesUndo() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let crop = CGRect(x: 5, y: 5, width: 30, height: 20)
        state.setCrop(crop)
        #expect(state.document.canvasCrop == crop)
        #expect(state.isEdited == true)
        state.undo()
        #expect(state.document.canvasCrop == nil)
    }

    @Test("redo restores the undone state")
    func redoRestores() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 1))
        state.add(layer)
        state.undo()
        #expect(state.document.layers.isEmpty)
        #expect(state.canRedo == true)
        state.redo()
        #expect(state.document.layers.count == 1)
    }

    // MARK: - duplicate covers all layer cases

    @Test("Duplicate offsets each layer kind by (12, 12) and gives it a fresh id")
    func duplicateAllKinds() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let kinds: [AnnotationLayer] = [
            .arrow(ArrowProps(start: .zero, end: CGPoint(x: 4, y: 4), color: .red, thickness: 1, doubleHeaded: false)),
            .line(LineProps(start: .zero, end: CGPoint(x: 4, y: 4), color: .red, thickness: 1)),
            .ellipse(ShapeProps(rect: CGRect(x: 0, y: 0, width: 10, height: 10), color: .red, thickness: 1, filled: false)),
            .freehand(FreehandProps(points: [.zero, CGPoint(x: 1, y: 1)], color: .red, thickness: 1, isHighlighter: false)),
            .text(TextProps(origin: .zero, text: "x", color: .red, fontName: "Helvetica", fontSize: 12)),
            .blur(BlurProps(rect: CGRect(x: 0, y: 0, width: 4, height: 4), style: .gaussian, intensity: 8)),
        ]
        for original in kinds {
            state.add(original)
            state.selectedLayerID = original.id
            state.duplicateSelected()
            // Document should hold the original + duplicate for this kind.
            let copies = state.document.layers.suffix(2)
            #expect(copies.count == 2)
            let originalRect = original.boundingRect
            let copyRect = copies.last!.boundingRect
            #expect(abs(copyRect.minX - (originalRect.minX + 12)) < 0.001)
            #expect(abs(copyRect.minY - (originalRect.minY + 12)) < 0.001)
            #expect(copies.first!.id != copies.last!.id)
        }
    }
}
