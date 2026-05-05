import Foundation

/// Metadata describing a successful capture. Pure value type — no I/O, no NSImage payload
/// (the pixels live in the file at `fileURL`).
public struct CaptureRecord: Equatable, Hashable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let captureType: CaptureType
    public let capturedAt: Date
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sourceApp: String?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        captureType: CaptureType,
        capturedAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceApp: String?
    ) {
        self.id = id
        self.fileURL = fileURL
        self.captureType = captureType
        self.capturedAt = capturedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceApp = sourceApp
    }
}
