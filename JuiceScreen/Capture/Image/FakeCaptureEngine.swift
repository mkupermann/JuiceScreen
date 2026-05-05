import Foundation

/// Test double for `CaptureEngine`. Configurable per-method outcomes,
/// records the order of calls.
public final class FakeCaptureEngine: CaptureEngine, @unchecked Sendable {

    public typealias Outcome = Result<CaptureRecord, CaptureError>

    private let lock = NSLock()
    public var recordsToReturn: [CaptureType: Outcome] = [:]
    public private(set) var calls: [CaptureType] = []

    public init() {}

    public func captureRegion() async throws -> CaptureRecord {
        try await dispatch(.region)
    }

    public func captureWindow() async throws -> CaptureRecord {
        try await dispatch(.window)
    }

    public func captureFullScreen() async throws -> CaptureRecord {
        try await dispatch(.fullScreen)
    }

    public func captureLastRegion() async throws -> CaptureRecord {
        try await dispatch(.lastRegion)
    }

    // MARK: - Helpers

    private func dispatch(_ type: CaptureType) async throws -> CaptureRecord {
        lock.lock()
        calls.append(type)
        let outcome = recordsToReturn[type] ?? .failure(.userCancelled)
        lock.unlock()
        switch outcome {
        case .success(let record): return record
        case .failure(let error):  throw error
        }
    }
}
