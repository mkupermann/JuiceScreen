import Foundation

/// Test double for `PermissionsService`. Mutable storage uses a lock for thread safety
/// because async tests may exercise it from multiple actors.
public final class FakePermissionsService: PermissionsService, @unchecked Sendable {

    private let lock = NSLock()
    private var statuses: [PermissionType: PermissionStatus]

    /// When `request(_:)` is called for a permission whose current status is
    /// `.notDetermined`, the value here becomes the new status.
    /// Defaults to `.granted` if not configured.
    public var nextStatusOnRequest: [PermissionType: PermissionStatus] = [:]

    /// Records each permission for which `openSettings(for:)` was called.
    public private(set) var openedSettingsFor: [PermissionType] = []

    public init(initial: [PermissionType: PermissionStatus] = [:]) {
        var seeded: [PermissionType: PermissionStatus] = [:]
        for type in PermissionType.allCases {
            seeded[type] = initial[type] ?? .notDetermined
        }
        self.statuses = seeded
    }

    public func status(for permission: PermissionType) -> PermissionStatus {
        lock.lock(); defer { lock.unlock() }
        return statuses[permission] ?? .notDetermined
    }

    public func request(_ permission: PermissionType) async -> PermissionStatus {
        lock.lock()
        let current = statuses[permission] ?? .notDetermined
        guard current == .notDetermined else {
            lock.unlock()
            return current
        }
        let next = nextStatusOnRequest[permission] ?? .granted
        statuses[permission] = next
        lock.unlock()
        return next
    }

    public func openSettings(for permission: PermissionType) {
        lock.lock(); defer { lock.unlock() }
        openedSettingsFor.append(permission)
    }
}
