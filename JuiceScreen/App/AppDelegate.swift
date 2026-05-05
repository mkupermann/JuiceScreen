import AppKit
import GRDB
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

    private lazy var editorWindowManager: EditorWindowManager = {
        EditorWindowManager(preferences: preferences)
    }()

    private lazy var libraryPaths: LibraryPaths = LibraryPaths()

    private lazy var libraryStore: LibraryStore = {
        do {
            let dbURL = try libraryPaths.databaseURL()
            let queue = try DatabaseQueue(path: dbURL.path)
            try LibrarySchema.migrator().migrate(queue)
            return LibraryStoreLive(databaseQueue: queue)
        } catch {
            log.error("Failed to open library database: \(String(describing: error))")
            return FakeLibraryStore()
        }
    }()

    private lazy var thumbnailStore: ThumbnailStore = ThumbnailStore(paths: libraryPaths)

    private lazy var ocrService: OCRService = OCRServiceLive()

    private lazy var ocrSidecarStore: OCRSidecarStore = OCRSidecarStore(paths: libraryPaths)

    private lazy var ocrPipeline: OCRPipeline = {
        OCRPipeline(
            ocrService: ocrService,
            sidecarStore: ocrSidecarStore,
            libraryStore: libraryStore
        )
    }()

    private lazy var captureLibraryRecorder: CaptureLibraryRecorder = {
        CaptureLibraryRecorder(
            store: libraryStore,
            thumbnailStore: thumbnailStore,
            ocrPipeline: ocrPipeline
        )
    }()

    private lazy var libraryWindowManager: LibraryWindowManager = {
        LibraryWindowManager(
            store: libraryStore,
            thumbnailStore: thumbnailStore,
            onOpenCapture: { [weak self] row in
                guard let self else { return }
                let record = CaptureRecord(
                    id: row.uuid,
                    fileURL: URL(fileURLWithPath: row.filePath),
                    captureType: .region,
                    capturedAt: row.capturedAt,
                    pixelWidth: row.pixelWidth,
                    pixelHeight: row.pixelHeight,
                    sourceApp: row.sourceApp
                )
                self.editorWindowManager.show(for: record)
            },
            onOpenSettings: { SettingsWindow.show() }
        )
    }()

    private var menuBar: MenuBarController?
    private var firstRun: FirstRunCoordinator?
    private var activationPolicy: ActivationPolicyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("JuiceScreen launching")

        activationPolicy = ActivationPolicyController()

        // Background: GC trashed files older than 30 days
        Task.detached { [preferences] in
            let saveDir = preferences.load().saveDirectory
            let gc = TrashGC(captureRoot: saveDir)
            do {
                let removed = try await gc.sweep()
                if removed > 0 {
                    AppLog.logger(category: "App").info("TrashGC removed \(removed) files older than 30 days")
                }
            } catch {
                AppLog.logger(category: "App").error("TrashGC failed: \(String(describing: error))")
            }
        }

        // Background: OCR backfill for captures that have no FTS5 entry yet
        Task.detached { [libraryStore, ocrPipeline] in
            let backfill = OCRBackfill(store: libraryStore, pipeline: ocrPipeline)
            await backfill.run()
        }

        let actions = MenuBarActions(
            captureRegion:     { [weak self] in self?.fireCapture(.region) },
            captureWindow:     { [weak self] in self?.fireCapture(.window) },
            captureFullScreen: { [weak self] in self?.fireCapture(.fullScreen) },
            captureLastRegion: { [weak self] in self?.fireCapture(.lastRegion) },
            recordScreen:      { [weak self] in self?.todoLog("recordScreen") },
            openLibrary:       { [weak self] in self?.libraryWindowManager.show() },
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
                editorWindowManager.show(for: record)
                Task { [captureLibraryRecorder] in
                    do {
                        try await captureLibraryRecorder.record(record)
                    } catch {
                        AppLog.logger(category: "App").error("Library recording failed: \(String(describing: error))")
                    }
                }
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
