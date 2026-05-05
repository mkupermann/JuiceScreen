import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let log = AppLog.logger(category: "App")

    private let permissions: PermissionsService = PermissionsServiceLive()
    private let preferences = PreferencesStore()
    private let hotkeyService = HotkeyService()

    private lazy var captureEngine: CaptureEngine = {
        let prefs = preferences.load()
        let saveDir = SaveDirectoryProvider(rootDirectory: prefs.saveDirectory)
        let writer = CaptureRecordWriter(saveDirectory: saveDir)
        return CaptureEngineLive(writer: writer, preferences: preferences)
    }()

    private var menuBar: MenuBarController?
    private var firstRun: FirstRunCoordinator?
    private var activationPolicy: ActivationPolicyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("JuiceScreen launching")

        activationPolicy = ActivationPolicyController()

        let actions = MenuBarActions(
            captureRegion:     { [weak self] in self?.fireCapture(.region) },
            captureWindow:     { [weak self] in self?.fireCapture(.window) },
            captureFullScreen: { [weak self] in self?.fireCapture(.fullScreen) },
            captureLastRegion: { [weak self] in self?.fireCapture(.lastRegion) },
            recordScreen:      { [weak self] in self?.todoLog("recordScreen") },
            openLibrary:       { [weak self] in self?.todoLog("openLibrary") },
            openPreferences:   { SettingsWindow.show() },
            quit:              { NSApp.terminate(nil) }
        )
        let prefs = preferences.load()
        menuBar = MenuBarController(prefs: prefs, actions: actions)

        registerHotkeys(prefs: prefs, actions: actions)

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

    private func fireCapture(_ type: CaptureType) {
        let engine = captureEngine
        Task { @MainActor in
            do {
                let record: CaptureRecord
                switch type {
                case .region:      record = try await engine.captureRegion()
                case .window:      record = try await engine.captureWindow()
                case .fullScreen:  record = try await engine.captureFullScreen()
                case .lastRegion:  record = try await engine.captureLastRegion()
                }
                log.info("Captured \(String(describing: record.captureType)) → \(record.fileURL.path)")
            } catch CaptureError.userCancelled {
                log.info("Capture cancelled by user")
            } catch CaptureError.missingScreenRecordingPermission {
                log.error("Capture failed: Screen Recording permission missing")
                permissions.openSettings(for: .screenRecording)
            } catch {
                log.error("Capture failed: \(String(describing: error))")
            }
        }
    }

    private func todoLog(_ what: String) {
        log.info("TODO: \(what) action — implemented in a later plan")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
