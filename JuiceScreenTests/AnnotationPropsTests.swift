import AppKit
import Testing
@testable import JuiceScreen

@Suite("Annotation Props")
struct AnnotationPropsTests {

    // MARK: - Arrow

    @Test("ArrowProps stores all fields including doubleHeaded")
    func arrowProps() {
        let p = ArrowProps(
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 100, y: 200),
            color: .red,
            thickness: 3,
            doubleHeaded: true
        )
        #expect(p.start == CGPoint(x: 10, y: 20))
        #expect(p.end == CGPoint(x: 100, y: 200))
        #expect(p.thickness == 3)
        #expect(p.doubleHeaded == true)
    }

    @Test("ArrowProps bounding rect fits both endpoints")
    func arrowBounds() {
        let p = ArrowProps(start: CGPoint(x: 100, y: 50), end: CGPoint(x: 10, y: 200),
                           color: .red, thickness: 2, doubleHeaded: false)
        let b = p.boundingRect
        #expect(b.minX == 10)
        #expect(b.maxX == 100)
        #expect(b.minY == 50)
        #expect(b.maxY == 200)
    }

    // MARK: - Line

    @Test("LineProps stores all fields")
    func lineProps() {
        let p = LineProps(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10),
                          color: .blue, thickness: 1)
        #expect(p.start == .zero)
        #expect(p.end == CGPoint(x: 10, y: 10))
    }

    // MARK: - Shape (Rectangle / Ellipse)

    @Test("ShapeProps stores rect, color, thickness, filled flag")
    func shapeProps() {
        let p = ShapeProps(rect: CGRect(x: 5, y: 5, width: 20, height: 30),
                           color: .green, thickness: 2, filled: false)
        #expect(p.rect.width == 20)
        #expect(p.filled == false)
    }

    // MARK: - Freehand

    @Test("FreehandProps stores point list and highlighter flag")
    func freehandProps() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 8)]
        let p = FreehandProps(points: pts, color: .yellow, thickness: 6, isHighlighter: true)
        #expect(p.points.count == 3)
        #expect(p.isHighlighter == true)
    }

    @Test("FreehandProps bounding rect contains all points")
    func freehandBounds() {
        let pts = [CGPoint(x: 50, y: 10), CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 50)]
        let p = FreehandProps(points: pts, color: .red, thickness: 2, isHighlighter: false)
        let b = p.boundingRect
        #expect(b.minX == 0)
        #expect(b.maxX == 200)
        #expect(b.minY == 10)
        #expect(b.maxY == 100)
    }

    @Test("FreehandProps bounding rect for empty points is zero rect")
    func freehandEmptyBounds() {
        let p = FreehandProps(points: [], color: .red, thickness: 2, isHighlighter: false)
        #expect(p.boundingRect == .zero)
    }

    // MARK: - Text

    @Test("TextProps stores origin, text, font fields")
    func textProps() {
        let p = TextProps(origin: CGPoint(x: 50, y: 60), text: "hello",
                          color: .black, fontName: "Helvetica", fontSize: 14)
        #expect(p.text == "hello")
        #expect(p.fontSize == 14)
    }

    // MARK: - Blur

    @Test("BlurProps stores rect, style and intensity")
    func blurProps() {
        let p = BlurProps(rect: CGRect(x: 0, y: 0, width: 50, height: 30),
                          style: .pixelate, intensity: 12)
        #expect(p.style == .pixelate)
        #expect(p.intensity == 12)
    }
}
