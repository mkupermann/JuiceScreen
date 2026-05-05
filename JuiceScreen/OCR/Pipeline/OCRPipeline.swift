import Foundation

/// Orchestrator that runs OCR on a capture's image file and persists the result.
/// Fire-and-forget from `CaptureLibraryRecorder`'s perspective: errors log but
/// never bubble up to disrupt the capture flow.
public actor OCRPipeline {

    private let ocrService: OCRService
    private let sidecarStore: OCRSidecarStore
    private let libraryStore: LibraryStore
    private let log = AppLog.logger(category: "OCRPipeline")

    public init(ocrService: OCRService, sidecarStore: OCRSidecarStore, libraryStore: LibraryStore) {
        self.ocrService = ocrService
        self.sidecarStore = sidecarStore
        self.libraryStore = libraryStore
    }

    public func process(captureID: UUID, fileURL: URL) async throws {
        do {
            let result = try await ocrService.recognize(imageAt: fileURL)
            try sidecarStore.write(result, for: captureID)
            try await libraryStore.upsertOCRText(id: captureID, text: result.fullText)
            log.info("OCR succeeded for \(captureID): \(result.regions.count) regions")
        } catch let error as OCRError {
            log.error("OCR failed for \(captureID): \(String(describing: error))")
            // swallow — capture still works without OCR
        } catch {
            log.error("OCR pipeline error for \(captureID): \(String(describing: error))")
        }
    }
}
