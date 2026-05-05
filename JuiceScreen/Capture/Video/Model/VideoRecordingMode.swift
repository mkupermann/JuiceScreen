import CoreGraphics

public enum VideoRecordingMode: Equatable, Sendable {
    case fullScreen
    case region(CGRect)
}
