import AppKit
import SwiftUI

@MainActor
final class RecordingControlWindow {

    let window: NSWindow
    private var hostingView: NSHostingView<RecordingControlBarView>?
    private var elapsed: TimeInterval = 0
    private var micEnabled: Bool = false

    init(initialMicEnabled: Bool, onStop: @escaping () -> Void, onToggleMic: @escaping () -> Void) {
        let frame = NSRect(x: 0, y: 0, width: 220, height: 48)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Position: bottom-center of primary screen, 64pt above bottom
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: screenFrame.midX - frame.width / 2,
                y: screenFrame.minY + 64
            ))
        }

        self.window = window
        self.micEnabled = initialMicEnabled

        let view = RecordingControlBarView(
            elapsed: elapsed,
            micEnabled: initialMicEnabled,
            onStop: onStop,
            onToggleMic: onToggleMic
        )
        let host = NSHostingView(rootView: view)
        window.contentView = host
        self.hostingView = host
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }

    func update(elapsed: TimeInterval, micEnabled: Bool, onStop: @escaping () -> Void, onToggleMic: @escaping () -> Void) {
        self.elapsed = elapsed
        self.micEnabled = micEnabled
        hostingView?.rootView = RecordingControlBarView(
            elapsed: elapsed,
            micEnabled: micEnabled,
            onStop: onStop,
            onToggleMic: onToggleMic
        )
    }
}
