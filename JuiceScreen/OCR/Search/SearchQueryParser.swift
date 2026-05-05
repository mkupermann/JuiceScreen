import Foundation

public struct SearchQueryParser {

    public var calendar: Calendar = .current

    public init() {}

    public func parse(_ input: String) -> SearchQuery {
        var query = SearchQuery()
        var freeTextTokens: [String] = []

        let tokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for raw in tokens {
            // Normalize key:value tokens by lowercasing the key only.
            if let colonIndex = raw.firstIndex(of: ":") {
                let key = raw[..<colonIndex].lowercased()
                let value = String(raw[raw.index(after: colonIndex)...])
                if applyFilter(key: key, value: value, into: &query) {
                    continue
                }
            }
            freeTextTokens.append(raw)
        }

        query.text = freeTextTokens.joined(separator: " ")
        return query
    }

    /// Returns true if the token matched a known filter (and was applied).
    private func applyFilter(key: String, value: String, into query: inout SearchQuery) -> Bool {
        switch key {
        case "from":
            guard !value.isEmpty else { return false }
            query.sourceApp = value
            return true
        case "type":
            if let mt = MediaType(rawValue: value.lowercased()) {
                query.mediaType = mt
            }
            return true
        case "before":
            if let date = parseDate(value) {
                query.before = date
            }
            return true
        case "after":
            if let date = parseDate(value) {
                query.after = date
            }
            return true
        default:
            return false
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return calendar.date(from: c)
    }
}
