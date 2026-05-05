import CoreGraphics
import Testing
@testable import JuiceScreen

@Suite("VideoRecordingMode")
struct VideoRecordingModeTests {

    @Test("fullScreen mode has no associated rect")
    func fullScreenHasNoRect() {
        let mode = VideoRecordingMode.fullScreen
        if case .region = mode {
            Issue.record("Expected fullScreen, got region")
        }
    }

    @Test("region mode carries CGRect")
    func regionCarriesRect() {
        let rect = CGRect(x: 10, y: 20, width: 640, height: 480)
        let mode = VideoRecordingMode.region(rect)
        guard case .region(let r) = mode else {
            Issue.record("Expected region, got fullScreen")
            return
        }
        #expect(r == rect)
    }

    @Test("Equatable: same cases equal, different rects not equal, fullScreen != region")
    func equatable() {
        let rect1 = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rect2 = CGRect(x: 0, y: 0, width: 200, height: 200)

        #expect(VideoRecordingMode.fullScreen == .fullScreen)
        #expect(VideoRecordingMode.region(rect1) == .region(rect1))
        #expect(VideoRecordingMode.region(rect1) != .region(rect2))
        #expect(VideoRecordingMode.fullScreen != .region(rect1))
    }
}
