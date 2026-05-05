import Foundation

public enum VideoRecordingError: Error, Equatable {
    case missingScreenRecordingPermission
    case missingMicrophonePermission
    case missingInputMonitoringPermission
    case userCancelled
    case noDisplaysAvailable
    case streamConfigurationFailed(String)
    case writerSetupFailed(String)
    case streamFailed(String)
    case writeFailed(String)
}
