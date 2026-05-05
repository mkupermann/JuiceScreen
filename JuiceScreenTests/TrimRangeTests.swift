import CoreMedia
import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrimRange")
struct TrimRangeTests {

    private func t(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    @Test("Constructor stores start and end")
    func storage() {
        let range = TrimRange(start: t(2), end: t(10))
        #expect(range.start == t(2))
        #expect(range.end == t(10))
    }

    @Test("durationSeconds == end - start")
    func duration() {
        let range = TrimRange(start: t(2), end: t(10.5))
        #expect(abs(range.durationSeconds - 8.5) < 0.001)
    }

    @Test("isValid: end > start AND duration >= minimum (0.1s)")
    func validity() {
        #expect(TrimRange(start: t(0), end: t(1)).isValid)
        #expect(TrimRange(start: t(2), end: t(10)).isValid)
        #expect(!TrimRange(start: t(5), end: t(5)).isValid)        // zero-duration
        #expect(!TrimRange(start: t(5), end: t(4)).isValid)        // inverted
        #expect(!TrimRange(start: t(0), end: t(0.05)).isValid)     // below minimum
    }

    @Test("clamped(toAssetDuration:) returns range bounded by asset")
    func clamping() {
        let assetDuration = t(20)
        let range = TrimRange(start: t(-5), end: t(30)).clamped(toAssetDuration: assetDuration)
        #expect(range.start == .zero)
        #expect(range.end == t(20))
    }

    @Test("Equatable")
    func equality() {
        let a = TrimRange(start: t(1), end: t(5))
        let b = TrimRange(start: t(1), end: t(5))
        let c = TrimRange(start: t(1), end: t(6))
        #expect(a == b)
        #expect(a != c)
    }
}
