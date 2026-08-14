import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
public final class CaptureEngineLive: CaptureEngine {

    private let writer: CaptureRecordWriter
    private let preferences: PreferencesStore
    private let windowPicker: WindowPickerService
    private let regionPicker: RegionPickerController
    private let freeformPicker: FreeformPickerController
    private let log = AppLog.logger(category: "CaptureEngineLive")

    public init(writer: CaptureRecordWriter, preferences: PreferencesStore) {
        self.writer = writer
        self.preferences = preferences
        self.windowPicker = WindowPickerService()
        self.regionPicker = RegionPickerController()
        self.freeformPicker = FreeformPickerController()
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
        try await captureLastRegionInternal()
    }

    nonisolated public func captureFreeform() async throws -> CaptureRecord {
        try await captureFreeformInternal()
    }

    private func captureLastRegionInternal() async throws -> CaptureRecord {
        let region = preferences.load().lastRegion
        guard let regionInScreen = region else {
            // No prior region — fall back to triggering the picker (same as captureRegion).
            return try await captureRegionInternal()
        }

        let (cg, display) = try await captureRect(globalBL: regionInScreen)
        return try await persist(cg: cg, captureType: .lastRegion, sourceApp: nil,
                                 scaleFactor: backingScaleFactor(for: display))
    }

    // MARK: - Region

    private func captureRegionInternal() async throws -> CaptureRecord {
        let regionInScreen = try await regionPicker.pickRegion()

        let (cg, display) = try await captureRect(globalBL: regionInScreen)

        // Remember this region for "Capture Last Region".
        var prefs = preferences.load()
        prefs.lastRegion = regionInScreen
        preferences.save(prefs)

        return try await persist(cg: cg, captureType: .region, sourceApp: nil,
                                 scaleFactor: backingScaleFactor(for: display))
    }

    // MARK: - Freeform

    private func captureFreeformInternal() async throws -> CaptureRecord {
        let pick = try await freeformPicker.pickFreeform()
        let (cg, display) = try await captureRect(globalBL: pick.globalBoundsBL)

        // The path is in points relative to the bounding box; the image is in
        // pixels. FreeformMasker scales between the two.
        guard let masked = FreeformMasker.apply(
            path: pick.pathInBounds,
            pathSpaceSize: pick.globalBoundsBL.size,
            to: cg
        ) else {
            throw CaptureError.captureFailed(underlying: "Freeform masking failed")
        }

        return try await persist(cg: masked, captureType: .freeform, sourceApp: nil,
                                 scaleFactor: backingScaleFactor(for: display))
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
        return try await persist(cg: cg, captureType: .fullScreen, sourceApp: nil, scaleFactor: backingScaleFactor(for: display))
    }

    // MARK: - Window

    private func captureWindowInternal() async throws -> CaptureRecord {
        let filter = try await windowPicker.pickWindow()
        let cfg = SCStreamConfiguration()
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        // The picker's filter already encodes which window to capture; SC handles sizing.
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        // Window captures don't bind to a single SCDisplay; use the main screen's
        // backing scale as the best guess (most users keep windows on the main display).
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return try await persist(cg: cg, captureType: .window, sourceApp: nil, scaleFactor: scale)
    }

    // MARK: - Helpers

    private func persist(cg: CGImage, captureType: CaptureType, sourceApp: String?, scaleFactor: CGFloat) async throws -> CaptureRecord {
        // Construct NSImage with point-size = pixel-size / display backing scale.
        // Using a hardcoded /2 (assuming Retina) breaks on displays that are 1×,
        // 1.5×, 3×, or any non-Retina external monitor — the canvas in the editor
        // ends up the wrong size relative to the captured region.
        let scale = max(scaleFactor, 1.0)
        let pointSize = NSSize(
            width:  CGFloat(cg.width)  / scale,
            height: CGFloat(cg.height) / scale
        )
        let image = NSImage(cgImage: cg, size: pointSize)
        return try await MainActor.run {
            try writer.write(
                image: image,
                captureType: captureType,
                capturedAt: Date(),
                sourceApp: sourceApp
            )
        }
    }

    /// Looks up the NSScreen matching `display` and returns its `backingScaleFactor`.
    /// Falls back to 2.0 (Retina) if no NSScreen matches — better than 1.0 because
    /// most Macs are Retina, and an undersized canvas is more visually wrong than
    /// a slightly-oversized one.
    private func backingScaleFactor(for display: SCDisplay) -> CGFloat {
        if let nsScreen = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) {
            return nsScreen.backingScaleFactor
        }
        return 2.0
    }

    nonisolated private func ownApplications() async throws -> [SCRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bks-lab.juicescreen"
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        return content.applications.filter { $0.bundleIdentifier == bundleID }
    }

    /// Shared by region, last-region and freeform: resolve the display holding
    /// the rect's centre, convert to `sourceRect` space, capture.
    /// `rect` is in global bottom-left screen coordinates.
    private func captureRect(globalBL rect: CGRect) async throws -> (image: CGImage, display: SCDisplay) {
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let display = ScreenCaptureKitHelpers.display(
            containing: CGPoint(x: rect.midX, y: rect.midY),
            in: content
        ) else {
            throw CaptureError.regionOutsideDisplays
        }
        let displayLocal = ScreenCaptureKitHelpers.displayLocalTopLeft(
            globalBL: rect,
            displayFrame: ScreenCaptureKitHelpers.globalFrame(of: display)
        )
        let filter = SCContentFilter(
            display: display,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: display, regionInPoints: displayLocal)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return (cg, display)
    }
}
