import Foundation

/// SQLite-shaped row stored in the `captures` table. Distinct from `CaptureRecord` (the
/// in-memory result of a capture operation) — `CaptureRow` includes index-only fields
/// like `thumbnailPath`, `fileSizeBytes`, `deletedAt` that the capture flow does not produce.
public struct CaptureRow: Equatable, Hashable, Sendable {

    public let uuid: UUID
    public let filePath: String
    public let annotationPath: String?
    public let thumbnailPath: String
    public let mediaType: MediaType
    public let capturedAt: Date
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let durationMs: Int?
    public let fileSizeBytes: Int64
    public let sourceApp: String?
    public let deletedAt: Date?

    public init(
        uuid: UUID,
        filePath: String,
        annotationPath: String?,
        thumbnailPath: String,
        mediaType: MediaType,
        capturedAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        durationMs: Int?,
        fileSizeBytes: Int64,
        sourceApp: String?,
        deletedAt: Date?
    ) {
        self.uuid = uuid
        self.filePath = filePath
        self.annotationPath = annotationPath
        self.thumbnailPath = thumbnailPath
        self.mediaType = mediaType
        self.capturedAt = capturedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationMs = durationMs
        self.fileSizeBytes = fileSizeBytes
        self.sourceApp = sourceApp
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// Convenience init from a freshly-completed `CaptureRecord` plus index-only fields.
    /// Plan 4 only writes image rows; Plan 6 (video recording) will add `.video` rows.
    public init(record: CaptureRecord, fileSizeBytes: Int64, thumbnailPath: String) {
        self.init(
            uuid: record.id,
            filePath: record.fileURL.path,
            annotationPath: nil,
            thumbnailPath: thumbnailPath,
            mediaType: .image,
            capturedAt: record.capturedAt,
            pixelWidth: record.pixelWidth,
            pixelHeight: record.pixelHeight,
            durationMs: nil,
            fileSizeBytes: fileSizeBytes,
            sourceApp: record.sourceApp,
            deletedAt: nil
        )
    }
}
