import Foundation
import Testing
@testable import JuiceScreen

@Suite("KeystrokeTracker")
struct KeystrokeTrackerTests {

    @Test("Initial recent keys is empty")
    func initial() {
        let tracker = KeystrokeTracker()
        #expect(tracker.recentKeys().isEmpty)
    }

    @Test("Injected keys appear in recentKeys, oldest first, capped at maxKeys")
    func injectAndCap() {
        let tracker = KeystrokeTracker(maxKeys: 3)
        let now = Date()
        tracker._injectKeyForTesting(.init(label: "a", timestamp: now.addingTimeInterval(-3)))
        tracker._injectKeyForTesting(.init(label: "b", timestamp: now.addingTimeInterval(-2)))
        tracker._injectKeyForTesting(.init(label: "c", timestamp: now.addingTimeInterval(-1)))
        tracker._injectKeyForTesting(.init(label: "d", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["b", "c", "d"])
    }

    @Test("Keys older than lifetime are pruned")
    func ttl() {
        let tracker = KeystrokeTracker(maxKeys: 5)
        let now = Date()
        tracker._injectKeyForTesting(.init(label: "old", timestamp: now.addingTimeInterval(-10)))
        tracker._injectKeyForTesting(.init(label: "new", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["new"])
    }
}
