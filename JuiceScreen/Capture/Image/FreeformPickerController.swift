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

    public init() {}

    public func pickFreeform() async throws -> FreeformPick {
        let result = try await host.pick { screen, isActive, onBegan, onCommitted in
            AnyView(
                FreeformPickerView(
                    canvasSize: screen.frame.size,
                    isActive: isActive,
                    onBegan: onBegan,
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
}
