import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Thin async wrappers around ScreenCaptureKit so the rest of the capture
/// engine can `await` natural-looking calls.
public enum ScreenCaptureKitHelpers {

    // MARK: - Coordinate spaces

    /// Converts a rect from AppKit's global screen space into the space
    /// `SCStreamConfiguration.sourceRect` expects.
    ///
    /// AppKit puts the origin at the **bottom-left** of the main display with y
    /// growing upwards, and that is what `RegionPickerController.pickRegion()`
    /// returns. ScreenCaptureKit documents `sourceRect` as display-local with
    /// the origin at the **top-left** of the display. Subtracting the display
    /// origin alone is not enough — the y axis has to be flipped as well, or
    /// the captured band is mirrored about the display's horizontal centre.
    ///
    /// - Parameters:
    ///   - rect: The region in global, bottom-left screen coordinates (points).
    ///   - displayFrame: The target display's frame in the same global space,
    ///     i.e. its `NSScreen.frame` (points).
    /// - Returns: The region in display-local, top-left coordinates (points).
    public static func displayLocalTopLeft(globalBL rect: CGRect, displayFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - displayFrame.minX,
            y: displayFrame.height - (rect.minY - displayFrame.minY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    /// Inverse of `displayLocalTopLeft(globalBL:displayFrame:)`: converts an
    /// overlay-local, top-left-origin rect into AppKit's global bottom-left space.
    ///
    /// - Parameters:
    ///   - rect: The rect in the overlay's local top-left coordinates (points).
    ///   - screenFrame: The overlay screen's `NSScreen.frame` (points).
    public static func globalBottomLeft(localTL rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + screenFrame.minX,
            y: (screenFrame.height - (rect.minY + rect.height)) + screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Whether a window is one of our own picker overlays, and must therefore be
    /// kept out of the capture.
    ///
    /// The obvious-looking alternative — building the filter with
    /// `excludingApplications:` — removes **every** window we own, so a region
    /// drawn over our own editor or library captured whatever happened to be
    /// behind that window instead of the window itself. The selection looked
    /// correct and the resulting image showed a different part of the screen,
    /// which is a far more confusing failure than a dim overlay would have been.
    ///
    /// The overlays are the only windows we place at `NSWindow.Level.screenSaver`
    /// (1000), so the level distinguishes them from the editor (0) and the
    /// menu-bar status item (25) without needing to track window IDs.
    public static func isPickerOverlayWindow(
        bundleIdentifier: String?,
        windowLayer: Int,
        ownBundleIdentifier: String
    ) -> Bool {
        guard let bundleIdentifier, bundleIdentifier == ownBundleIdentifier else { return false }
        return windowLayer >= Int(NSWindow.Level.screenSaver.rawValue)
    }

    /// Returns the SCDisplay whose global frame contains `point`, or nil.
    /// `point` is in global bottom-left screen coordinates.
    @MainActor
    public static func display(containing point: CGPoint, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { globalFrame(of: $0).contains(point) }
    }

    /// SCDisplay frames are display-local; combine with `frame` from the matching
    /// NSScreen to get global screen coordinates. We match by `displayID`
    /// (CGDirectDisplayID).
    @MainActor
    public static func globalFrame(of display: SCDisplay) -> CGRect {
        if let nsScreen = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) {
            return nsScreen.frame
        }
        return CGRect(x: 0, y: 0, width: display.width, height: display.height)
    }

    /// Returns the current shareable content (displays + windows).
    /// Throws `CaptureError.missingScreenRecordingPermission` if the user has not granted access.
    public static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            // ScreenCaptureKit returns a permission error when TCC is not granted.
            // Map it to our domain error so callers can render a friendly UI.
            throw CaptureError.missingScreenRecordingPermission
        }
    }

    /// Captures a one-shot image of the supplied filter at the supplied configuration.
    public static func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed(underlying: "\(error)")
        }
    }

    /// Builds an `SCStreamConfiguration` sized for the supplied display.
    /// Configures pixel format BGRA, scales for Retina (using `pixelDensity`).
    public static func configuration(for display: SCDisplay, pixelDensity: Int = 2) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        cfg.width = display.width * pixelDensity
        cfg.height = display.height * pixelDensity
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        return cfg
    }

    /// Builds an `SCStreamConfiguration` sized for a region of the supplied display.
    /// `regionInPoints` is in points (scaled up by `pixelDensity` for the output).
    public static func configuration(
        for display: SCDisplay,
        regionInPoints: CGRect,
        pixelDensity: Int = 2
    ) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        cfg.width = Int(regionInPoints.width) * pixelDensity
        cfg.height = Int(regionInPoints.height) * pixelDensity
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.sourceRect = regionInPoints
        return cfg
    }
}
