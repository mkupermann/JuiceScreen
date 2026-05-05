import Foundation

@MainActor
public final class RecordingSessionManager {

    private let recorderFactory: () -> VideoRecorder
    private let onStopComplete: (CaptureRecord) -> Void
    private var session: RecordingSession?

    public init(
        recorderFactory: @escaping () -> VideoRecorder,
        onStopComplete: @escaping (CaptureRecord) -> Void
    ) {
        self.recorderFactory = recorderFactory
        self.onStopComplete = onStopComplete
    }

    public var isActive: Bool { session?.isActive == true }

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        if isActive { return }
        let recorder = recorderFactory()
        let session = RecordingSession(recorder: recorder) { [weak self] record in
            self?.session = nil
            self?.onStopComplete(record)
        }
        self.session = session
        try await session.start(mode: mode, options: options, outputURL: outputURL)
    }

    public func stop() async throws {
        guard let session else { return }
        try await session.stop()
    }
}
