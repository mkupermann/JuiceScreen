import AppKit
import AVFoundation
import CoreGraphics
import IOKit.hid

public final class PermissionsServiceLive: PermissionsService {

    private let log = AppLog.logger(category: "PermissionsServiceLive")

    public init() {}

    public func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .screenRecording: return screenRecordingStatus()
        case .microphone:      return microphoneStatus()
        case .inputMonitoring: return inputMonitoringStatus()
        }
    }

    public func request(_ permission: PermissionType) async -> PermissionStatus {
        switch permission {
        case .screenRecording: return await requestScreenRecording()
        case .microphone:      return await requestMicrophone()
        case .inputMonitoring: return await requestInputMonitoring()
        }
    }

    public func openSettings(for permission: PermissionType) {
        SettingsDeepLink.open(permission)
    }

    // MARK: - Screen Recording

    private func screenRecordingStatus() -> PermissionStatus {
        // CGPreflightScreenCaptureAccess returns false if denied or notDetermined.
        // There is no public API to distinguish denied from notDetermined for
        // screen recording — Apple does not expose a TCC status query for it.
        // We treat false as `.denied` because the user-visible recovery is the same:
        // open System Settings and toggle the permission.
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }
        return .denied
    }

    private func requestScreenRecording() async -> PermissionStatus {
        // CGRequestScreenCaptureAccess triggers the TCC prompt the FIRST time only.
        // Subsequent calls when status is denied do nothing. The user then must
        // visit System Settings — handled by openSettings(for:).
        let granted = CGRequestScreenCaptureAccess()
        return granted ? .granted : .denied
    }

    // MARK: - Microphone

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined
        }
    }

    private func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    // MARK: - Input Monitoring

    private func inputMonitoringStatus() -> PermissionStatus {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        case kIOHIDAccessTypeUnknown:
            return .notDetermined
        default:
            return .notDetermined
        }
    }

    private func requestInputMonitoring() async -> PermissionStatus {
        // IOHIDRequestAccess is synchronous and triggers the TCC prompt on first call.
        // Subsequent calls when denied do nothing — same as Screen Recording.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        return granted ? .granted : .denied
    }
}
