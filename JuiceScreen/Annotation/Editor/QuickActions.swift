import AppKit
import SwiftUI

@MainActor
public final class QuickActions {

    private let state: EditorState
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "QuickActions")

    public init(state: EditorState, preferences: PreferencesStore) {
        self.state = state
        self.preferences = preferences
    }

    /// Copies the flattened image to the system pasteboard as PNG.
    public func copyToClipboard() {
        do {
            let flattened = try AnnotationRenderer.render(state.document)
            let data = try PNGEncoder.encode(flattened)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: .png)
            log.info("Copied flattened image to clipboard (\(data.count) bytes)")
        } catch {
            log.error("Copy failed: \(String(describing: error))")
            NSSound.beep()
        }
    }

    /// Saves to the original capture's location, replacing the file in place.
    public func save() {
        let url = state.captureRecord.fileURL
        let format: ExportService.Format = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" ? .jpg : .png
        let quality = preferences.load().jpegQuality
        do {
            try ExportService.export(document: state.document, format: format, jpegQuality: quality, to: url)
            log.info("Saved → \(url.path)")
            state.isEdited = false
        } catch {
            log.error("Save failed: \(String(describing: error))")
            presentSaveError(error)
        }
    }

    /// Opens an `NSSavePanel` and writes to the chosen location.
    public func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = state.captureRecord.fileURL.deletingPathExtension().lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format: ExportService.Format = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" ? .jpg : .png
        let quality = preferences.load().jpegQuality
        do {
            try ExportService.export(document: state.document, format: format, jpegQuality: quality, to: url)
            log.info("Save As → \(url.path)")
            state.isEdited = false
        } catch {
            log.error("Save As failed: \(String(describing: error))")
            presentSaveError(error)
        }
    }

    /// Reveals the original capture file in Finder.
    public func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([state.captureRecord.fileURL])
    }

    /// Asks the user to confirm if there are unsaved edits, then closes the editor window.
    /// Returns true if the caller should close the window.
    public func discardConfirm() -> Bool {
        guard state.isEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard edits?"
        alert.informativeText = "You have unsaved annotation changes. Closing will lose them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Helpers

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not save"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
