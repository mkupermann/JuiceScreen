import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CursorTracker")
struct CursorTrackerTests {

    @Test("Initial currentLocation is .zero")
    func initialLocation() {
        let tracker = CursorTracker()
        #expect(tracker.currentLocation == .zero)
    }

    @Test("Manually-injected location updates currentLocation")
    func manualUpdate() {
        let tracker = CursorTracker()
        tracker._setLocationForTesting(CGPoint(x: 100, y: 200))
        #expect(tracker.currentLocation == CGPoint(x: 100, y: 200))
    }
}
