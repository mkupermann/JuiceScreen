import Foundation

public actor OCRBackfill {
    private let store: LibraryStore
    private let pipeline: OCRPipeline
    private let log = AppLog.logger(category: "OCRBackfill")

    public init(store: LibraryStore, pipeline: OCRPipeline) {
        self.store = store
        self.pipeline = pipeline
    }

    public func run(maxConcurrency: Int = 2) async {
        let pending: [(id: UUID, filePath: String)]
        do {
            pending = try await store.captureIDsWithoutOCR()
        } catch {
            log.error("OCR backfill: failed to fetch pending captures: \(String(describing: error))")
            return
        }

        guard !pending.isEmpty else {
            log.info("OCR backfill: nothing to do")
            return
        }
        log.info("OCR backfill: \(pending.count) capture(s) pending")

        await withTaskGroup(of: Void.self) { group in
            var index = 0

            func enqueueNext() {
                guard index < pending.count else { return }
                let item = pending[index]
                index += 1
                group.addTask {
                    let fileURL = URL(fileURLWithPath: item.filePath)
                    try? await self.pipeline.process(captureID: item.id, fileURL: fileURL)
                }
            }

            // Prime with up to maxConcurrency tasks
            for _ in 0 ..< min(maxConcurrency, pending.count) {
                enqueueNext()
            }

            // As each finishes, start the next
            for await _ in group {
                enqueueNext()
            }
        }

        log.info("OCR backfill: complete")
    }
}
