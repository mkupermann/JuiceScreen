import Foundation

public struct VideoRecordingOptions: Equatable, Sendable {

    public var targetFps: Int
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool
    public var showCursorHighlight: Bool
    public var showClickPulse: Bool
    public var showKeystrokes: Bool

    public init(
        targetFps: Int,
        captureSystemAudio: Bool,
        captureMicrophone: Bool,
        showCursorHighlight: Bool,
        showClickPulse: Bool,
        showKeystrokes: Bool
    ) {
        self.targetFps = targetFps
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.showCursorHighlight = showCursorHighlight
        self.showClickPulse = showClickPulse
        self.showKeystrokes = showKeystrokes
    }

    public static let defaults = VideoRecordingOptions(
        targetFps: 60,
        captureSystemAudio: true,
        captureMicrophone: false,
        showCursorHighlight: true,
        showClickPulse: false,
        showKeystrokes: false
    )

    /// True if the user has enabled any feature that requires Input Monitoring TCC.
    public var requiresInputMonitoring: Bool {
        showClickPulse || showKeystrokes
    }
}
