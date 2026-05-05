import Foundation
import Sparkle

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of the app does not import Sparkle.
@MainActor
public final class SparkleUpdater {

    private let controller: SPUStandardUpdaterController
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "SparkleUpdater")

    public init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let prefs = preferences.load()
        self.controller.updater.automaticallyChecksForUpdates = prefs.updateAutoCheckEnabled
    }

    /// Triggers the standard "Check for Updates…" UI flow.
    public func checkNow() {
        log.info("User-initiated update check")
        controller.checkForUpdates(nil)
        var prefs = preferences.load()
        prefs.updateLastCheckedAt = Date()
        preferences.save(prefs)
    }

    public var isAutomaticChecksEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            var prefs = preferences.load()
            prefs.updateAutoCheckEnabled = newValue
            preferences.save(prefs)
        }
    }

    public var lastCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }
}
