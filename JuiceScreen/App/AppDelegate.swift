import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let log = AppLog.logger(category: "App")

    private let permissions: PermissionsService = PermissionsServiceLive()
    private let preferences = PreferencesStore()
    private let hotkeyService = HotkeyService()

    private var menuBar: MenuBarController?
    private var firstRun: FirstRunCoordinator?
    private var activationPolicy: ActivationPolicyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("JuiceScreen launching")

        // Activation policy controller (sets initial state to .accessory)
        activationPolicy = ActivationPolicyController()

        // Menu bar
        let actions = MenuBarActions(
            captureRegion:     { [weak self] in self?.todoLog("captureRegion") },
            captureWindow:     { [weak self] in self?.todoLog("captureWindow") },
            captureFullScreen: { [weak self] in self?.todoLog("captureFullScreen") },
            captureLastRegion: { [weak self] in self?.todoLog("captureLastRegion") },
            recordScreen:      { [weak self] in self?.todoLog("recordScreen") },
            openLibrary:       { [weak self] in self?.todoLog("openLibrary") },
            openPreferences:   { SettingsWindow.show() },
            quit:              { NSApp.terminate(nil) }
        )
        let prefs = preferences.load()
        menuBar = MenuBarController(prefs: prefs, actions: actions)

        // Hotkeys
        registerHotkeys(prefs: prefs, actions: actions)

        // First-run wizard (no-op if already complete OR if running in UI test mode)
        if ProcessInfo.processInfo.environment["JUICESCREEN_UI_TEST_MODE"] == nil {
            let coordinator = FirstRunCoordinator(permissions: permissions, preferences: preferences)
            firstRun = coordinator
            coordinator.start()
            FirstRunWindow.showIfNeeded(coordinator: coordinator)
        }
    }

    private func registerHotkeys(prefs: Preferences, actions: MenuBarActions) {
        hotkeyService.register(prefs.captureRegionHotkey,     for: .captureRegion)     { actions.captureRegion() }
        hotkeyService.register(prefs.captureWindowHotkey,     for: .captureWindow)     { actions.captureWindow() }
        hotkeyService.register(prefs.captureFullScreenHotkey, for: .captureFullScreen) { actions.captureFullScreen() }
        hotkeyService.register(prefs.captureLastRegionHotkey, for: .captureLastRegion) { actions.captureLastRegion() }
        hotkeyService.register(prefs.recordScreenHotkey,      for: .recordScreen)      { actions.recordScreen() }
        hotkeyService.register(prefs.openLibraryHotkey,       for: .openLibrary)       { actions.openLibrary() }
    }

    private func todoLog(_ what: String) {
        log.info("TODO: \(what) action — implemented in a later plan")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app — don't quit when user closes the Settings window.
        false
    }
}
