import Foundation
import Testing
@testable import JuiceScreen

@Suite("SearchQueryParser")
struct SearchQueryParserTests {

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    @Test("Empty input → empty query")
    func empty() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("")
        #expect(q.isEmpty)
    }

    @Test("Bare words become free text")
    func freeText() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("aws error")
        #expect(q.text == "aws error")
        #expect(q.sourceApp == nil)
    }

    @Test("from:safari → sourceApp")
    func fromFilter() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("from:Safari")
        #expect(q.text == "")
        #expect(q.sourceApp == "Safari")
    }

    @Test("before:2026-04-01 + after:2026-04-15 → date range")
    func dateRange() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("after:2026-04-15 before:2026-05-01")
        #expect(q.after == ymd(2026, 4, 15))
        #expect(q.before == ymd(2026, 5, 1))
    }

    @Test("type:image / type:video → mediaType")
    func typeFilter() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        #expect(parser.parse("type:image").mediaType == .image)
        #expect(parser.parse("type:video").mediaType == .video)
        #expect(parser.parse("type:bogus").mediaType == nil)   // unknown values ignored
    }

    @Test("Combined: free text + filters parses everything")
    func combined() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("aws error from:Safari after:2026-04-15 type:image")
        #expect(q.text == "aws error")
        #expect(q.sourceApp == "Safari")
        #expect(q.after == ymd(2026, 4, 15))
        #expect(q.mediaType == .image)
    }

    @Test("Filter tokens preserved in original casing for sourceApp; type/before/after lowercased")
    func casing() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("FROM:Safari TYPE:IMAGE")
        #expect(q.sourceApp == "Safari")
        #expect(q.mediaType == .image)
    }

    @Test("Malformed date strings are silently dropped")
    func malformedDate() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("before:not-a-date")
        #expect(q.before == nil)
    }

    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
}
