import Foundation
import Testing
@testable import JuiceScreen

@Suite("SearchQuery")
struct SearchQueryTests {

    @Test("Empty query: no terms, no filters")
    func empty() {
        let q = SearchQuery()
        #expect(q.text == "")
        #expect(q.sourceApp == nil)
        #expect(q.before == nil)
        #expect(q.after == nil)
        #expect(q.mediaType == nil)
        #expect(q.isEmpty)
    }

    @Test("isEmpty false if any field set")
    func notEmpty() {
        var q = SearchQuery()
        q.text = "hello"
        #expect(q.isEmpty == false)

        q = SearchQuery()
        q.sourceApp = "Safari"
        #expect(q.isEmpty == false)

        q = SearchQuery()
        q.mediaType = .image
        #expect(q.isEmpty == false)
    }

    @Test("Equality is value-based")
    func equality() {
        var a = SearchQuery()
        a.text = "aws error"
        a.sourceApp = "Safari"
        var b = SearchQuery()
        b.text = "aws error"
        b.sourceApp = "Safari"
        #expect(a == b)
    }
}
