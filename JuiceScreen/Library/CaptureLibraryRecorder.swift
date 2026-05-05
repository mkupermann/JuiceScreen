import AppKit
import AVFoundation
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
        let isVideo = record.fileURL.pathExtension.lowercased() == "mp4"

        let sourceImage: NSImage?
        if isVideo {
            sourceImage = await Self.firstFrameThumbnail(for: record.fileURL)
        } else {
            sourceImage = NSImage(contentsOf: record.fileURL)
        }
        guard let image = sourceImage else {
            log.error("Could not derive thumbnail for \(record.fileURL.path)")
            return
        }

        let thumbnailPath = try thumbnailStore.write(image: image, for: record.id)
        let attrs = try? FileManager.default.attributesOfItem(atPath: record.fileURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        let row: CaptureRow
        if isVideo {
            row = CaptureRow(
                uuid: record.id,
                filePath: record.fileURL.path,
                annotationPath: nil,
                thumbnailPath: thumbnailPath,
                mediaType: .video,
                capturedAt: record.capturedAt,
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                durationMs: nil,
                fileSizeBytes: fileSize,
                sourceApp: record.sourceApp,
                deletedAt: nil
            )
        } else {
            row = CaptureRow(record: record, fileSizeBytes: fileSize, thumbnailPath: thumbnailPath)
        }

        try await store.insert(row)
        log.info("Indexed capture \(record.id) (\(fileSize) bytes, \(isVideo ? "video" : "image"))")

        // OCR pipeline only for images
        if let pipeline = ocrPipeline, !isVideo {
            Task.detached { [pipeline, captureID = record.id, fileURL = record.fileURL] in
                try? await pipeline.process(captureID: captureID, fileURL: fileURL)
            }
        }
    }

    private static func firstFrameThumbnail(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        do {
            let cg = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }
}
