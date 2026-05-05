import Foundation
import Testing
@testable import JuiceScreen

@Suite("OCRResult")
struct OCRResultTests {

    private let sampleRegion = OCRRegion(
        text: "Hello",
        boundingBox: CGRect(x: 0, y: 0, width: 100, height: 20)
    )

    @Test("region stores text and boundingBox")
    func regionStoresFields() {
        let region = OCRRegion(text: "Swift", boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(region.text == "Swift")
        #expect(region.boundingBox == CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    @Test("fullText joins region texts with newline")
    func fullTextJoined() {
        let r1 = OCRRegion(text: "Line one", boundingBox: .zero)
        let r2 = OCRRegion(text: "Line two", boundingBox: .zero)
        let result = OCRResult(regions: [r1, r2], extractedAt: .now)
        #expect(result.fullText == "Line one\nLine two")
    }

    @Test("fullText is empty string when there are no regions")
    func fullTextEmpty() {
        let result = OCRResult(regions: [], extractedAt: .now)
        #expect(result.fullText == "")
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let region = OCRRegion(text: "OCR", boundingBox: CGRect(x: 10, y: 20, width: 200, height: 40))
        let original = OCRResult(regions: [region], extractedAt: date)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(OCRResult.self, from: data)
        #expect(decoded == original)
    }

    @Test("Equatable distinguishes different results")
    func equatable() {
        let r1 = OCRResult(regions: [sampleRegion], extractedAt: Date(timeIntervalSince1970: 0))
        let r2 = OCRResult(regions: [sampleRegion], extractedAt: Date(timeIntervalSince1970: 0))
        let r3 = OCRResult(regions: [], extractedAt: Date(timeIntervalSince1970: 0))
        #expect(r1 == r2)
        #expect(r1 != r3)
    }
}
