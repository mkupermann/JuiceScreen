import AppKit
import ScreenCaptureKit
import SwiftUI

/// Shows the display picker as a modal NSWindow and bridges its result to async/await.
@MainActor
enum DisplayPickerWindow {

    static func pick(from displays: [SCDisplay]) async throws -> SCDisplay {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SCDisplay, Error>) in
            var window: NSWindow!
            let onPick: (SCDisplay) -> Void = { display in
                window.close()
                cont.resume(returning: display)
            }
            let onCancel: () -> Void = {
                window.close()
                cont.resume(throwing: CaptureError.userCancelled)
            }
            let view = DisplayPickerView(displays: displays, onPick: onPick, onCancel: onCancel)

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "JuiceScreen — Capture Full Screen"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
