import CoreGraphics

public enum VideoRecordingMode: Equatable, Sendable {
    case fullScreen
    /// Region to record, in **display-local, top-left-origin points** — the space
    /// `SCStreamConfiguration.sourceRect` expects, not AppKit's global bottom-left
    /// space. A rect coming from `RegionPickerController.pickRegion()` must be run
    /// through `ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL:displayFrame:)`
    /// first. No caller constructs this case yet — the menu records full screen.
    case region(CGRect)
}
