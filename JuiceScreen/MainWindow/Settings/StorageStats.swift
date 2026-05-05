import Foundation

public struct StorageStats: Equatable, Sendable {

    public let captureCount: Int
    public let totalBytes: Int64
    public let trashedCount: Int
    public let trashedBytes: Int64

    public static let empty = StorageStats(
        captureCount: 0, totalBytes: 0, trashedCount: 0, trashedBytes: 0
    )

    public static func compute(from rows: [CaptureRow]) -> StorageStats {
        var liveCount = 0
        var liveBytes: Int64 = 0
        var trashCount = 0
        var trashBytes: Int64 = 0
        for row in rows {
            if row.isDeleted {
                trashCount += 1
                trashBytes += row.fileSizeBytes
            } else {
                liveCount += 1
                liveBytes += row.fileSizeBytes
            }
        }
        return StorageStats(
            captureCount: liveCount,
            totalBytes: liveBytes,
            trashedCount: trashCount,
            trashedBytes: trashBytes
        )
    }
}
