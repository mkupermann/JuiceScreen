import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("RegionSelection")
struct RegionSelectionTests {

    @Test("Normalizes drag from top-left to bottom-right")
    func topLeftToBottomRight() {
        let s = RegionSelection(start: CGPoint(x: 10, y: 20), current: CGPoint(x: 110, y: 220))
        #expect(s.normalized == CGRect(x: 10, y: 20, width: 100, height: 200))
    }

    @Test("Normalizes drag from bottom-right to top-left (negative width/height)")
    func bottomRightToTopLeft() {
        let s = RegionSelection(start: CGPoint(x: 110, y: 220), current: CGPoint(x: 10, y: 20))
        #expect(s.normalized == CGRect(x: 10, y: 20, width: 100, height: 200))
    }

    @Test("Zero-area when start == current")
    func zeroArea() {
        let s = RegionSelection(start: CGPoint(x: 50, y: 50), current: CGPoint(x: 50, y: 50))
        #expect(s.normalized == CGRect(x: 50, y: 50, width: 0, height: 0))
    }

    @Test("isUsable false for zero-area selection")
    func zeroNotUsable() {
        let s = RegionSelection(start: .zero, current: .zero)
        #expect(s.isUsable == false)
    }

    @Test("isUsable true for >= 1x1 selection")
    func oneByOneUsable() {
        let s = RegionSelection(start: .zero, current: CGPoint(x: 1, y: 1))
        #expect(s.isUsable == true)
    }

    @Test("Nudging by an offset translates start and current equally")
    func nudge() {
        let s = RegionSelection(start: CGPoint(x: 10, y: 10), current: CGPoint(x: 30, y: 50))
        let n = s.nudged(by: CGSize(width: 5, height: -3))
        #expect(n.normalized == CGRect(x: 15, y: 7, width: 20, height: 40))
    }
}
