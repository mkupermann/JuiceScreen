import AppKit
import CoreGraphics
import SwiftUI

/// The result of a freeform pick.
///
/// Only the bounding box is expressed globally. The path stays relative to that
/// box, so exactly one coordinate conversion happens per capture and it happens
/// through `ScreenCaptureKitHelpers`.
public struct FreeformPick: @unchecked Sendable {
    public let globalBoundsBL: CGRect
    public let pathInBounds: CGPath
}

@MainActor
public final class FreeformPickerController {

    private let host = OverlayPickerHost<FreeformSelection>()

    /// Tab cannot be an `onKeyPress` on the overlay: only the key window sees
    /// key events, and on multiple displays that is the last screen rather than
    /// the one under the cursor. A local monitor sees it wherever it lands —
    /// the same mechanism `OverlayPickerHost` already uses for Esc.
    private var tabMonitor: Any?

    public init() {}

    public func pickFreeform() async throws -> FreeformPick {
        // `host.pick` refuses re-entry too, but this has to come first: without
        // it a second call would overwrite `tabMonitor` before being refused,
        // and its `defer` would then tear down the live pick's monitor.
        guard tabMonitor == nil else {
            throw CaptureError.userCancelled
        }

        // Fresh per pick, so the next capture starts in freehand and unfrozen.
        let mode = FreeformModeHolder()
        installTabMonitor(for: mode)
        defer { removeTabMonitor() }

        let result = try await host.pick { screen, isActive, onBegan, onCommitted in
            AnyView(
                FreeformPickerView(
                    canvasSize: screen.frame.size,
                    isActive: isActive,
                    mode: mode,
                    // The first point anywhere fixes the mode for every overlay.
                    onBegan: { mode.freeze(); onBegan() },
                    onCommitted: onCommitted
                )
            )
        }
        let selection = result.payload
        return FreeformPick(
            globalBoundsBL: ScreenCaptureKitHelpers.globalBottomLeft(
                localTL: selection.bounds,
                screenFrame: result.screen.frame
            ),
            pathInBounds: selection.pathInBounds
        )
    }

    // MARK: - Tab

    private func installTabMonitor(for mode: FreeformModeHolder) {
        tabMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == 48 else { return event }  // Tab
            mode.toggle()
            return nil                                      // never focus traversal
        }
    }

    private func removeTabMonitor() {
        if let m = tabMonitor {
            NSEvent.removeMonitor(m)
            tabMonitor = nil
        }
    }
}
