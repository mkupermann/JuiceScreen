import Foundation

public enum ScrollCaptureError: Error, Equatable {
    case missingScreenRecordingPermission
    case userCancelled
    case noFramesCaptured
    case stitchingFailed(String)
    case writeFailed(String)
    case streamConfigurationFailed(String)
}
