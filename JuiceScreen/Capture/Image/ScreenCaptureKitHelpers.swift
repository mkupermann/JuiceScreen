import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Thin async wrappers around ScreenCaptureKit so the rest of the capture
/// engine can `await` natural-looking calls.
public enum ScreenCaptureKitHelpers {

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
