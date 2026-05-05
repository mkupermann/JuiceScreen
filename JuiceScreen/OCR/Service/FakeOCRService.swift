import Foundation

public final class FakeOCRService: OCRService, @unchecked Sendable {
    public typealias Outcome = Result<OCRResult, OCRError>

    private let lock = NSLock()
    public var nextResult: Outcome?
    public private(set) var calls: [URL] = []

    public init() {}

    public func recognize(imageAt url: URL) async throws -> OCRResult {
        lock.lock()
        calls.append(url)
        let outcome = nextResult
        lock.unlock()

        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        case nil:
            return OCRResult(regions: [], extractedAt: Date())
        }
    }
}
