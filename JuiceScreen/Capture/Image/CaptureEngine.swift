import Foundation

public protocol CaptureEngine: Sendable {
    func captureRegion() async throws -> CaptureRecord
    func captureWindow() async throws -> CaptureRecord
    func captureFullScreen() async throws -> CaptureRecord
    func captureLastRegion() async throws -> CaptureRecord
}
