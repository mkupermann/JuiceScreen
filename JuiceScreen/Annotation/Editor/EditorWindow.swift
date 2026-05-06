import AppKit
import SwiftUI

@MainActor
final class EditorWindow {

    let window: NSWindow
    private let state: EditorState
    private let actions: QuickActions
    private let onClose: () -> Void
    private var closeObserver: NSObjectProtocol?

    init(captureRecord: CaptureRecord, baseImage: NSImage, preferences: PreferencesStore, onClose: @escaping () -> Void) {
        let state = EditorState(captureRecord: captureRecord, baseImage: baseImage)
        self.state = state
        self.actions = QuickActions(state: state, preferences: preferences)
        self.onClose = onClose

        // Initial window size matches the canvas + the new top toolbar's two rows
        // and the 20pt padding around the canvas inside EditorView.
        // Prefer NSImage.size (already in points, accounts for the capture's backing
        // scale) so the window fits the image correctly on Macs with any display
        // density. Fall back to pixel/2 only if the image is zero-sized.
        let imgSize = baseImage.size
        let canvasW = imgSize.width  > 0 ? imgSize.width  : CGFloat(captureRecord.pixelWidth)  / 2
        let canvasH = imgSize.height > 0 ? imgSize.height : CGFloat(captureRecord.pixelHeight) / 2
        // Horizontal: 20pt padding on each side of the canvas.
        let chromeW: CGFloat = 40
        // Vertical: tool-selector row (~46pt) + divider (1pt) + contextual TopBar (40pt)
        // + 20pt padding above the canvas + 20pt padding below.
        let chromeH: CGFloat = 46 + 1 + 40 + 20 + 20

        // Cap the initial size so a huge capture (e.g. 5K) doesn't open a window
        // larger than the screen. The window stays user-resizable.
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = visibleFrame.width - 40
        let maxH = visibleFrame.height - 40
        let contentW = min(canvasW + chromeW, maxW)
        let contentH = min(canvasH + chromeH, maxH)
        let frame = NSRect(x: 0, y: 0, width: contentW, height: contentH)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "JuiceScreen — \(captureRecord.fileURL.lastPathComponent)"
        win.contentView = NSHostingView(rootView: EditorView(state: state, actions: actions))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { _ in
            onClose()
        }
        self.closeObserver = observer
    }

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Confirms discard with the user (if edited) and returns true if the window may close.
    func confirmClose() -> Bool {
        actions.discardConfirm()
    }
}
