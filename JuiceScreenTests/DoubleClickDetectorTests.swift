import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("DoubleClickDetector")
struct DoubleClickDetectorTests {

    @Test("The very first click never closes")
    func firstClickNeverCloses() {
        var d = DoubleClickDetector()
        let closes = d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0, interval: 0.5)
        #expect(closes == false)
    }

    @Test("Two clicks inside the interval and within the distance threshold close")
    func closesOnDoubleClick() {
        var d = DoubleClickDetector()
        #expect(d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0, interval: 0.5) == false)
        #expect(d.isSecondClick(at: CGPoint(x: 12, y: 10), time: 0.2, interval: 0.5) == true)
    }

    @Test("Two clicks outside the interval do not close")
    func doesNotCloseOutsideInterval() {
        var d = DoubleClickDetector()
        #expect(d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0, interval: 0.5) == false)
        #expect(d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0.6, interval: 0.5) == false)
    }

    @Test("Two clicks inside the interval but far apart do not close")
    func doesNotCloseWhenFarApart() {
        var d = DoubleClickDetector()
        #expect(d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0, interval: 0.5) == false)
        #expect(d.isSecondClick(at: CGPoint(x: 30, y: 10), time: 0.2, interval: 0.5) == false)
    }

    @Test("A third click after a detected close starts fresh rather than immediately closing")
    func startsFreshAfterClose() {
        var d = DoubleClickDetector()
        #expect(d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0, interval: 0.5) == false)
        #expect(d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0.1, interval: 0.5) == true)
        #expect(d.isSecondClick(at: CGPoint(x: 10, y: 10), time: 0.15, interval: 0.5) == false)
    }

    @Test("A click exactly at the distance threshold closes")
    func exactDistanceThresholdCloses() {
        var d = DoubleClickDetector()
        #expect(d.isSecondClick(at: CGPoint(x: 0, y: 0), time: 0, interval: 0.5) == false)
        #expect(d.isSecondClick(at: CGPoint(x: 4, y: 0), time: 0.1, interval: 0.5) == true)
    }

    @Test("A click just past the distance threshold does not close")
    func justPastDistanceThresholdDoesNotClose() {
        var d = DoubleClickDetector()
        #expect(d.isSecondClick(at: CGPoint(x: 0, y: 0), time: 0, interval: 0.5) == false)
        #expect(d.isSecondClick(at: CGPoint(x: 4.1, y: 0), time: 0.1, interval: 0.5) == false)
    }
}
