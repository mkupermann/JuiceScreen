import AppKit
import Foundation

/// Tracks mouse-down events globally and exposes recent clicks for the renderer.
/// **Requires Input Monitoring permission.** Callers MUST verify the permission
/// is granted (via `PermissionsService`) before calling `start()`.
public final class ClickTracker: @unchecked Sendable {

    public struct Click: Equatable, Sendable {
        public let location: CGPoint
        public let timestamp: Date
    }

    private let lock = NSLock()
    private var recent: [Click] = []
    private var monitor: Any?
    private let log = AppLog.logger(category: "ClickTracker")

    /// How long a click stays in the renderable history. Animations fade out within this window.
    public static let clickLifetime: TimeInterval = 0.6

    public init() {}

    public func start() {
        stop()
        let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            let click = Click(location: CGPoint(x: loc.x, y: loc.y), timestamp: Date())
            self.lock.lock()
            self.recent.append(click)
            self.purgeOldLocked()
            self.lock.unlock()
        }
        monitor = m
        if monitor == nil {
            log.error("Failed to install click monitor (Input Monitoring not granted?)")
        }
    }

    public func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    /// Returns clicks newer than `clickLifetime` ago.
    public func recentClicks(now: Date = Date()) -> [Click] {
        lock.lock(); defer { lock.unlock() }
        purgeOldLocked(now: now)
        return recent
    }

    private func purgeOldLocked(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.clickLifetime)
        recent.removeAll { $0.timestamp < cutoff }
    }

    /// Test-only seam.
    public func _injectClickForTesting(_ click: Click) {
        lock.lock(); defer { lock.unlock() }
        recent.append(click)
    }
}
