import AppKit
import SwiftUI

/// Orchestrates the region picker overlay: shows a transparent NSWindow over
/// every display, lets the user drag a rectangle, returns the selected CGRect
/// (in global screen coordinates) or throws `CaptureError.userCancelled`.
@MainActor
public final class RegionPickerController {

    private var window: RegionPickerOverlayWindow?
    private var localMonitor: Any?
    private var continuation: CheckedContinuation<CGRect, Error>?
    private var selection: RegionSelection?
    private var cursor: CGPoint?

    public init() {}

    /// Returns the selected rectangle in global screen coordinates (origin at lower-left
    /// of the unioned screen frame, matching AppKit's coordinate convention).
    public func pickRegion() async throws -> CGRect {
        // Compute the union frame of all screens — this is our overlay's bounds.
        let union = NSScreen.screens.reduce(NSRect.zero) { acc, scr in acc.union(scr.frame) }
        guard union.width > 0, union.height > 0 else {
            throw CaptureError.noDisplaysAvailable
        }

        let win = RegionPickerOverlayWindow(frame: union)
        self.window = win
        rebuildContentView()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installEventMonitor()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGRect, Error>) in
            self.continuation = cont
        }
    }

    // MARK: - Event monitor

    private func installEventMonitor() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeEventMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        let pointInWindow = window.contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow

        switch event.type {
        case .mouseMoved:
            cursor = pointInWindow
            rebuildContentView()
            return event

        case .leftMouseDown:
            selection = RegionSelection(start: pointInWindow, current: pointInWindow)
            cursor = pointInWindow
            rebuildContentView()
            return nil

        case .leftMouseDragged:
            if var s = selection {
                s.current = pointInWindow
                selection = s
            }
            cursor = pointInWindow
            rebuildContentView()
            return nil

        case .leftMouseUp:
            if let s = selection, s.isUsable {
                let rect = windowRectToScreenRect(s.normalized)
                finish(.success(rect))
            } else {
                finish(.failure(.userCancelled))
            }
            return nil

        case .keyDown:
            switch event.keyCode {
            case 53: // Esc
                finish(.failure(.userCancelled))
                return nil
            case 36, 76: // Return, KP-Enter
                if let s = selection, s.isUsable {
                    finish(.success(windowRectToScreenRect(s.normalized)))
                } else {
                    finish(.failure(.userCancelled))
                }
                return nil
            case 123, 124, 125, 126: // Left, Right, Down, Up
                if var s = selection {
                    let stepped: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                    let dx: CGFloat = event.keyCode == 123 ? -stepped : event.keyCode == 124 ? stepped : 0
                    let dy: CGFloat = event.keyCode == 125 ? -stepped : event.keyCode == 126 ? stepped : 0
                    s = s.nudged(by: CGSize(width: dx, height: dy))
                    selection = s
                    rebuildContentView()
                }
                return nil
            default:
                return event
            }

        default:
            return event
        }
    }

    // MARK: - Coordinate conversion

    /// Converts a rect in the overlay window's local coordinates to global screen coordinates
    /// (the same coordinate space that ScreenCaptureKit's `sourceRect` expects, when scoped to a display).
    private func windowRectToScreenRect(_ windowRect: CGRect) -> CGRect {
        guard let window else { return windowRect }
        let originInScreen = window.convertPoint(toScreen: windowRect.origin)
        return CGRect(origin: originInScreen, size: windowRect.size)
    }

    private func rebuildContentView() {
        guard let window else { return }
        let view = RegionPickerView(
            canvasSize: window.frame.size,
            selection: selection,
            cursor: cursor
        )
        window.contentView = NSHostingView(rootView: view)
    }

    private func finish(_ outcome: Result<CGRect, CaptureError>) {
        removeEventMonitor()
        window?.orderOut(nil)
        window = nil
        selection = nil
        cursor = nil
        switch outcome {
        case .success(let rect): continuation?.resume(returning: rect)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
