import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeOCRService")
struct FakeOCRServiceTests {

    private let sampleURL = URL(fileURLWithPath: "/tmp/sample.png")
    private let sampleResult = OCRResult(
        regions: [OCRRegion(text: "Hello", boundingBox: CGRect(x: 0, y: 0, width: 100, height: 20))],
        extractedAt: Date(timeIntervalSince1970: 1_000_000)
    )

    @Test("returns configured result")
    func returnsConfiguredResult() async throws {
        let sut = FakeOCRService()
        sut.nextResult = .success(sampleResult)
        let result = try await sut.recognize(imageAt: sampleURL)
        #expect(result == sampleResult)
    }

    @Test("throws configured error")
    func throwsConfiguredError() async throws {
        let sut = FakeOCRService()
        sut.nextResult = .failure(.imageLoadFailed)
        await #expect(throws: OCRError.imageLoadFailed) {
            try await sut.recognize(imageAt: sampleURL)
        }
    }

    @Test("records calls in order")
    func recordsCallsInOrder() async throws {
        let sut = FakeOCRService()
        sut.nextResult = .success(sampleResult)
        let url1 = URL(fileURLWithPath: "/tmp/a.png")
        let url2 = URL(fileURLWithPath: "/tmp/b.png")
        _ = try await sut.recognize(imageAt: url1)
        _ = try await sut.recognize(imageAt: url2)
        #expect(sut.calls == [url1, url2])
    }

    @Test("default unconfigured returns empty OCRResult")
    func defaultUnconfiguredReturnsEmpty() async throws {
        let sut = FakeOCRService()
        let result = try await sut.recognize(imageAt: sampleURL)
        #expect(result.regions.isEmpty)
    }
}
