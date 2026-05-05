import Foundation

public enum TrimmerError: Error, Equatable {
    case invalidRange
    case sourceUnreadable
    case destinationUnwritable(String)
    case exportFailed(String)
    case userCancelled
}

public protocol TrimmerService: Sendable {
    /// Writes a trimmed copy of `sourceURL` covering `range` to `destinationURL`.
    /// Returns the URL of the written file.
    func trim(sourceURL: URL, range: TrimRange, destinationURL: URL) async throws -> URL
}
