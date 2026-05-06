import AppKit
import SwiftUI

/// Orchestrates the region picker overlay across every display.
///
/// macOS does not reliably draw or accept events in a single window that spans
/// multiple displays — only the display the window is "anchored" to behaves.
/// We create one overlay window per `NSScreen`, share a single selection state
/// in global screen coordinates, and translate to each window's local coords
/// when rendering. The user can drag from any display.
@MainActor
public final class RegionPickerController {

    private struct Overlay {
        let window: RegionPickerOverlayWindow
        let screen: NSScreen
    }

    private var overlays: [Overlay] = []
    private var localMonitor: Any?
    private var continuation: CheckedContinuation<CGRect, Error>?

    /// Selection in global screen coordinates (lower-left origin, AppKit convention).
    private var selection: RegionSelection?
    /// Cursor in global screen coordinates.
    private var cursor: CGPoint?

    public init() {}

    /// Returns the selected rectangle in global screen coordinates (origin at the
    /// lower-left of the unioned screen frame, matching AppKit's coordinate space —
    /// which is what `ScreenCaptureKit`'s `sourceRect` expects when scoped to a display).
    public func pickRegion() async throws -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }

        // One overlay per screen, sized to that screen's frame.
        for screen in screens {
            let win = RegionPickerOverlayWindow(frame: screen.frame)
            overlays.append(Overlay(window: win, screen: screen))
        }

        rebuildAllContent()
        for entry in overlays {
            entry.window.makeKeyAndOrderFront(nil)
        }
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
        // Translate event location to global screen coordinates regardless of
        // which overlay window received it.
        guard let win = event.window as? RegionPickerOverlayWindow else { return event }
        let pointInScreen = win.convertPoint(toScreen: event.locationInWindow)

        switch event.type {
        case .mouseMoved:
            cursor = pointInScreen
            rebuildAllContent()
            return event

        case .leftMouseDown:
            selection = RegionSelection(start: pointInScreen, current: pointInScreen)
            cursor = pointInScreen
            rebuildAllContent()
            return nil

        case .leftMouseDragged:
            if var s = selection {
                s.current = pointInScreen
                selection = s
            }
            cursor = pointInScreen
            rebuildAllContent()
            return nil

        case .leftMouseUp:
            if let s = selection, s.isUsable {
                finish(.success(s.normalized))
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
                    finish(.success(s.normalized))
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
                    rebuildAllContent()
                }
                return nil
            default:
                return event
            }

        default:
            return event
        }
    }

    // MARK: - Rendering

    private func rebuildAllContent() {
        for entry in overlays {
            rebuildContent(for: entry)
        }
    }

    private func rebuildContent(for entry: Overlay) {
        let screenOrigin = entry.screen.frame.origin
        let localSelection = selection.map { sel in
            RegionSelection(
                start:   CGPoint(x: sel.start.x   - screenOrigin.x, y: sel.start.y   - screenOrigin.y),
                current: CGPoint(x: sel.current.x - screenOrigin.x, y: sel.current.y - screenOrigin.y)
            )
        }
        let localCursor = cursor.map { CGPoint(x: $0.x - screenOrigin.x, y: $0.y - screenOrigin.y) }

        let view = RegionPickerView(
            canvasSize: entry.screen.frame.size,
            selection: localSelection,
            cursor: localCursor
        )
        entry.window.contentView = NSHostingView(rootView: view)
    }

    // MARK: - Finish

    private func finish(_ outcome: Result<CGRect, CaptureError>) {
        removeEventMonitor()
        for entry in overlays { entry.window.orderOut(nil) }
        overlays.removeAll()
        selection = nil
        cursor = nil
        switch outcome {
        case .success(let rect): continuation?.resume(returning: rect)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
