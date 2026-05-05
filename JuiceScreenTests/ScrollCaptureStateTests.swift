import Foundation
import Testing
@testable import JuiceScreen

@Suite("ScrollCaptureState")
struct ScrollCaptureStateTests {

    @Test("Equatable across all cases")
    func equatable() {
        #expect(ScrollCaptureState.idle == .idle)
        #expect(ScrollCaptureState.collecting(framesCaptured: 5) == .collecting(framesCaptured: 5))
        #expect(ScrollCaptureState.collecting(framesCaptured: 5) != .collecting(framesCaptured: 6))
        #expect(ScrollCaptureState.stitching == .stitching)
        let url = URL(fileURLWithPath: "/tmp/x.png")
        #expect(ScrollCaptureState.done(fileURL: url) == .done(fileURL: url))
        #expect(ScrollCaptureState.failed(.userCancelled) == .failed(.userCancelled))
    }

    @Test("isActive true while collecting OR stitching")
    func isActive() {
        #expect(!ScrollCaptureState.idle.isActive)
        #expect(ScrollCaptureState.collecting(framesCaptured: 0).isActive)
        #expect(ScrollCaptureState.stitching.isActive)
        #expect(!ScrollCaptureState.done(fileURL: URL(fileURLWithPath: "/x")).isActive)
        #expect(!ScrollCaptureState.failed(.userCancelled).isActive)
    }
}
