import Foundation

public final class FakeTrimmerService: TrimmerService, @unchecked Sendable {

    public typealias Outcome = Result<URL, TrimmerError>

    public struct Call: Equatable, Sendable {
        public let sourceURL: URL
        public let range: TrimRange
        public let destinationURL: URL
    }

    private let lock = NSLock()
    public var nextResult: Outcome?
    public private(set) var calls: [Call] = []

    public init() {}

    public func trim(sourceURL: URL, range: TrimRange, destinationURL: URL) async throws -> URL {
        lock.lock()
        calls.append(Call(sourceURL: sourceURL, range: range, destinationURL: destinationURL))
        let outcome = nextResult
        lock.unlock()

        switch outcome {
        case .success(let url): return url
        case .failure(let err): throw err
        case nil:               return destinationURL
        }
    }
}
