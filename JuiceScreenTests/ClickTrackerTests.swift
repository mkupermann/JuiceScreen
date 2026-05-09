import Foundation
import Testing
@testable import JuiceScreen

@Suite("ClickTracker")
struct ClickTrackerTests {

    @Test("Initial recentClicks is empty")
    func initial() {
        let tracker = ClickTracker()
        #expect(tracker.recentClicks().isEmpty)
        #expect(tracker.recentClicks(now: Date()).isEmpty)
    }

    @Test("Single injected click is returned by recentClicks")
    func singleInjection() {
        let tracker = ClickTracker()
        let now = Date()
        tracker._injectClickForTesting(.init(location: CGPoint(x: 10, y: 20), timestamp: now))

        let clicks = tracker.recentClicks(now: now)
        #expect(clicks.count == 1)
        #expect(clicks.first?.location == CGPoint(x: 10, y: 20))
        #expect(clicks.first?.timestamp == now)
    }

    @Test("Multiple injections preserve insertion order")
    func multipleInjectionsOrder() {
        let tracker = ClickTracker()
        let now = Date()
        let a = ClickTracker.Click(location: CGPoint(x: 1, y: 1), timestamp: now.addingTimeInterval(-0.3))
        let b = ClickTracker.Click(location: CGPoint(x: 2, y: 2), timestamp: now.addingTimeInterval(-0.2))
        let c = ClickTracker.Click(location: CGPoint(x: 3, y: 3), timestamp: now.addingTimeInterval(-0.1))
        tracker._injectClickForTesting(a)
        tracker._injectClickForTesting(b)
        tracker._injectClickForTesting(c)

        let clicks = tracker.recentClicks(now: now)
        #expect(clicks == [a, b, c])
    }

    @Test("Clicks older than clickLifetime are purged")
    func ttlPurges() {
        let tracker = ClickTracker()
        let now = Date()
        tracker._injectClickForTesting(.init(location: CGPoint(x: 5, y: 5), timestamp: Date(timeIntervalSinceNow: -1.0)))

        let clicks = tracker.recentClicks(now: now)
        #expect(clicks.isEmpty)
    }

    @Test("Clicks within the lifetime window are kept")
    func ttlWithinWindow() {
        let tracker = ClickTracker()
        let now = Date()
        // 0.3s ago is within the 0.6s lifetime window.
        let kept = ClickTracker.Click(location: CGPoint(x: 7, y: 8), timestamp: now.addingTimeInterval(-0.3))
        tracker._injectClickForTesting(kept)

        let clicks = tracker.recentClicks(now: now)
        #expect(clicks == [kept])
    }

    @Test("Mixed expired and fresh: only fresh remain")
    func ttlMixed() {
        let tracker = ClickTracker()
        let now = Date()
        let expired = ClickTracker.Click(location: CGPoint(x: 0, y: 0), timestamp: now.addingTimeInterval(-1.0))
        let fresh = ClickTracker.Click(location: CGPoint(x: 9, y: 9), timestamp: now.addingTimeInterval(-0.1))
        tracker._injectClickForTesting(expired)
        tracker._injectClickForTesting(fresh)

        let clicks = tracker.recentClicks(now: now)
        #expect(clicks == [fresh])
    }

    @Test("stop() is safe when no monitor was installed")
    func stopWithoutStart() {
        let tracker = ClickTracker()
        // Should be a no-op and not crash.
        tracker.stop()
        tracker.stop()
        #expect(tracker.recentClicks().isEmpty)
    }

    @Test("Click Equatable: same location and timestamp are equal; differences are not")
    func clickEquality() {
        let ts = Date()
        let loc = CGPoint(x: 100, y: 200)
        let a = ClickTracker.Click(location: loc, timestamp: ts)
        let b = ClickTracker.Click(location: loc, timestamp: ts)
        let differentLocation = ClickTracker.Click(location: CGPoint(x: 101, y: 200), timestamp: ts)
        let differentTimestamp = ClickTracker.Click(location: loc, timestamp: ts.addingTimeInterval(1))

        #expect(a == b)
        #expect(a != differentLocation)
        #expect(a != differentTimestamp)
    }

    @Test("clickLifetime is exposed and equals 0.6")
    func clickLifetimeConstant() {
        #expect(ClickTracker.clickLifetime == 0.6)
    }
}
