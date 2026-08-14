import AppKit
import SwiftUI

/// Multi-display overlay plumbing shared by every picker.
///
/// Owns one borderless overlay window per `NSScreen`, decides which overlay owns
/// the in-flight gesture, installs the Esc-to-cancel monitor, and bridges the
/// callback flow to `async`. It deliberately knows nothing about geometry —
/// callers convert coordinates themselves, using the screen this returns.
@MainActor
final class OverlayPickerHost<Payload> {

    struct Result {
        let payload: Payload
        let screen: NSScreen
    }

    /// Builds the SwiftUI surface for one overlay. `isActive` is false for every
    /// overlay except the one that started the current gesture.
    typealias ContentBuilder = (
        _ screen: NSScreen,
        _ isActive: Bool,
        _ onBegan: @escaping () -> Void,
        _ onCommitted: @escaping (Payload?) -> Void
    ) -> AnyView

    private struct Overlay {
        let window: RegionPickerOverlayWindow
        let screen: NSScreen
    }

    private var overlays: [Overlay] = []
    private var continuation: CheckedContinuation<Result, Error>?
    private var activeScreen: NSScreen?
    private var escMonitor: Any?
    private var builder: ContentBuilder?

    func pick(content: @escaping ContentBuilder) async throws -> Result {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }
        builder = content

        for screen in screens {
            let win = RegionPickerOverlayWindow(frame: screen.frame)
            overlays.append(Overlay(window: win, screen: screen))
        }
        for entry in overlays {
            installContent(for: entry)
            entry.window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Result, Error>) in
            self.continuation = cont
        }
    }

    // MARK: - Overlay content

    private func installContent(for entry: Overlay) {
        guard let builder else { return }
        let view = builder(
            entry.screen,
            activeScreen == nil ? true : (activeScreen === entry.screen),
            { [weak self] in self?.markActive(entry.screen) },
            { [weak self] payload in self?.commit(payload, on: entry.screen) }
        )
        entry.window.contentView = NSHostingView(rootView: view)
    }

    /// First overlay to start a gesture owns it; the others are rebuilt with
    /// `isActive = false` so they stop responding.
    private func markActive(_ screen: NSScreen) {
        guard activeScreen == nil else { return }
        activeScreen = screen
        for entry in overlays where entry.screen !== screen {
            installContent(for: entry)
        }
    }

    // MARK: - Esc

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.commit(nil, on: self.activeScreen ?? self.overlays.first!.screen)
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor {
            NSEvent.removeMonitor(m)
            escMonitor = nil
        }
    }

    // MARK: - Commit

    private func commit(_ payload: Payload?, on screen: NSScreen) {
        guard continuation != nil else { return }   // already finished
        guard let payload else {
            finish(.failure(CaptureError.userCancelled))
            return
        }
        finish(.success(Result(payload: payload, screen: screen)))
    }

    private func finish(_ outcome: Swift.Result<Result, Error>) {
        removeEscMonitor()
        for entry in overlays { entry.window.orderOut(nil) }
        overlays.removeAll()
        activeScreen = nil
        builder = nil
        switch outcome {
        case .success(let result): continuation?.resume(returning: result)
        case .failure(let error):  continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
