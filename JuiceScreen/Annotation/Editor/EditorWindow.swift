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

        // Initial window size: half the capture's pixel size + chrome (toolbar + palette + topbar).
        let canvasW = CGFloat(captureRecord.pixelWidth) / 2
        let canvasH = CGFloat(captureRecord.pixelHeight) / 2
        let chromeW: CGFloat = 48 + 0   // tool palette
        let chromeH: CGFloat = 40 + 28  // top bar + window title bar
        let frame = NSRect(x: 0, y: 0, width: canvasW + chromeW, height: canvasH + chromeH)

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
