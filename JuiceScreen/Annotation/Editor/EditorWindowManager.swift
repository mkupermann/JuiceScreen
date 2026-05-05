import AppKit
import Foundation

@MainActor
public final class EditorWindowManager {

    private var openWindows: [UUID: EditorWindow] = [:]
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "EditorWindowManager")

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    /// Opens an editor window for a successful capture. If a window is already
    /// open for this capture (matched by UUID), brings it to the front instead.
    public func show(for record: CaptureRecord) {
        if let existing = openWindows[record.id] {
            existing.show()
            return
        }
        guard let image = NSImage(contentsOf: record.fileURL) else {
            log.error("Could not load image at \(record.fileURL.path)")
            return
        }
        let window = EditorWindow(
            captureRecord: record,
            baseImage: image,
            preferences: preferences,
            onClose: { [weak self] in
                self?.openWindows.removeValue(forKey: record.id)
            }
        )
        openWindows[record.id] = window
        window.show()
        log.info("Opened editor for capture \(record.id) (\(record.fileURL.lastPathComponent))")
    }
}
