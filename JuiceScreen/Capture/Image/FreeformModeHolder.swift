import Foundation
import Observation

/// The freeform drawing mode, shared by every overlay of one pick.
///
/// The mode cannot live in per-overlay `@State`. `OverlayPickerHost` calls
/// `makeKeyAndOrderFront` on each overlay in turn, so the **last** screen in
/// `NSScreen.screens` ends up key — and macOS delivers key events only to the
/// key window, where `onKeyPress` fires only on that window's focused view. On
/// two displays, Tab pressed with the cursor over screen 0 toggled screen 1.
/// The overlays then disagreed: their HUDs contradicted each other, and a click
/// on the still-freehand overlay fell through to the freehand
/// `DragGesture(minimumDistance: 0)`, which appended a single point and
/// committed an unusable one-point selection — cancelling the whole capture.
///
/// `FreeformPickerController` owns one of these per pick and drives it from a
/// local key-down monitor, the same mechanism `OverlayPickerHost` already uses
/// for Esc, which is what makes it work regardless of which window is key.
@MainActor
@Observable
final class FreeformModeHolder {

    private(set) var mode: FreeformMode = .freehand

    /// Mirrors `FreeformSelection.setMode`'s rule: switching mid-shape would
    /// leave the points half-freehand and half-polygon. That rule is per
    /// selection and so cannot see the other overlays; freezing here is what
    /// stops a Tab pressed mid-draw on screen 0 from dropping the untouched
    /// overlay on screen 1 back to freehand.
    private var isFrozen = false

    /// Called when the first point is placed, on any overlay.
    func freeze() {
        isFrozen = true
    }

    func toggle() {
        guard !isFrozen else { return }
        mode = (mode == .freehand) ? .polygon : .freehand
    }
}
