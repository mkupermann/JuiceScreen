import CoreMedia
import Foundation

public struct TrimRange: Equatable, Sendable {
    public var start: CMTime
    public var end: CMTime

    public static let minimumDurationSeconds: Double = 0.1

    public init(start: CMTime, end: CMTime) {
        self.start = start
        self.end = end
    }

    public var durationSeconds: Double {
        let s = CMTimeGetSeconds(start)
        let e = CMTimeGetSeconds(end)
        guard s.isFinite, e.isFinite else { return 0 }
        return max(0, e - s)
    }

    public var isValid: Bool {
        durationSeconds >= TrimRange.minimumDurationSeconds
    }

    public var asCMTimeRange: CMTimeRange {
        CMTimeRange(start: start, end: end)
    }

    public func clamped(toAssetDuration assetDuration: CMTime) -> TrimRange {
        let zero = CMTime.zero
        let clampedStart = CMTimeMaximum(start, zero)
        let clampedEnd = CMTimeMinimum(end, assetDuration)
        return TrimRange(start: clampedStart, end: clampedEnd)
    }
}
