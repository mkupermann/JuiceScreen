import Foundation
import ScreenCaptureKit

/// Wraps `SCContentSharingPicker` (macOS 14+) — the Apple-provided window picker.
/// The picker's user interaction is asynchronous; we bridge it to async/await
/// via `withCheckedContinuation`.
@MainActor
public final class WindowPickerService: NSObject, SCContentSharingPickerObserver {

    private var continuation: CheckedContinuation<SCContentFilter, Error>?
    private var pickerStream: SCStream?

    public override init() {
        super.init()
    }

    /// Presents the window picker and returns the user-selected `SCContentFilter`.
    /// Throws `CaptureError.userCancelled` if the user dismisses without picking.
    public func pickWindow() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        defer { picker.remove(self) }

        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.excludedWindowIDs = []
        picker.defaultConfiguration = configuration
        picker.isActive = true

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SCContentFilter, Error>) in
            self.continuation = cont
            picker.present()
        }
    }

    // MARK: - SCContentSharingPickerObserver

    nonisolated public func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            picker.isActive = false
            continuation?.resume(returning: filter)
            continuation = nil
        }
    }

    nonisolated public func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            picker.isActive = false
            continuation?.resume(throwing: CaptureError.userCancelled)
            continuation = nil
        }
    }

    nonisolated public func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in
            continuation?.resume(throwing: CaptureError.captureFailed(underlying: "\(error)"))
            continuation = nil
        }
    }
}
