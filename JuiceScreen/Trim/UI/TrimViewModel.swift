import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class TrimViewModel {

    public let player: AVPlayer
    public let sourceURL: URL
    public let assetDuration: CMTime

    public private(set) var range: TrimRange
    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: CMTime = .zero
    public var trimErrorMessage: String? = nil
    public var isExporting: Bool = false

    // Stored as nonisolated so deinit can access without MainActor hop.
    nonisolated(unsafe) private var timeObserver: Any?
    private let log = AppLog.logger(category: "TrimViewModel")

    public init(player: AVPlayer, sourceURL: URL, assetDuration: CMTime) {
        self.player = player
        self.sourceURL = sourceURL
        self.assetDuration = assetDuration
        self.range = TrimRange(start: .zero, end: assetDuration)
        installTimeObserver()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    public var assetDurationSeconds: Double {
        CMTimeGetSeconds(assetDuration)
    }

    // MARK: - Range mutations

    public func setStart(seconds: Double) {
        let target = max(0, min(seconds, assetDurationSeconds - TrimRange.minimumDurationSeconds))
        let endSeconds = max(target + TrimRange.minimumDurationSeconds, range.end.seconds)
        range = TrimRange(
            start: CMTime(seconds: target, preferredTimescale: 600),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )
        seek(toSeconds: target)
    }

    public func setEnd(seconds: Double) {
        let minEnd = range.start.seconds + TrimRange.minimumDurationSeconds
        let target = min(max(seconds, minEnd), assetDurationSeconds)
        range = TrimRange(
            start: range.start,
            end: CMTime(seconds: target, preferredTimescale: 600)
        )
        seek(toSeconds: target)
    }

    public func resetRange() {
        range = TrimRange(start: .zero, end: assetDuration)
    }

    // MARK: - Playback

    public func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            // Loop within trim range: seek to start if currentTime is outside it
            if currentTime < range.start || currentTime >= range.end {
                seek(toSeconds: range.start.seconds)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    public func seek(toSeconds seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Helpers

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time
                // Stop at end of trim range
                if self.isPlaying, time >= self.range.end {
                    self.player.pause()
                    self.isPlaying = false
                }
            }
        }
    }
}
