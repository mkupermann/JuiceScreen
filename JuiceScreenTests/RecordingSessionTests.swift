import Foundation
import Testing
@testable import JuiceScreen

@Suite("RecordingSession")
@MainActor
struct RecordingSessionTests {

    @Test("start kicks off recorder and creates UI")
    func start() async throws {
        let recorder = FakeVideoRecorder()
        let session = RecordingSession(recorder: recorder, onStopComplete: { _ in })
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        try await session.start(mode: .fullScreen, options: .defaults, outputURL: url)
        #expect(recorder.isRecording == true)
        #expect(session.isActive == true)
    }

    @Test("stop returns recorder result and calls completion handler")
    func stop() async throws {
        let recorder = FakeVideoRecorder()
        var receivedRecord: CaptureRecord?
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let expected = CaptureRecord(
            id: UUID(), fileURL: url, captureType: .fullScreen,
            capturedAt: Date(), pixelWidth: 1920, pixelHeight: 1080, sourceApp: nil
        )
        recorder.stopOutcome = .success(expected)

        let session = RecordingSession(recorder: recorder) { receivedRecord = $0 }
        try await session.start(mode: .fullScreen, options: .defaults, outputURL: url)
        try await session.stop()

        #expect(recorder.isRecording == false)
        #expect(session.isActive == false)
        #expect(receivedRecord?.id == expected.id)
    }
}
