import AppKit
import SwiftUI

/// `NSHostingView` returns `acceptsFirstMouse = false` by default, which means
/// the very first click on a SwiftUI button inside a non-activating panel is
/// consumed by AppKit's activation path instead of firing the button. This
/// subclass returns `true` so the click hits the button on first press.
private final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class RecordingControlWindow {

    let window: NSWindow
    private var hostingView: FirstClickHostingView<RecordingControlBarView>?
    private var elapsed: TimeInterval = 0
    private var micEnabled: Bool = false

    init(initialMicEnabled: Bool, onStop: @escaping () -> Void, onToggleMic: @escaping () -> Void) {
        let frame = NSRect(x: 0, y: 0, width: 220, height: 48)
        // NSPanel handles `.nonactivatingPanel`; on plain NSWindow the flag is a
        // no-op. Combined with `isMovableByWindowBackground = true`, that meant
        // AppKit treated every mouseDown as a window-drag and the SwiftUI buttons
        // inside the NSHostingView never received their click.
        let window = NSPanel(
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
        // Disable drag-to-move so clicks reach the Stop and Mic buttons.
        window.isMovableByWindowBackground = false
        // Required so SwiftUI buttons inside a borderless non-activating panel
        // can take momentary key focus when clicked, which is what makes their
        // action fire. Without this, clicks register on the panel but never
        // reach the buttons.
        window.becomesKeyOnlyIfNeeded = true
        window.hidesOnDeactivate = false

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
        let host = FirstClickHostingView(rootView: view)
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
