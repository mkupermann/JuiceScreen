import Foundation

public enum CaptureError: Error, Equatable {
    case missingScreenRecordingPermission
    case userCancelled
    case noDisplaysAvailable
    case captureFailed(underlying: String)
    case regionOutsideDisplays
    case writeFailed(underlying: String)
}
