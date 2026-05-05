import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureRecord")
struct CaptureRecordTests {

    @Test("CaptureType is exhaustively case-iterable")
    func captureTypeAllCases() {
        let all = Set(CaptureType.allCases)
        #expect(all == [.region, .window, .fullScreen, .lastRegion])
    }

    @Test("CaptureRecord stores all metadata fields")
    func storesFields() {
        let url = URL(fileURLWithPath: "/tmp/JuiceScreen_2026-05-05_at_14.32.18.png")
        let date = Date(timeIntervalSince1970: 1_770_000_000)
        let record = CaptureRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            fileURL: url,
            captureType: .region,
            capturedAt: date,
            pixelWidth: 1024,
            pixelHeight: 768,
            sourceApp: "Safari"
        )

        #expect(record.fileURL == url)
        #expect(record.captureType == .region)
        #expect(record.capturedAt == date)
        #expect(record.pixelWidth == 1024)
        #expect(record.pixelHeight == 768)
        #expect(record.sourceApp == "Safari")
    }

    @Test("sourceApp is optional")
    func sourceAppNullable() {
        let record = CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/x.png"),
            captureType: .fullScreen,
            capturedAt: Date(),
            pixelWidth: 100,
            pixelHeight: 100,
            sourceApp: nil
        )
        #expect(record.sourceApp == nil)
    }

    @Test("Convenience init generates a UUID when not supplied")
    func convenienceInit() {
        let a = CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/a.png"),
            captureType: .window,
            capturedAt: Date(),
            pixelWidth: 1, pixelHeight: 1,
            sourceApp: nil
        )
        let b = CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/b.png"),
            captureType: .window,
            capturedAt: Date(),
            pixelWidth: 1, pixelHeight: 1,
            sourceApp: nil
        )
        #expect(a.id != b.id)
    }

    @Test("Equatable: same field values are equal")
    func equatable() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/x.png")
        let date = Date(timeIntervalSince1970: 0)
        let a = CaptureRecord(id: id, fileURL: url, captureType: .region,
                              capturedAt: date, pixelWidth: 10, pixelHeight: 10, sourceApp: nil)
        let b = CaptureRecord(id: id, fileURL: url, captureType: .region,
                              capturedAt: date, pixelWidth: 10, pixelHeight: 10, sourceApp: nil)
        #expect(a == b)
    }
}
