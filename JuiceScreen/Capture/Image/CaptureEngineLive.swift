import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
public final class CaptureEngineLive: CaptureEngine {

    private let writer: CaptureRecordWriter
    private let windowPicker: WindowPickerService
    private let regionPicker: RegionPickerController
    private let log = AppLog.logger(category: "CaptureEngineLive")

    public init(writer: CaptureRecordWriter) {
        self.writer = writer
        self.windowPicker = WindowPickerService()
        self.regionPicker = RegionPickerController()
    }

    nonisolated public func captureRegion() async throws -> CaptureRecord {
        try await captureRegionInternal()
    }

    nonisolated public func captureWindow() async throws -> CaptureRecord {
        try await captureWindowInternal()
    }

    nonisolated public func captureFullScreen() async throws -> CaptureRecord {
        try await captureFullScreenInternal()
    }

    nonisolated public func captureLastRegion() async throws -> CaptureRecord {
        // Implemented in Task 17
        throw CaptureError.captureFailed(underlying: "captureLastRegion not yet implemented")
    }

    // MARK: - Region

    private func captureRegionInternal() async throws -> CaptureRecord {
        let regionInScreen = try await regionPicker.pickRegion()

        // Find which display contains the selection's center.
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let display = displayContaining(point: CGPoint(x: regionInScreen.midX, y: regionInScreen.midY),
                                              in: content) else {
            throw CaptureError.regionOutsideDisplays
        }

        // Convert global-screen coordinates to display-local coordinates for sourceRect.
        let displayFrame = displayGlobalFrame(display)
        let displayLocal = CGRect(
            x: regionInScreen.minX - displayFrame.minX,
            y: regionInScreen.minY - displayFrame.minY,
            width: regionInScreen.width,
            height: regionInScreen.height
        )

        let filter = SCContentFilter(
            display: display,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: display, regionInPoints: displayLocal)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .region, sourceApp: nil)
    }

    /// Returns the SCDisplay whose global frame contains `point`, or nil.
    private func displayContaining(point: CGPoint, in content: SCShareableContent) -> SCDisplay? {
        return content.displays.first { display in
            displayGlobalFrame(display).contains(point)
        }
    }

    /// SCDisplay frames are in display-local coordinates; combine with `frame` from the matching NSScreen
    /// to get global screen coordinates. We match by `displayID` (CGDirectDisplayID).
    private func displayGlobalFrame(_ display: SCDisplay) -> CGRect {
        if let nsScreen = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) {
            return nsScreen.frame
        }
        return CGRect(x: 0, y: 0, width: display.width, height: display.height)
    }

    // MARK: - Full screen

    private func captureFullScreenInternal() async throws -> CaptureRecord {
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }

        let display: SCDisplay
        if content.displays.count == 1 {
            display = content.displays[0]
        } else {
            display = try await DisplayPickerWindow.pick(from: content.displays)
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: display)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .fullScreen, sourceApp: nil)
    }

    // MARK: - Window

    private func captureWindowInternal() async throws -> CaptureRecord {
        let filter = try await windowPicker.pickWindow()
        let cfg = SCStreamConfiguration()
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        // The picker's filter already encodes which window to capture; SC handles sizing.
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .window, sourceApp: nil)
    }

    // MARK: - Helpers

    private func persist(cg: CGImage, captureType: CaptureType, sourceApp: String?) async throws -> CaptureRecord {
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        return try await MainActor.run {
            try writer.write(
                image: image,
                captureType: captureType,
                capturedAt: Date(),
                sourceApp: sourceApp
            )
        }
    }

    nonisolated private func ownApplications() async throws -> [SCRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bks-lab.juicescreen"
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        return content.applications.filter { $0.bundleIdentifier == bundleID }
    }
}
