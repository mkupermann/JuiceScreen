import SwiftUI
import AppKit

@MainActor
public final class FirstRunWindow {

    private static var window: NSWindow?

    public static func showIfNeeded(coordinator: FirstRunCoordinator) {
        guard coordinator.state != .done else { return }
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "JuiceScreen — Setup"
        window.contentView = NSHostingView(rootView: FirstRunHost(coordinator: coordinator) {
            window.close()
            Self.window = nil
        })
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }
}

private struct FirstRunHost: View {
    @Bindable var coordinator: FirstRunCoordinator
    let onDone: () -> Void

    var body: some View {
        Group {
            switch coordinator.state {
            case .awaitingScreenRecording:
                ScreenRecordingPermissionView(
                    onGrant: { Task { await coordinator.requestScreenRecording() } },
                    onOpenSettings: { coordinator.openScreenRecordingSettings() },
                    onSkip: { coordinator.skipScreenRecording() }
                )

            case .awaitingHotkeyDecision:
                HotkeyConflictWizardView(
                    onOpenKeyboardSettings: { SettingsDeepLink.openKeyboardShortcuts() },
                    onUseAlternativeDefaults: { coordinator.useAlternativeHotkeys() },
                    onSkip: { coordinator.acceptHotkeyDefaults() }
                )

            case .awaitingWelcomeDismiss:
                WelcomePanelView(
                    regionShortcut: "⌘⇧4",
                    recordShortcut: "⌘⇧5",
                    libraryShortcut: "⌘⇧L",
                    onDismiss: { coordinator.dismissWelcome() }
                )

            case .done:
                Color.clear.onAppear { onDone() }
            }
        }
    }
}
