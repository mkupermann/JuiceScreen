import Foundation

@MainActor
public final class TrimEditorWindowManager {

    private var openWindows: [UUID: TrimEditorWindow] = [:]
    private let trimmer: TrimmerService
    private let log = AppLog.logger(category: "TrimEditorWindowManager")

    public init(trimmer: TrimmerService = TrimmerServiceLive()) {
        self.trimmer = trimmer
    }

    public func show(for row: CaptureRow) {
        if let existing = openWindows[row.uuid] {
            existing.show()
            return
        }
        Task { @MainActor in
            do {
                let win = try await TrimEditorWindow(
                    captureRecord: row,
                    trimmer: trimmer,
                    onClose: { [weak self] in
                        self?.openWindows.removeValue(forKey: row.uuid)
                    }
                )
                openWindows[row.uuid] = win
                win.show()
            } catch {
                log.error("Failed to open trim window for \(row.uuid): \(String(describing: error))")
            }
        }
    }
}
