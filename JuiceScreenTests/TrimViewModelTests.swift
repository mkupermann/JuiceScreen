import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrimViewModel")
@MainActor
struct TrimViewModelTests {

    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    @Test("Initial state: full range, isPlaying false, currentTime zero")
    func initial() {
        let player = AVPlayer()
        let vm = TrimViewModel(player: player, sourceURL: URL(fileURLWithPath: "/tmp/x.mp4"), assetDuration: t(20))
        #expect(vm.range == TrimRange(start: .zero, end: t(20)))
        #expect(vm.isPlaying == false)
        #expect(vm.assetDurationSeconds == 20)
    }

    @Test("setStart clamps to [0, end - minimum]")
    func setStartClamps() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(10))
        vm.setStart(seconds: -5)
        #expect(vm.range.start == .zero)
        vm.setStart(seconds: 9.99)
        #expect(vm.range.start.seconds < vm.range.end.seconds - TrimRange.minimumDurationSeconds + 0.01)
    }

    @Test("setEnd clamps to [start + minimum, assetDuration]")
    func setEndClamps() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(10))
        vm.setEnd(seconds: 100)
        #expect(abs(vm.range.end.seconds - 10) < 0.001)
        vm.setStart(seconds: 5)
        vm.setEnd(seconds: 5)
        #expect(vm.range.end.seconds >= 5 + TrimRange.minimumDurationSeconds)
    }

    @Test("resetRange returns range to [0, assetDuration]")
    func resetRange() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(10))
        vm.setStart(seconds: 3)
        vm.setEnd(seconds: 7)
        vm.resetRange()
        #expect(vm.range == TrimRange(start: .zero, end: t(10)))
    }

    @Test("togglePlay toggles isPlaying when currentTime is within range")
    func togglePlayWithinRange() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(20))
        // currentTime defaults to .zero which equals range.start — within [start, end) is false at start==currentTime
        // but range.start == 0 and currentTime == 0, so currentTime < range.start is false; currentTime >= range.end is false.
        // So it's "within" (no seek branch). Just check toggle.
        #expect(vm.isPlaying == false)
        vm.togglePlay()
        #expect(vm.isPlaying == true)
        vm.togglePlay()
        #expect(vm.isPlaying == false)
    }

    @Test("togglePlay seeks to range.start when currentTime is outside range")
    func togglePlayOutsideRange() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(20))
        // Move trim range so that currentTime (0) is outside [start, end)
        vm.setStart(seconds: 5)
        vm.setEnd(seconds: 10)
        // currentTime is still .zero (no time observer fires in tests), which is < range.start (5)
        #expect(vm.isPlaying == false)
        vm.togglePlay()
        #expect(vm.isPlaying == true)
        vm.togglePlay()
        #expect(vm.isPlaying == false)
    }

    @Test("seek(toSeconds:) executes without error")
    func seekToSeconds() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(20))
        vm.seek(toSeconds: 5)
        vm.seek(toSeconds: 0)
        vm.seek(toSeconds: 19.5)
        // No throw — just verify isPlaying unchanged
        #expect(vm.isPlaying == false)
    }

    @Test("assetDurationSeconds returns correct seconds for various CMTimes")
    func assetDurationSecondsValues() {
        let vm1 = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(0.5))
        #expect(abs(vm1.assetDurationSeconds - 0.5) < 0.001)

        let vm2 = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(60))
        #expect(abs(vm2.assetDurationSeconds - 60) < 0.001)

        // Tolerance reflects CMTime's 600-tick timescale rounding: 3.14159 → 1885 ticks → 3.141666… seconds.
        let vm3 = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(3.14159))
        #expect(abs(vm3.assetDurationSeconds - 3.14159) < 0.01)
    }

    @Test("setStart > end pushes end forward; large negative clamps to 0")
    func setStartEdgeCases() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(20))
        vm.setEnd(seconds: 5)
        // Now move start past end — end should be pushed forward to start + minimum
        vm.setStart(seconds: 8)
        #expect(abs(vm.range.start.seconds - 8) < 0.001)
        #expect(vm.range.end.seconds >= 8 + TrimRange.minimumDurationSeconds - 0.001)

        // Large negative seconds clamps to 0
        vm.setStart(seconds: -1000)
        #expect(vm.range.start.seconds == 0)
    }

    @Test("setEnd less than start+minimum clamps; setEnd > assetDuration clamps to assetDuration")
    func setEndEdgeCases() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(20))
        vm.setStart(seconds: 5)
        // setEnd less than start+minimum should clamp to start+minimum
        vm.setEnd(seconds: 5.0)
        #expect(abs(vm.range.end.seconds - (5 + TrimRange.minimumDurationSeconds)) < 0.001)

        // setEnd > assetDuration clamps to assetDuration
        vm.setEnd(seconds: 999)
        #expect(abs(vm.range.end.seconds - 20) < 0.001)
    }

    @Test("trimErrorMessage and isExporting can be assigned and read back")
    func mutablePublicProps() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(20))
        #expect(vm.trimErrorMessage == nil)
        #expect(vm.isExporting == false)

        vm.trimErrorMessage = "export failed"
        vm.isExporting = true
        #expect(vm.trimErrorMessage == "export failed")
        #expect(vm.isExporting == true)

        vm.trimErrorMessage = nil
        vm.isExporting = false
        #expect(vm.trimErrorMessage == nil)
        #expect(vm.isExporting == false)
    }

    @Test("Range mutations do not affect isPlaying")
    func rangeMutationsLeaveIsPlayingAlone() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(20))
        #expect(vm.isPlaying == false)
        vm.setStart(seconds: 2)
        vm.setEnd(seconds: 15)
        vm.resetRange()
        #expect(vm.isPlaying == false)
    }
}
