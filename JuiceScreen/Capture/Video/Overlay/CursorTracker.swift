import AppKit
import Foundation

/// Polls `NSEvent.mouseLocation()` at 50Hz on a private timer queue.
/// Public API requires no extra TCC permission. Used by `FrameCompositor`
/// to draw the cursor highlight ring onto recorded frames.
public final class CursorTracker: @unchecked Sendable {

    private let lock = NSLock()
    private var location: CGPoint = .zero
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.cursor-tracker")

    public init() {}

    public func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))   // 50Hz
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            self.lock.lock()
            self.location = CGPoint(x: loc.x, y: loc.y)
            self.lock.unlock()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public var currentLocation: CGPoint {
        lock.lock(); defer { lock.unlock() }
        return location
    }

    /// Test-only injection seam.
    public func _setLocationForTesting(_ point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        location = point
    }
}
