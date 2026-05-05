import Foundation

@MainActor
public final class FakeVideoRecorder: VideoRecorder {

    public typealias Outcome = Result<CaptureRecord, VideoRecordingError>

    public private(set) var isRecording: Bool = false
    public var elapsed: TimeInterval = 0
    public var stopOutcome: Outcome = .failure(.streamFailed("not configured"))
    public private(set) var lastMode: VideoRecordingMode?
    public private(set) var lastOptions: VideoRecordingOptions?

    public init() {}

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        lastMode = mode
        lastOptions = options
        isRecording = true
    }

    public func stop() async throws -> CaptureRecord {
        isRecording = false
        switch stopOutcome {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    public func toggleMicrophoneMute() {
        // no-op for tests; can be observed via lastOptions in future
    }
}
