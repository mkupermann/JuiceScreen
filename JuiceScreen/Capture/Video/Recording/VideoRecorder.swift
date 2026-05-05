import Foundation

@MainActor
public protocol VideoRecorder: AnyObject {
    var isRecording: Bool { get }
    var elapsed: TimeInterval { get }

    func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws
    func stop() async throws -> CaptureRecord
    func toggleMicrophoneMute()
}
