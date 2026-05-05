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
}
