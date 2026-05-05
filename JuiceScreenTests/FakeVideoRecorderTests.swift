import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeVideoRecorder")
@MainActor
struct FakeVideoRecorderTests {

    @Test("Idle by default")
    func idle() {
        let r = FakeVideoRecorder()
        #expect(r.isRecording == false)
    }

    @Test("start switches to recording; stop returns the configured outcome")
    func startStop() async throws {
        let r = FakeVideoRecorder()
        let url = URL(fileURLWithPath: "/tmp/fake.mp4")
        let resultRecord = CaptureRecord(
            id: UUID(), fileURL: url, captureType: .fullScreen,
            capturedAt: Date(), pixelWidth: 1920, pixelHeight: 1080, sourceApp: nil
        )
        r.stopOutcome = .success(resultRecord)

        try await r.start(mode: .fullScreen, options: .defaults, outputURL: url)
        #expect(r.isRecording == true)

        let returned = try await r.stop()
        #expect(r.isRecording == false)
        #expect(returned.id == resultRecord.id)
    }

    @Test("stop throws the configured error")
    func stopError() async {
        let r = FakeVideoRecorder()
        try? await r.start(mode: .fullScreen, options: .defaults, outputURL: URL(fileURLWithPath: "/tmp/x.mp4"))
        r.stopOutcome = .failure(.streamFailed("boom"))
        await #expect(throws: VideoRecordingError.self) {
            _ = try await r.stop()
        }
    }
}
