import Foundation

/// Status of a TCC permission as observed at a point in time.
public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Categories of TCC permissions JuiceScreen requests.
/// Accessibility (kTCCServiceAccessibility) is intentionally absent — see design spec §6.
public enum PermissionType: String, CaseIterable, Sendable {
    case screenRecording
    case microphone
    case inputMonitoring
}

/// Abstraction over macOS TCC. Live impl in `PermissionsServiceLive`.
/// Test impl in `FakePermissionsService` (test target).
public protocol PermissionsService: Sendable {
    func status(for permission: PermissionType) -> PermissionStatus

    /// Triggers the system permission prompt if `notDetermined`. No-op if already determined.
    func request(_ permission: PermissionType) async -> PermissionStatus

    /// Opens the appropriate System Settings pane for the user to toggle a permission manually.
    func openSettings(for permission: PermissionType)
}
