import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Production `CaptureEngine` using ScreenCaptureKit + AppKit overlays for the picker.
/// Region picker, window picker, and multi-display picker land in subsequent tasks.
@MainActor
public final class CaptureEngineLive: CaptureEngine {

    private let writer: CaptureRecordWriter
    private let log = AppLog.logger(category: "CaptureEngineLive")

    public init(writer: CaptureRecordWriter) {
        self.writer = writer
    }

    nonisolated public func captureRegion() async throws -> CaptureRecord {
        // Implemented in Task 15
        throw CaptureError.captureFailed(underlying: "captureRegion not yet implemented")
    }

    nonisolated public func captureWindow() async throws -> CaptureRecord {
        // Implemented in Task 10
        throw CaptureError.captureFailed(underlying: "captureWindow not yet implemented")
    }

    nonisolated public func captureFullScreen() async throws -> CaptureRecord {
        try await captureFullScreenInternal()
    }

    nonisolated public func captureLastRegion() async throws -> CaptureRecord {
        // Implemented in Task 17
        throw CaptureError.captureFailed(underlying: "captureLastRegion not yet implemented")
    }

    // MARK: - Full screen (single display path; multi-display picker added in Task 11)

    private func captureFullScreenInternal() async throws -> CaptureRecord {
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let primary = content.displays.first else {
            throw CaptureError.noDisplaysAvailable
        }

        // Filter excludes our own app's windows so we never capture the menu we may have just dismissed.
        let filter = SCContentFilter(
            display: primary,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: primary)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))

        return try writer.write(
            image: image,
            captureType: .fullScreen,
            capturedAt: Date(),
            sourceApp: nil
        )
    }

    /// Returns this app's `SCRunningApplication`s so we can exclude them from the capture filter.
    nonisolated private func ownApplications() async throws -> [SCRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bks-lab.juicescreen"
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        return content.applications.filter { $0.bundleIdentifier == bundleID }
    }
}
