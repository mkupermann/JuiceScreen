import CoreGraphics
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

    @Test("stop() before start() is a no-op and does not throw")
    func stopBeforeStart() async throws {
        let recorder = FakeVideoRecorder()
        var completionCallCount = 0
        let session = RecordingSession(recorder: recorder) { _ in completionCallCount += 1 }

        // Should NOT throw; should just log and return after deferred cleanup.
        try await session.stop()

        #expect(session.isActive == false)
        #expect(recorder.isRecording == false)
        #expect(completionCallCount == 0)
    }

    @Test("stop() rethrows recorder.stop failure and still tears down state")
    func stopPropagatesRecorderError() async throws {
        let recorder = FakeVideoRecorder()
        var completionCallCount = 0
        let url = URL(fileURLWithPath: "/tmp/fail.mp4")
        let session = RecordingSession(recorder: recorder) { _ in completionCallCount += 1 }

        try await session.start(mode: .fullScreen, options: .defaults, outputURL: url)
        recorder.stopOutcome = .failure(.writeFailed("disk full"))

        await #expect(throws: VideoRecordingError.writeFailed("disk full")) {
            try await session.stop()
        }

        // Completion must not fire on failure; deferred cleanup still flips recorder state.
        #expect(completionCallCount == 0)
        #expect(session.isActive == false)
    }

    @Test("start() rethrows recorder.start failure and leaves session inactive")
    func startPropagatesRecorderError() async throws {
        let recorder = ThrowingStartRecorder(error: .missingScreenRecordingPermission)
        let session = RecordingSession(recorder: recorder, onStopComplete: { _ in })
        let url = URL(fileURLWithPath: "/tmp/nope.mp4")

        await #expect(throws: VideoRecordingError.missingScreenRecordingPermission) {
            try await session.start(mode: .fullScreen, options: .defaults, outputURL: url)
        }

        // No zombie UI / no recording: isActive must remain false.
        #expect(session.isActive == false)
        #expect(recorder.isRecording == false)
    }

    @Test("calling start() twice still leaves session active and recorder configured with latest options")
    func startTwice() async throws {
        let recorder = FakeVideoRecorder()
        let session = RecordingSession(recorder: recorder, onStopComplete: { _ in })
        let url = URL(fileURLWithPath: "/tmp/twice.mp4")

        let secondMode: VideoRecordingMode = .region(CGRect(x: 0, y: 0, width: 100, height: 100))
        try await session.start(mode: .fullScreen, options: .defaults, outputURL: url)
        try await session.start(mode: secondMode, options: .defaults, outputURL: url)

        #expect(session.isActive == true)
        #expect(recorder.lastMode == secondMode)
    }

    @Test("isActive reflects the recorder's isRecording flag")
    func isActiveDelegates() async throws {
        let recorder = FakeVideoRecorder()
        let session = RecordingSession(recorder: recorder, onStopComplete: { _ in })

        #expect(session.isActive == false)

        try await recorder.start(mode: .fullScreen, options: .defaults, outputURL: URL(fileURLWithPath: "/tmp/d.mp4"))
        #expect(session.isActive == true)

        recorder.stopOutcome = .success(CaptureRecord(
            id: UUID(), fileURL: URL(fileURLWithPath: "/tmp/d.mp4"), captureType: .fullScreen,
            capturedAt: Date(), pixelWidth: 1, pixelHeight: 1, sourceApp: nil
        ))
        _ = try await recorder.stop()
        #expect(session.isActive == false)
    }
}

/// Local mock that throws from `start()` — used to drive the
/// "no zombie control bar" branch in `RecordingSession.start`.
@MainActor
private final class ThrowingStartRecorder: VideoRecorder {
    var isRecording: Bool = false
    var elapsed: TimeInterval = 0
    let error: VideoRecordingError

    init(error: VideoRecordingError) { self.error = error }

    func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        throw error
    }

    func stop() async throws -> CaptureRecord {
        throw error
    }

    func toggleMicrophoneMute() {}
}
