import Foundation

public struct SearchQuery: Equatable, Sendable {
    /// Free-text search terms (will become an FTS5 MATCH expression).
    public var text: String = ""

    /// Filter on `source_app` column. Case-insensitive equality match.
    public var sourceApp: String?

    /// Inclusive upper bound on `captured_at`.
    public var before: Date?

    /// Inclusive lower bound on `captured_at`.
    public var after: Date?

    /// Filter on media type column.
    public var mediaType: MediaType?

    public init() {}

    public var isEmpty: Bool {
        text.isEmpty && sourceApp == nil && before == nil && after == nil && mediaType == nil
    }
}
