import Foundation
import Testing
@testable import JuiceScreen

@Suite("OCRSidecarStore")
struct OCRSidecarStoreTests {

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    @Test("write + read round-trip preserves the OCRResult")
    func roundTrip() throws {
        let paths = makeTempPaths()
        let store = OCRSidecarStore(paths: paths)
        let id = UUID()
        let original = OCRResult(
            regions: [
                OCRRegion(text: "alpha", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04)),
                OCRRegion(text: "beta", boundingBox: CGRect(x: 0.5, y: 0.6, width: 0.2, height: 0.04))
            ],
            extractedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )

        try store.write(original, for: id)
        let loaded = try #require(try store.read(for: id))
        #expect(loaded == original)
    }

    @Test("read returns nil if sidecar does not exist")
    func readMissing() throws {
        let paths = makeTempPaths()
        let store = OCRSidecarStore(paths: paths)
        let result = try store.read(for: UUID())
        #expect(result == nil)
    }

    @Test("delete removes the sidecar; second delete is a no-op")
    func deleteSidecar() throws {
        let paths = makeTempPaths()
        let store = OCRSidecarStore(paths: paths)
        let id = UUID()
        try store.write(OCRResult(regions: [], extractedAt: Date()), for: id)
        try store.delete(for: id)
        try store.delete(for: id)
        #expect(try store.read(for: id) == nil)
    }
}
