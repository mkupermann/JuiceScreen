import AppKit
import Foundation

public final class KeystrokeTracker: @unchecked Sendable {

    public struct Key: Equatable, Sendable {
        public var label: String       // human-readable: "A", "↩", "⌘C"
        public var timestamp: Date

        public init(label: String, timestamp: Date) {
            self.label = label
            self.timestamp = timestamp
        }
    }

    public static let lifetime: TimeInterval = 2.5

    private let lock = NSLock()
    private var keys: [Key] = []
    private let maxKeys: Int
    private var monitor: Any?
    private let log = AppLog.logger(category: "KeystrokeTracker")

    public init(maxKeys: Int = 3) {
        self.maxKeys = maxKeys
    }

    public func start() {
        stop()
        let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            let label = Self.label(for: event)
            let key = Key(label: label, timestamp: Date())
            self.lock.lock()
            self.keys.append(key)
            self.purgeLocked()
            self.lock.unlock()
        }
        monitor = m
        if monitor == nil {
            log.error("Failed to install keystroke monitor (Input Monitoring not granted?)")
        }
    }

    public func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    public func recentKeys(now: Date = Date()) -> [Key] {
        lock.lock(); defer { lock.unlock() }
        purgeLocked(now: now)
        return keys
    }

    public func _injectKeyForTesting(_ key: Key) {
        lock.lock(); defer { lock.unlock() }
        keys.append(key)
    }

    // MARK: - Helpers

    private func purgeLocked(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.lifetime)
        keys.removeAll { $0.timestamp < cutoff }
        if keys.count > maxKeys {
            keys.removeFirst(keys.count - maxKeys)
        }
    }

    private static func label(for event: NSEvent) -> String {
        var prefix = ""
        if event.modifierFlags.contains(.control) { prefix += "⌃" }
        if event.modifierFlags.contains(.option)  { prefix += "⌥" }
        if event.modifierFlags.contains(.shift)   { prefix += "⇧" }
        if event.modifierFlags.contains(.command) { prefix += "⌘" }
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        return prefix + chars
    }
}
