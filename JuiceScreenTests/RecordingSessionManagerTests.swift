import Foundation
import Testing
@testable import JuiceScreen

@Suite("RecordingSessionManager")
@MainActor
struct RecordingSessionManagerTests {

    private static let outputURL = URL(fileURLWithPath: "/tmp/x.mp4")

    private static func successRecord(url: URL = outputURL) -> CaptureRecord {
        CaptureRecord(
            id: UUID(),
            fileURL: url,
            captureType: .fullScreen,
            capturedAt: Date(),
            pixelWidth: 1920,
            pixelHeight: 1080,
            sourceApp: nil
        )
    }

    @Test("isActive is false on a freshly initialized manager")
    func initiallyInactive() {
        let manager = RecordingSessionManager(
            recorderFactory: { FakeVideoRecorder() },
            onStopComplete: { _ in }
        )
        #expect(manager.isActive == false)
    }

    @Test("start() flips isActive to true")
    func startActivates() async throws {
        let manager = RecordingSessionManager(
            recorderFactory: { FakeVideoRecorder() },
            onStopComplete: { _ in }
        )
        try await manager.start(mode: .fullScreen, options: .defaults, outputURL: Self.outputURL)
        #expect(manager.isActive == true)
    }

    @Test("start() while active is a no-op and does not spawn a new recorder")
    func startWhileActiveIsNoop() async throws {
        var factoryCount = 0
        let factory: () -> VideoRecorder = {
            factoryCount += 1
            let recorder = FakeVideoRecorder()
            recorder.stopOutcome = .success(Self.successRecord())
            return recorder
        }
        let manager = RecordingSessionManager(
            recorderFactory: factory,
            onStopComplete: { _ in }
        )

        try await manager.start(mode: .fullScreen, options: .defaults, outputURL: Self.outputURL)
        // Second start should hit the early return; must not throw.
        try await manager.start(mode: .fullScreen, options: .defaults, outputURL: Self.outputURL)

        #expect(manager.isActive == true)
        #expect(factoryCount == 1)
    }

    @Test("stop() ends the session and flips isActive back to false")
    func stopEndsSession() async throws {
        let recorder = FakeVideoRecorder()
        recorder.stopOutcome = .success(Self.successRecord())
        let manager = RecordingSessionManager(
            recorderFactory: { recorder },
            onStopComplete: { _ in }
        )

        try await manager.start(mode: .fullScreen, options: .defaults, outputURL: Self.outputURL)
        try await manager.stop()

        #expect(manager.isActive == false)
    }

    @Test("onStopComplete callback fires once with the recorder's stopOutcome record")
    func onStopCompleteWiresThrough() async throws {
        let expected = Self.successRecord()
        let recorder = FakeVideoRecorder()
        recorder.stopOutcome = .success(expected)

        var receivedRecords: [CaptureRecord] = []
        let manager = RecordingSessionManager(
            recorderFactory: { recorder },
            onStopComplete: { receivedRecords.append($0) }
        )

        try await manager.start(mode: .fullScreen, options: .defaults, outputURL: Self.outputURL)
        try await manager.stop()

        #expect(receivedRecords.count == 1)
        #expect(receivedRecords.first?.id == expected.id)
    }

    @Test("stop() on a fresh manager with no active session is a no-op")
    func stopWithoutStartIsNoop() async throws {
        var callbackInvocations = 0
        let manager = RecordingSessionManager(
            recorderFactory: { FakeVideoRecorder() },
            onStopComplete: { _ in callbackInvocations += 1 }
        )

        try await manager.stop()

        #expect(manager.isActive == false)
        #expect(callbackInvocations == 0)
    }

    @Test("start -> stop -> start cycle creates a fresh recorder for the second session")
    func sequentialStartStopStart() async throws {
        var factoryCount = 0
        let factory: () -> VideoRecorder = {
            factoryCount += 1
            let recorder = FakeVideoRecorder()
            recorder.stopOutcome = .success(Self.successRecord())
            return recorder
        }
        let manager = RecordingSessionManager(
            recorderFactory: factory,
            onStopComplete: { _ in }
        )

        try await manager.start(mode: .fullScreen, options: .defaults, outputURL: Self.outputURL)
        try await manager.stop()
        #expect(manager.isActive == false)

        try await manager.start(mode: .fullScreen, options: .defaults, outputURL: Self.outputURL)
        #expect(manager.isActive == true)
        #expect(factoryCount == 2)
    }
}
