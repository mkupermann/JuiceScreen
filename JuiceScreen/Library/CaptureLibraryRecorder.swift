import AppKit
import Foundation

/// Glue service: after a successful capture, generates a thumbnail and inserts a
/// `CaptureRow` into the `LibraryStore`. Called by `AppDelegate.fireCapture` (Task 13).
public actor CaptureLibraryRecorder {

    private let store: LibraryStore
    private let thumbnailStore: ThumbnailStore
    private let ocrPipeline: OCRPipeline?
    private let log = AppLog.logger(category: "CaptureLibraryRecorder")

    public init(store: LibraryStore, thumbnailStore: ThumbnailStore, ocrPipeline: OCRPipeline? = nil) {
        self.store = store
        self.thumbnailStore = thumbnailStore
        self.ocrPipeline = ocrPipeline
    }

    public func record(_ record: CaptureRecord) async throws {
        // Load the image from disk to generate a thumbnail. (CaptureRecord doesn't
        // carry pixels — they live in the file at fileURL.)
        guard let image = NSImage(contentsOf: record.fileURL) else {
            log.error("Could not read \(record.fileURL.path) to generate thumbnail")
            return
        }

        let thumbnailPath = try thumbnailStore.write(image: image, for: record.id)

        let attrs = try? FileManager.default.attributesOfItem(atPath: record.fileURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        let row = CaptureRow(record: record, fileSizeBytes: fileSize, thumbnailPath: thumbnailPath)
        try await store.insert(row)
        log.info("Indexed capture \(record.id) (\(fileSize) bytes)")

        // Fire-and-forget OCR — failures caught by pipeline; don't gate editor open
        if let pipeline = ocrPipeline {
            Task.detached { [pipeline, captureID = record.id, fileURL = record.fileURL] in
                try? await pipeline.process(captureID: captureID, fileURL: fileURL)
            }
        }
    }
}
