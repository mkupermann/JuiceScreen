import AppKit
import SwiftUI

@MainActor
final class ScrollPromptWindow {

    private var window: NSWindow?

    init() {}

    func show(onStart: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = ScrollPromptView(
            onStart: { [weak self] in self?.close(); onStart() },
            onCancel: { [weak self] in self?.close(); onCancel() }
        )
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Scroll Capture"
        win.contentView = NSHostingView(rootView: view)
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func close() {
        window?.close()
        window = nil
    }
}
