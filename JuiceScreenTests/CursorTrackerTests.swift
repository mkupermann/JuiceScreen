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

    @Test("start then stop covers timer setup and teardown")
    func startStop() async throws {
        let tracker = CursorTracker()
        tracker.start()
        // Let the 50Hz timer fire at least once. 30ms covers the 20ms interval.
        try await Task.sleep(nanoseconds: 30_000_000)
        _ = tracker.currentLocation   // must remain thread-safe under concurrent timer ticks
        tracker.stop()
        // Re-injection still works after stop (lock independent of timer state).
        tracker._setLocationForTesting(CGPoint(x: 1, y: 2))
        #expect(tracker.currentLocation == CGPoint(x: 1, y: 2))
    }

    @Test("start is idempotent — second call replaces the prior timer")
    func startIsIdempotent() {
        let tracker = CursorTracker()
        tracker.start()
        tracker.start()   // exercises stop+start path inside start()
        tracker.stop()
    }

    @Test("stop without start is a no-op")
    func stopWithoutStart() {
        let tracker = CursorTracker()
        tracker.stop()
        #expect(tracker.currentLocation == .zero)
    }
}
