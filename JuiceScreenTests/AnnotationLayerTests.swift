import AppKit
import Testing
@testable import JuiceScreen

@Suite("AnnotationLayer")
struct AnnotationLayerTests {

    @Test("Each layer carries a UUID")
    func layerHasId() {
        let a = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        let b = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        #expect(a.id != b.id)
    }

    @Test("Bounding rect dispatches per case")
    func bounds() {
        let line = AnnotationLayer.line(LineProps(start: .init(x: 5, y: 5), end: .init(x: 10, y: 20), color: .red, thickness: 2))
        #expect(line.boundingRect == CGRect(x: 5, y: 5, width: 5, height: 15))

        let rect = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 1, y: 2, width: 30, height: 40), color: .red, thickness: 2, filled: false))
        #expect(rect.boundingRect == CGRect(x: 1, y: 2, width: 30, height: 40))

        let blur = AnnotationLayer.blur(BlurProps(rect: CGRect(x: 0, y: 0, width: 50, height: 50), style: .gaussian, intensity: 8))
        #expect(blur.boundingRect == CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    @Test("Tool type per layer")
    func toolType() {
        let line = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 1))
        #expect(line.toolType == .line)

        let arrow = AnnotationLayer.arrow(ArrowProps(start: .zero, end: .zero, color: .red, thickness: 1, doubleHeaded: false))
        #expect(arrow.toolType == .arrow)

        let darrow = AnnotationLayer.arrow(ArrowProps(start: .zero, end: .zero, color: .red, thickness: 1, doubleHeaded: true))
        #expect(darrow.toolType == .doubleArrow)

        let rect = AnnotationLayer.rectangle(ShapeProps(rect: .zero, color: .red, thickness: 1, filled: false))
        #expect(rect.toolType == .rectangle)

        let ellipse = AnnotationLayer.ellipse(ShapeProps(rect: .zero, color: .red, thickness: 1, filled: false))
        #expect(ellipse.toolType == .ellipse)

        let pen = AnnotationLayer.freehand(FreehandProps(points: [], color: .red, thickness: 1, isHighlighter: false))
        #expect(pen.toolType == .pen)

        let high = AnnotationLayer.freehand(FreehandProps(points: [], color: .yellow, thickness: 8, isHighlighter: true))
        #expect(high.toolType == .highlighter)

        let text = AnnotationLayer.text(TextProps(origin: .zero, text: "x", color: .black, fontName: "Helvetica", fontSize: 12))
        #expect(text.toolType == .text)

        let blur = AnnotationLayer.blur(BlurProps(rect: .zero, style: .gaussian, intensity: 8))
        #expect(blur.toolType == .blur)
    }
}
