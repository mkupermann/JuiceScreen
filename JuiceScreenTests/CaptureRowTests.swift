import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureRow")
struct CaptureRowTests {

    @Test("MediaType allCases")
    func mediaTypeAllCases() {
        #expect(Set(MediaType.allCases) == [.image, .video])
    }

    @Test("CaptureRow can be built from a CaptureRecord")
    func fromCaptureRecord() {
        let record = CaptureRecord(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/x.png"),
            captureType: .region,
            capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
            pixelWidth: 1024, pixelHeight: 768,
            sourceApp: "Safari"
        )
        let row = CaptureRow(record: record, fileSizeBytes: 12345, thumbnailPath: "/tmp/thumb.jpg")
        #expect(row.uuid == record.id)
        #expect(row.filePath == record.fileURL.path)
        #expect(row.thumbnailPath == "/tmp/thumb.jpg")
        #expect(row.mediaType == .image)
        #expect(row.capturedAt == record.capturedAt)
        #expect(row.pixelWidth == 1024)
        #expect(row.pixelHeight == 768)
        #expect(row.fileSizeBytes == 12345)
        #expect(row.sourceApp == "Safari")
        #expect(row.deletedAt == nil)
        #expect(row.annotationPath == nil)
        #expect(row.durationMs == nil)
    }

    @Test("Equality is value-based")
    func equality() {
        let id = UUID()
        let date = Date()
        let a = CaptureRow(uuid: id, filePath: "/a.png", annotationPath: nil, thumbnailPath: "/t.jpg",
                           mediaType: .image, capturedAt: date,
                           pixelWidth: 10, pixelHeight: 10, durationMs: nil,
                           fileSizeBytes: 100, sourceApp: nil, deletedAt: nil)
        let b = CaptureRow(uuid: id, filePath: "/a.png", annotationPath: nil, thumbnailPath: "/t.jpg",
                           mediaType: .image, capturedAt: date,
                           pixelWidth: 10, pixelHeight: 10, durationMs: nil,
                           fileSizeBytes: 100, sourceApp: nil, deletedAt: nil)
        #expect(a == b)
    }

    @Test("isDeleted reflects deletedAt presence")
    func isDeleted() {
        let liveRow = CaptureRow(uuid: UUID(), filePath: "/x", annotationPath: nil, thumbnailPath: "/t",
                                  mediaType: .image, capturedAt: Date(),
                                  pixelWidth: 1, pixelHeight: 1, durationMs: nil,
                                  fileSizeBytes: 0, sourceApp: nil, deletedAt: nil)
        let trashedRow = CaptureRow(uuid: UUID(), filePath: "/x", annotationPath: nil, thumbnailPath: "/t",
                                     mediaType: .image, capturedAt: Date(),
                                     pixelWidth: 1, pixelHeight: 1, durationMs: nil,
                                     fileSizeBytes: 0, sourceApp: nil, deletedAt: Date())
        #expect(liveRow.isDeleted == false)
        #expect(trashedRow.isDeleted == true)
    }
}
