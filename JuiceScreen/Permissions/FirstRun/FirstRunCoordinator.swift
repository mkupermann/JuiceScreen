import Foundation
import Observation

/// Drives the four-step first-run flow: screen recording permission → hotkey decision → welcome → done.
/// Owns no UI; views observe `state` and call back into the coordinator's methods.
@MainActor
@Observable
public final class FirstRunCoordinator {

    public enum State: Equatable {
        case awaitingScreenRecording
        case awaitingHotkeyDecision
        case awaitingWelcomeDismiss
        case done
    }

    public private(set) var state: State

    private let permissions: PermissionsService
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "FirstRun")

    public init(permissions: PermissionsService, preferences: PreferencesStore) {
        self.permissions = permissions
        self.preferences = preferences

        let prefs = preferences.load()
        if prefs.firstRunComplete {
            self.state = .done
        } else {
            switch permissions.status(for: .screenRecording) {
            case .granted:      self.state = .awaitingHotkeyDecision
            case .denied,
                 .notDetermined: self.state = .awaitingScreenRecording
            }
        }
    }

    /// Re-evaluates state. Call when the view wants to drive the flow forward without an action
    /// (for example, to skip to .awaitingHotkeyDecision when permission is already granted).
    public func start() {
        guard state != .done else { return }
        if state == .awaitingScreenRecording,
           permissions.status(for: .screenRecording) == .granted {
            state = .awaitingHotkeyDecision
        }
    }

    public func requestScreenRecording() async {
        let result = await permissions.request(.screenRecording)
        log.info("Screen recording permission result: \(String(describing: result))")
        if result == .granted {
            state = .awaitingHotkeyDecision
        }
    }

    public func openScreenRecordingSettings() {
        permissions.openSettings(for: .screenRecording)
    }

    public func skipScreenRecording() {
        // User chose to continue without permission. Capture won't work but the app should not be blocked.
        state = .awaitingHotkeyDecision
    }

    public func acceptHotkeyDefaults() {
        state = .awaitingWelcomeDismiss
    }

    public func useAlternativeHotkeys() {
        var prefs = preferences.load()
        // Swap shift→control on the conflicting trio so we coexist with the macOS shortcuts.
        prefs.captureRegionHotkey     = Hotkey(keyCode: 21, modifiers: [.command, .control])
        prefs.captureFullScreenHotkey = Hotkey(keyCode: 20, modifiers: [.command, .control])
        prefs.recordScreenHotkey      = Hotkey(keyCode: 23, modifiers: [.command, .control])
        preferences.save(prefs)
        state = .awaitingWelcomeDismiss
    }

    public func dismissWelcome() {
        var prefs = preferences.load()
        prefs.firstRunComplete = true
        preferences.save(prefs)
        state = .done
    }
}
