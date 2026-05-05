import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
public final class CaptureEngineLive: CaptureEngine {

    private let writer: CaptureRecordWriter
    private let windowPicker: WindowPickerService
    private let log = AppLog.logger(category: "CaptureEngineLive")

    public init(writer: CaptureRecordWriter) {
        self.writer = writer
        self.windowPicker = WindowPickerService()
    }

    nonisolated public func captureRegion() async throws -> CaptureRecord {
        // Implemented in Task 15
        throw CaptureError.captureFailed(underlying: "captureRegion not yet implemented")
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
