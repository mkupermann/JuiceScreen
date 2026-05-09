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

    @Test("maxKeys cap with all-fresh keys keeps only the most recent N")
    func capWithAllFreshKeys() {
        let tracker = KeystrokeTracker(maxKeys: 2)
        let now = Date()
        // Inject 5 keys all within the lifetime window.
        tracker._injectKeyForTesting(.init(label: "1", timestamp: now.addingTimeInterval(-2.0)))
        tracker._injectKeyForTesting(.init(label: "2", timestamp: now.addingTimeInterval(-1.5)))
        tracker._injectKeyForTesting(.init(label: "3", timestamp: now.addingTimeInterval(-1.0)))
        tracker._injectKeyForTesting(.init(label: "4", timestamp: now.addingTimeInterval(-0.5)))
        tracker._injectKeyForTesting(.init(label: "5", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["4", "5"])
    }

    @Test("purgeLocked: mixed old + fresh keys with cap drops old then enforces cap")
    func mixedOldFreshOverCap() {
        let tracker = KeystrokeTracker(maxKeys: 3)
        let now = Date()
        // 2 old (beyond lifetime) + 4 fresh.
        tracker._injectKeyForTesting(.init(label: "old1", timestamp: now.addingTimeInterval(-10)))
        tracker._injectKeyForTesting(.init(label: "old2", timestamp: now.addingTimeInterval(-5)))
        tracker._injectKeyForTesting(.init(label: "f1", timestamp: now.addingTimeInterval(-2.0)))
        tracker._injectKeyForTesting(.init(label: "f2", timestamp: now.addingTimeInterval(-1.5)))
        tracker._injectKeyForTesting(.init(label: "f3", timestamp: now.addingTimeInterval(-1.0)))
        tracker._injectKeyForTesting(.init(label: "f4", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["f2", "f3", "f4"])
    }

    @Test("now: boundary — within 2.5s kept, just past purged")
    func nowBoundary() {
        let tracker = KeystrokeTracker(maxKeys: 5)
        let injected = Date()
        tracker._injectKeyForTesting(.init(label: "k", timestamp: injected))

        // Within the lifetime window (2.4s elapsed): kept.
        let withinKeys = tracker.recentKeys(now: injected.addingTimeInterval(2.4))
        #expect(withinKeys.map { $0.label } == ["k"])

        // Just past the lifetime window (2.6s elapsed): purged.
        let pastKeys = tracker.recentKeys(now: injected.addingTimeInterval(2.6))
        #expect(pastKeys.isEmpty)
    }

    @Test("init(maxKeys: 0) drops all injected keys")
    func zeroMaxKeys() {
        let tracker = KeystrokeTracker(maxKeys: 0)
        let now = Date()
        tracker._injectKeyForTesting(.init(label: "x", timestamp: now))

        #expect(tracker.recentKeys(now: now).isEmpty)
    }

    @Test("Self.lifetime equals 2.5 seconds")
    func lifetimeConstant() {
        #expect(KeystrokeTracker.lifetime == 2.5)
    }

    @Test("Multiple stop() calls in a row are safe")
    func multipleStopCalls() {
        let tracker = KeystrokeTracker()
        tracker.stop()
        tracker.stop()
        tracker.stop()
        #expect(tracker.recentKeys().isEmpty)
    }

    @Test("recentKeys() with default now returns recently-injected key")
    func recentKeysDefaultNow() {
        let tracker = KeystrokeTracker()
        tracker._injectKeyForTesting(.init(label: "fresh", timestamp: Date()))

        let keys = tracker.recentKeys()
        #expect(keys.map { $0.label } == ["fresh"])
    }
}
