import AppKit
import SwiftUI

@MainActor
final class ScrollControlWindow {
    let window: NSWindow
    private var hostingView: NSHostingView<ScrollControlBarView>?
    private var localKeyMonitor: Any?

    init(onStop: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let windowWidth: CGFloat = 240
            let windowHeight: CGFloat = 56
            let x = visibleFrame.midX - windowWidth / 2
            let y = visibleFrame.minY + 64
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let barView = ScrollControlBarView(frameCount: 0, onStop: onStop)
        let hosting = NSHostingView(rootView: barView)
        hosting.frame = NSRect(x: 0, y: 0, width: 240, height: 56)
        panel.contentView = hosting

        self.window = panel
        self.hostingView = hosting

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil else { return event }
            if event.keyCode == 53 { // Esc
                onStop()
                return nil
            }
            return event
        }
    }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }

    func update(frameCount: Int, onStop: @escaping () -> Void) {
        hostingView?.rootView = ScrollControlBarView(frameCount: frameCount, onStop: onStop)
    }
}
