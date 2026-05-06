import AppKit
import SwiftUI

/// Region picker overlay across every display.
///
/// One overlay window per `NSScreen`. The drag is owned by SwiftUI's
/// `DragGesture` inside `RegionPickerView`; the controller just plumbs
/// callbacks. Whichever overlay's gesture begins first becomes the active
/// overlay — the others are deactivated for the rest of that drag.
///
/// SwiftUI's `value.location` is already in the view's local top-left
/// coords, so no AppKit coordinate translation happens at event time.
/// We only convert at gesture-end, mapping the active overlay's local rect
/// to AppKit bottom-left global screen coords (what `displayGlobalFrame`
/// in `CaptureEngineLive` subtracts from to derive the SC `sourceRect`).
@MainActor
public final class RegionPickerController {

    private struct Overlay {
        let window: RegionPickerOverlayWindow
        let screen: NSScreen
    }

    private var overlays: [Overlay] = []
    private var continuation: CheckedContinuation<CGRect, Error>?

    /// The screen whose overlay started the active drag. nil before mouseDown.
    private var activeScreen: NSScreen?
    /// Esc-to-cancel monitor.
    private var escMonitor: Any?

    public init() {}

    public func pickRegion() async throws -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }

        // Build per-screen overlays.
        for screen in screens {
            let win = RegionPickerOverlayWindow(frame: screen.frame)
            overlays.append(Overlay(window: win, screen: screen))
        }
        // Wire the SwiftUI host view for each overlay.
        for entry in overlays {
            installContent(for: entry)
            entry.window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        installEscMonitor()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGRect, Error>) in
            self.continuation = cont
        }
    }

    // MARK: - View installation

    private func installContent(for entry: Overlay) {
        let view = RegionPickerView(
            canvasSize: entry.screen.frame.size,
            isActive: activeScreen == nil ? true : (activeScreen === entry.screen),
            onBegan: { [weak self] in
                self?.markActive(entry.screen)
            },
            onCommitted: { [weak self] localRect in
                self?.commit(localRect: localRect, on: entry.screen)
            }
        )
        entry.window.contentView = NSHostingView(rootView: view)
    }

    /// First overlay to start a drag becomes the active one. Refresh other
    /// overlays so their `isActive=false` setting is honoured.
    private func markActive(_ screen: NSScreen) {
        guard activeScreen == nil else { return }
        activeScreen = screen
        for entry in overlays where entry.screen !== screen {
            installContent(for: entry)
        }
    }

    // MARK: - Esc-to-cancel

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.commit(localRect: nil, on: self.activeScreen ?? self.overlays.first!.screen)
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor {
            NSEvent.removeMonitor(m)
            escMonitor = nil
        }
    }

    // MARK: - Commit

    /// `localRect` is in the active overlay's top-left local coords (SwiftUI
    /// view-local). Convert to AppKit bottom-left global screen coords here.
    private func commit(localRect: CGRect?, on screen: NSScreen) {
        guard continuation != nil else { return }   // already finished
        guard let localRect, localRect.width >= 1, localRect.height >= 1 else {
            finish(.failure(.userCancelled))
            return
        }
        let frame = screen.frame   // BL global
        // Local TL → BL local: y_BL = screen.height - (y_TL + height)
        let blLocalY = frame.height - (localRect.minY + localRect.height)
        let globalRect = CGRect(
            x: localRect.minX + frame.minX,
            y: blLocalY + frame.minY,
            width: localRect.width,
            height: localRect.height
        )
        finish(.success(globalRect))
    }

    private func finish(_ outcome: Result<CGRect, CaptureError>) {
        removeEscMonitor()
        for entry in overlays { entry.window.orderOut(nil) }
        overlays.removeAll()
        activeScreen = nil
        switch outcome {
        case .success(let rect): continuation?.resume(returning: rect)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
