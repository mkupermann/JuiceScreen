import Foundation
import Testing
@testable import JuiceScreen

@Suite("StorageStats")
struct StorageStatsTests {

    private func row(deleted: Bool, bytes: Int64) -> CaptureRow {
        CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/test",
            annotationPath: nil,
            thumbnailPath: "/tmp/thumb",
            mediaType: .image,
            capturedAt: Date(timeIntervalSince1970: 1_715_000_000),
            pixelWidth: 100,
            pixelHeight: 100,
            durationMs: nil,
            fileSizeBytes: bytes,
            sourceApp: nil,
            deletedAt: deleted ? Date() : nil
        )
    }

    @Test("Empty list returns all-zero stats")
    func empty() {
        let stats = StorageStats.compute(from: [])
        #expect(stats.captureCount == 0)
        #expect(stats.totalBytes == 0)
        #expect(stats.trashedCount == 0)
        #expect(stats.trashedBytes == 0)
    }

    @Test("Live + trashed rows split correctly")
    func splitsByDeletedFlag() {
        let rows = [
            row(deleted: false, bytes: 1_000),
            row(deleted: false, bytes: 2_000),
            row(deleted: true,  bytes: 5_000),
            row(deleted: true,  bytes: 7_000)
        ]
        let stats = StorageStats.compute(from: rows)
        #expect(stats.captureCount == 2)
        #expect(stats.totalBytes == 3_000)
        #expect(stats.trashedCount == 2)
        #expect(stats.trashedBytes == 12_000)
    }
}
