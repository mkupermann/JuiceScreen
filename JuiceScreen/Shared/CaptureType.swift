import Foundation

/// What kind of capture produced a `CaptureRecord`.
public enum CaptureType: String, CaseIterable, Sendable, Hashable {
    case region
    case window
    case fullScreen
    case lastRegion
}
