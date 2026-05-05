import Foundation

public enum ScrollCaptureState: Equatable, Sendable {
    case idle
    case collecting(framesCaptured: Int)
    case stitching
    case done(fileURL: URL)
    case failed(ScrollCaptureError)

    public var isActive: Bool {
        switch self {
        case .collecting, .stitching: return true
        case .idle, .done, .failed:   return false
        }
    }
}
