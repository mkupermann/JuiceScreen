import AppKit
import Testing
@testable import JuiceScreen

@Suite("HitTest")
struct HitTestTests {

    @Test("Rectangle: point inside hits, outside does not")
    func rect() {
        let layer = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 10, y: 10, width: 50, height: 50), color: .red, thickness: 2, filled: false))
        #expect(HitTest.contains(layer, point: CGPoint(x: 30, y: 30)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 5, y: 5)))
    }

    @Test("Ellipse: hit uses inscribed ellipse, not the bounding rect")
    func ellipse() {
        // 100x100 ellipse from (0,0). Corner (5,5) is inside the bounding rect but outside the ellipse.
        let layer = AnnotationLayer.ellipse(ShapeProps(rect: CGRect(x: 0, y: 0, width: 100, height: 100), color: .red, thickness: 2, filled: false))
        #expect(HitTest.contains(layer, point: CGPoint(x: 50, y: 50)))   // center, inside
        #expect(!HitTest.contains(layer, point: CGPoint(x: 5, y: 5)))    // corner, outside
    }

    @Test("Line: point near segment hits, far from segment misses")
    func line() {
        // Horizontal line from (0,50) to (100,50), thickness 4, hit-tolerance = thickness/2 + 4
        let layer = AnnotationLayer.line(LineProps(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 100, y: 50), color: .red, thickness: 4))
        #expect(HitTest.contains(layer, point: CGPoint(x: 50, y: 51)))   // very close
        #expect(!HitTest.contains(layer, point: CGPoint(x: 50, y: 80)))  // 30pt away
    }

    @Test("Arrow: same hit logic as line")
    func arrow() {
        let layer = AnnotationLayer.arrow(ArrowProps(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), color: .red, thickness: 2, doubleHeaded: false))
        #expect(HitTest.contains(layer, point: CGPoint(x: 50, y: 1)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 50, y: 50)))
    }

    @Test("Text: hits inside the text bounding rect")
    func text() {
        let layer = AnnotationLayer.text(TextProps(origin: CGPoint(x: 100, y: 100), text: "Hello world",
                                                    color: .black, fontName: "Helvetica", fontSize: 24))
        #expect(HitTest.contains(layer, point: CGPoint(x: 105, y: 105)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 5, y: 5)))
    }

    @Test("Blur: hits inside the rect")
    func blur() {
        let layer = AnnotationLayer.blur(BlurProps(rect: CGRect(x: 50, y: 50, width: 30, height: 30),
                                                    style: .gaussian, intensity: 8))
        #expect(HitTest.contains(layer, point: CGPoint(x: 60, y: 60)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 10, y: 10)))
    }
}
