import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FreeformSelection")
struct FreeformSelectionTests {

    @Test("Freehand append drops points closer than the minimum spacing")
    func minimumSpacing() {
        var s = FreeformSelection(mode: .freehand)
        s.append(CGPoint(x: 0, y: 0))
        s.append(CGPoint(x: 1, y: 0))     // 1pt away — dropped
        s.append(CGPoint(x: 2, y: 0))     // 2pt from the first kept point — kept
        #expect(s.points == [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0)])
    }

    @Test("Polygon vertices are never distance-filtered")
    func polygonKeepsEveryVertex() {
        var s = FreeformSelection(mode: .polygon)
        s.appendVertex(CGPoint(x: 0, y: 0))
        s.appendVertex(CGPoint(x: 1, y: 0))
        s.appendVertex(CGPoint(x: 1, y: 1))
        #expect(s.points.count == 3)
    }

    @Test("removeLastVertex undoes one point and is safe when empty")
    func undoVertex() {
        var s = FreeformSelection(mode: .polygon)
        s.appendVertex(CGPoint(x: 5, y: 5))
        s.removeLastVertex()
        #expect(s.points.isEmpty)
        s.removeLastVertex()          // must not trap
        #expect(s.points.isEmpty)
    }

    @Test("bounds is the outward-rounded box around all points")
    func boundsRoundOutward() {
        var s = FreeformSelection(mode: .polygon)
        s.appendVertex(CGPoint(x: 10.4, y: 20.7))
        s.appendVertex(CGPoint(x: 50.2, y: 20.7))
        s.appendVertex(CGPoint(x: 30.0, y: 60.1))
        #expect(s.bounds == CGRect(x: 10, y: 20, width: 41, height: 41))
    }

    @Test("bounds is identical whichever direction the shape is drawn")
    func boundsDirectionIndependent() {
        var a = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 30)] { a.appendVertex(p) }
        var b = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 40, y: 30), CGPoint(x: 40, y: 0), CGPoint(x: 0, y: 0)] { b.appendVertex(p) }
        #expect(a.bounds == b.bounds)
    }

    @Test("isUsable requires three points and a box of at least 1x1")
    func usability() {
        var two = FreeformSelection(mode: .polygon)
        two.appendVertex(CGPoint(x: 0, y: 0))
        two.appendVertex(CGPoint(x: 10, y: 10))
        #expect(two.isUsable == false)

        var degenerate = FreeformSelection(mode: .polygon)
        for _ in 0..<3 { degenerate.appendVertex(CGPoint(x: 7, y: 7)) }
        #expect(degenerate.isUsable == false)

        var ok = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 4)] { ok.appendVertex(p) }
        #expect(ok.isUsable == true)
    }

    @Test("pathInBounds is the closed path translated to the bounds origin")
    func pathInBoundsTranslation() {
        var s = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 100, y: 200), CGPoint(x: 140, y: 200), CGPoint(x: 140, y: 230)] {
            s.appendVertex(p)
        }
        #expect(s.bounds.origin == CGPoint(x: 100, y: 200))
        #expect(s.pathInBounds.boundingBox.origin.x == 0)
        #expect(s.pathInBounds.boundingBox.origin.y == 0)
        #expect(s.closedPath.isEmpty == false)
    }

    @Test("Mode can be switched only before the first point")
    func modeLock() {
        var s = FreeformSelection(mode: .freehand)
        s.setMode(.polygon)
        #expect(s.mode == .polygon)
        s.appendVertex(CGPoint(x: 1, y: 1))
        s.setMode(.freehand)
        #expect(s.mode == .polygon)
    }
}
