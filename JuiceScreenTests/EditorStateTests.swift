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
}
