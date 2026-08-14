import AppKit
import SwiftUI

/// Rectangular region picker.
///
/// The overlay mechanics live in `OverlayPickerHost`; this type only supplies
/// the SwiftUI surface and converts the committed rect from the overlay's local
/// top-left space into AppKit's global bottom-left space.
@MainActor
public final class RegionPickerController {

    private let host = OverlayPickerHost<CGRect>()

    public init() {}

    /// Returns the selected rect in global bottom-left screen coordinates.
    public func pickRegion() async throws -> CGRect {
        let result = try await host.pick { screen, isActive, onBegan, onCommitted in
            AnyView(
                RegionPickerView(
                    canvasSize: screen.frame.size,
                    isActive: isActive,
                    onBegan: onBegan,
                    onCommitted: { localRect in
                        guard let localRect, localRect.width >= 1, localRect.height >= 1 else {
                            onCommitted(nil)
                            return
                        }
                        onCommitted(localRect)
                    }
                )
            )
        }
        return ScreenCaptureKitHelpers.globalBottomLeft(
            localTL: result.payload,
            screenFrame: result.screen.frame
        )
    }
}
