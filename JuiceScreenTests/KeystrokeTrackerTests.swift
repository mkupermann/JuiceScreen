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

    @Test("recentKeys with default now returns empty for fresh tracker")
    func recentKeysDefaultEmpty() {
        let tracker = KeystrokeTracker()
        #expect(tracker.recentKeys(now: Date()).isEmpty)
    }

    @Test("Single injected key is returned by recentKeys")
    func singleInjection() {
        let tracker = KeystrokeTracker()
        let now = Date()
        tracker._injectKeyForTesting(.init(label: "X", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.count == 1)
        #expect(keys.first?.label == "X")
    }

    @Test("Keys just inside the lifetime window are kept")
    func ttlWithinWindow() {
        let tracker = KeystrokeTracker(maxKeys: 5)
        let now = Date()
        // 2.0s ago is within the 2.5s lifetime window
        tracker._injectKeyForTesting(.init(label: "kept", timestamp: now.addingTimeInterval(-2.0)))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["kept"])
    }

    @Test("Keys just over the lifetime window are purged")
    func ttlJustOver() {
        let tracker = KeystrokeTracker(maxKeys: 5)
        let now = Date()
        // 3.0s ago is past the 2.5s lifetime window
        tracker._injectKeyForTesting(.init(label: "expired", timestamp: now.addingTimeInterval(-3.0)))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.isEmpty)
    }

    @Test("stop() is safe when no monitor was installed")
    func stopWithoutStart() {
        let tracker = KeystrokeTracker()
        // Should be a no-op and not crash.
        tracker.stop()
        tracker.stop()
        #expect(tracker.recentKeys().isEmpty)
    }

    @Test("Custom maxKeys cap retains only the most recent key")
    func customMaxKeysCap() {
        let tracker = KeystrokeTracker(maxKeys: 1)
        let now = Date()
        tracker._injectKeyForTesting(.init(label: "first", timestamp: now.addingTimeInterval(-1)))
        tracker._injectKeyForTesting(.init(label: "second", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["second"])
    }

    @Test("Key Equatable: same label and timestamp are equal")
    func keyEqualitySame() {
        let ts = Date()
        let a = KeystrokeTracker.Key(label: "A", timestamp: ts)
        let b = KeystrokeTracker.Key(label: "A", timestamp: ts)
        #expect(a == b)
    }

    @Test("Key Equatable: different label or timestamp are not equal")
    func keyEqualityDifferent() {
        let ts = Date()
        let a = KeystrokeTracker.Key(label: "A", timestamp: ts)
        let differentLabel = KeystrokeTracker.Key(label: "B", timestamp: ts)
        let differentTimestamp = KeystrokeTracker.Key(label: "A", timestamp: ts.addingTimeInterval(1))
        #expect(a != differentLabel)
        #expect(a != differentTimestamp)
    }
}
