import AppKit
import Testing
@testable import JuiceScreen

@Suite("AnnotationDocument")
struct AnnotationDocumentTests {

    private func makeImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return img
    }

    @Test("Initial document has no layers and no crop")
    func initial() {
        let doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        #expect(doc.layers.isEmpty)
        #expect(doc.canvasCrop == nil)
    }

    @Test("Append layer mutates layers array")
    func appendLayer() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        doc.append(layer)
        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].id == layer.id)
    }

    @Test("Replace layer by id keeps order and replaces in place")
    func replaceLayer() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        let l1 = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        let l2 = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 20, y: 20), color: .blue, thickness: 4))
        doc.append(l1)
        doc.append(l2)

        let updated = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 99, y: 99), color: .green, thickness: 8), id: l1.id)
        doc.replace(updated)
        #expect(doc.layers.count == 2)
        #expect(doc.layers[0].id == l1.id)
        if case .line(let p, _) = doc.layers[0] {
            #expect(p.color == .green)
        } else {
            Issue.record("Expected line at index 0")
        }
    }

    @Test("Remove layer by id")
    func removeLayer() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        let l1 = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 1))
        let l2 = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .blue, thickness: 1))
        doc.append(l1)
        doc.append(l2)
        doc.remove(id: l1.id)
        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].id == l2.id)
    }

    @Test("Crop is settable and clearable")
    func crop() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        doc.canvasCrop = CGRect(x: 10, y: 10, width: 50, height: 50)
        #expect(doc.canvasCrop == CGRect(x: 10, y: 10, width: 50, height: 50))
        doc.canvasCrop = nil
        #expect(doc.canvasCrop == nil)
    }
}
