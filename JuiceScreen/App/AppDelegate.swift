import AppKit
import GRDB
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let log = AppLog.logger(category: "App")

    private let permissions: PermissionsService = PermissionsServiceLive()
    private let preferences = PreferencesStore()
    private let hotkeyService = HotkeyService()

    private lazy var sparkleUpdater: SparkleUpdater = SparkleUpdater(preferences: preferences)

    private lazy var captureEngine: CaptureEngine = {
        let prefs = preferences.load()
        let saveDir = SaveDirectoryProvider(rootDirectory: prefs.saveDirectory)
        let writer = CaptureRecordWriter(saveDirectory: saveDir)
        return CaptureEngineLive(writer: writer, preferences: preferences)
    }()

    private lazy var editorWindowManager: EditorWindowManager = {
        EditorWindowManager(preferences: preferences)
    }()

    private lazy var trimEditorWindowManager: TrimEditorWindowManager = {
        TrimEditorWindowManager()
    }()

    private var _scrollCaptureSessionManager: ScrollCaptureSessionManager?
    private var scrollCaptureSessionManager: ScrollCaptureSessionManager {
        if let mgr = _scrollCaptureSessionManager { return mgr }
        let mgr = ScrollCaptureSessionManager(
            serviceFactory: { ScrollCaptureServiceLive() },
            saveDirectory: SaveDirectoryProvider(rootDirectory: preferences.load().saveDirectory),
            onComplete: { [weak self] record in
                guard let self else { return }
                AppLog.logger(category: "App").info("Scroll capture → \(record.fileURL.path)")
                self.editorWindowManager.show(for: record)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await self.captureLibraryRecorder.record(record)
                    } catch {
                        AppLog.logger(category: "App").error("Library recording failed: \(String(describing: error))")
                    }
                }
            },
            onError: { error in
                if case .userCancelled = error {
                    AppLog.logger(category: "App").info("Scroll capture cancelled by user")
                } else {
                    AppLog.logger(category: "App").error("Scroll capture failed: \(String(describing: error))")
                }
            }
        )
        _scrollCaptureSessionManager = mgr
        return mgr
    }

    private var _recordingSessionManager: RecordingSessionManager?
    private var recordingSessionManager: RecordingSessionManager {
        if let mgr = _recordingSessionManager { return mgr }
        let mgr = RecordingSessionManager(
            recorderFactory: { [permissions] in VideoRecorderLive(permissions: permissions) },
            onStopComplete: { [weak self] record in
                guard let self else { return }
                self.menuBar?.setRecordingIndicator(false)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await self.captureLibraryRecorder.record(record)
                    } catch {
                        AppLog.logger(category: "App").error("Library recording failed: \(String(describing: error))")
                    }
                }
            }
        )
        _recordingSessionManager = mgr
        return mgr
    }

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
                switch row.mediaType {
                case .video:
                    self.trimEditorWindowManager.show(for: row)
                case .image:
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
                }
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

        // Skip Sparkle bootstrap in unit/UI test runs — its scheduler blocks the
        // test host on first appcast fetch.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["JUICESCREEN_UI_TEST_MODE"] != nil
        if !isTesting {
            _ = sparkleUpdater   // initializes Sparkle's scheduler
        }

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
            captureScroll:     { [weak self] in self?.scrollCaptureSessionManager.begin() },
            recordScreen:      { [weak self] in self?.handleRecordScreen() },
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
        hotkeyService.register(prefs.captureScrollHotkey,     for: .captureScroll)     { actions.captureScroll() }
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
                case .scroll:      scrollCaptureSessionManager.begin(); return
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

    private func startRecording() {
        Task { @MainActor in
            let mode: VideoRecordingMode = .fullScreen
            let prefs = preferences.load()
            let date = Date()
            let saveDir = SaveDirectoryProvider(rootDirectory: prefs.saveDirectory)
            let outputURL: URL
            do {
                let folder = try saveDir.directory(for: date)
                let filename = FilenameGenerator().filename(for: date, extension: "mp4")
                outputURL = folder.appendingPathComponent(filename)
            } catch {
                AppLog.logger(category: "App").error("Could not prepare output URL: \(String(describing: error))")
                return
            }
            do {
                menuBar?.setRecordingIndicator(true)
                try await recordingSessionManager.start(mode: mode, options: prefs.recordingOptions, outputURL: outputURL)
            } catch {
                AppLog.logger(category: "App").error("Recording failed to start: \(String(describing: error))")
                menuBar?.setRecordingIndicator(false)
            }
        }
    }

    private func stopRecording() {
        Task { @MainActor in
            do {
                try await recordingSessionManager.stop()
            } catch {
                AppLog.logger(category: "App").error("Stop failed: \(String(describing: error))")
            }
        }
    }

    private func handleRecordScreen() {
        if recordingSessionManager.isActive {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func todoLog(_ what: String) {
        log.info("TODO: \(what) action — implemented in a later plan")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
