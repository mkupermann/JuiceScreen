import Foundation

/// Reads/writes `Preferences` via `UserDefaults`. Single source of truth at runtime.
public final class PreferencesStore: @unchecked Sendable {

    private enum Key {
        static let firstRunComplete = "firstRunComplete"
        static let startAtLogin = "startAtLogin"
        static let saveDirectory = "saveDirectory"
        static let defaultStillFormat = "defaultStillFormat"
        static let jpegQuality = "jpegQuality"
        static let captureRegionHotkey = "captureRegionHotkey"
        static let captureWindowHotkey = "captureWindowHotkey"
        static let captureFullScreenHotkey = "captureFullScreenHotkey"
        static let captureLastRegionHotkey = "captureLastRegionHotkey"
        static let recordScreenHotkey = "recordScreenHotkey"
        static let openLibraryHotkey = "openLibraryHotkey"
        static let captureScrollHotkey = "captureScrollHotkey"
        static let hotkeysPaused = "hotkeysPaused"
        static let lastRegion = "lastRegion"

        // v0.9
        static let recTargetFps = "recordingTargetFps"
        static let recSystemAudio = "recordingSystemAudio"
        static let recMicrophone = "recordingMicrophone"
        static let recCursorHighlight = "recordingCursorHighlight"
        static let recClickPulse = "recordingClickPulse"
        static let recKeystrokes = "recordingKeystrokes"
        static let includeCursorInStills = "includeCursorInStills"
        static let imageScale = "imageScale"
        static let updateAutoCheckEnabled = "updateAutoCheckEnabled"
        static let updateLastCheckedAt = "updateLastCheckedAt"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Preferences {
        let d = Preferences.defaults
        let opts = VideoRecordingOptions(
            targetFps:           defaults.object(forKey: Key.recTargetFps) as? Int ?? d.recordingOptions.targetFps,
            captureSystemAudio:  defaults.object(forKey: Key.recSystemAudio) as? Bool ?? d.recordingOptions.captureSystemAudio,
            captureMicrophone:   defaults.object(forKey: Key.recMicrophone) as? Bool ?? d.recordingOptions.captureMicrophone,
            showCursorHighlight: defaults.object(forKey: Key.recCursorHighlight) as? Bool ?? d.recordingOptions.showCursorHighlight,
            showClickPulse:      defaults.object(forKey: Key.recClickPulse) as? Bool ?? d.recordingOptions.showClickPulse,
            showKeystrokes:      defaults.object(forKey: Key.recKeystrokes) as? Bool ?? d.recordingOptions.showKeystrokes
        )
        let imageScale: ImageScale = (defaults.string(forKey: Key.imageScale).flatMap(ImageScale.init(rawValue:))) ?? d.imageScale
        let lastCheckedSeconds = defaults.object(forKey: Key.updateLastCheckedAt) as? Double
        return Preferences(
            firstRunComplete:        defaults.object(forKey: Key.firstRunComplete) as? Bool ?? d.firstRunComplete,
            startAtLogin:            defaults.object(forKey: Key.startAtLogin) as? Bool ?? d.startAtLogin,
            saveDirectory:           loadURL(Key.saveDirectory) ?? d.saveDirectory,
            defaultStillFormat:      loadEnum(Key.defaultStillFormat) ?? d.defaultStillFormat,
            jpegQuality:             defaults.object(forKey: Key.jpegQuality) as? Double ?? d.jpegQuality,
            captureRegionHotkey:     loadHotkey(Key.captureRegionHotkey)     ?? d.captureRegionHotkey,
            captureWindowHotkey:     loadHotkey(Key.captureWindowHotkey)     ?? d.captureWindowHotkey,
            captureFullScreenHotkey: loadHotkey(Key.captureFullScreenHotkey) ?? d.captureFullScreenHotkey,
            captureLastRegionHotkey: loadHotkey(Key.captureLastRegionHotkey) ?? d.captureLastRegionHotkey,
            recordScreenHotkey:      loadHotkey(Key.recordScreenHotkey)      ?? d.recordScreenHotkey,
            openLibraryHotkey:       loadHotkey(Key.openLibraryHotkey)       ?? d.openLibraryHotkey,
            captureScrollHotkey:     loadHotkey(Key.captureScrollHotkey)     ?? d.captureScrollHotkey,
            hotkeysPaused:           defaults.object(forKey: Key.hotkeysPaused) as? Bool ?? d.hotkeysPaused,
            lastRegion:              loadRect(Key.lastRegion),
            recordingOptions:        opts,
            includeCursorInStills:   defaults.object(forKey: Key.includeCursorInStills) as? Bool ?? d.includeCursorInStills,
            imageScale:              imageScale,
            updateAutoCheckEnabled:  defaults.object(forKey: Key.updateAutoCheckEnabled) as? Bool ?? d.updateAutoCheckEnabled,
            updateLastCheckedAt:     lastCheckedSeconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    public func save(_ prefs: Preferences) {
        defaults.set(prefs.firstRunComplete, forKey: Key.firstRunComplete)
        defaults.set(prefs.startAtLogin, forKey: Key.startAtLogin)
        saveURL(prefs.saveDirectory, key: Key.saveDirectory)
        defaults.set(prefs.defaultStillFormat.rawValue, forKey: Key.defaultStillFormat)
        defaults.set(prefs.jpegQuality, forKey: Key.jpegQuality)
        saveHotkey(prefs.captureRegionHotkey,     key: Key.captureRegionHotkey)
        saveHotkey(prefs.captureWindowHotkey,     key: Key.captureWindowHotkey)
        saveHotkey(prefs.captureFullScreenHotkey, key: Key.captureFullScreenHotkey)
        saveHotkey(prefs.captureLastRegionHotkey, key: Key.captureLastRegionHotkey)
        saveHotkey(prefs.recordScreenHotkey,      key: Key.recordScreenHotkey)
        saveHotkey(prefs.openLibraryHotkey,       key: Key.openLibraryHotkey)
        saveHotkey(prefs.captureScrollHotkey,     key: Key.captureScrollHotkey)
        defaults.set(prefs.hotkeysPaused, forKey: Key.hotkeysPaused)
        saveRect(prefs.lastRegion, key: Key.lastRegion)

        defaults.set(prefs.recordingOptions.targetFps, forKey: Key.recTargetFps)
        defaults.set(prefs.recordingOptions.captureSystemAudio, forKey: Key.recSystemAudio)
        defaults.set(prefs.recordingOptions.captureMicrophone, forKey: Key.recMicrophone)
        defaults.set(prefs.recordingOptions.showCursorHighlight, forKey: Key.recCursorHighlight)
        defaults.set(prefs.recordingOptions.showClickPulse, forKey: Key.recClickPulse)
        defaults.set(prefs.recordingOptions.showKeystrokes, forKey: Key.recKeystrokes)
        defaults.set(prefs.includeCursorInStills, forKey: Key.includeCursorInStills)
        defaults.set(prefs.imageScale.rawValue, forKey: Key.imageScale)
        defaults.set(prefs.updateAutoCheckEnabled, forKey: Key.updateAutoCheckEnabled)
        if let date = prefs.updateLastCheckedAt {
            defaults.set(date.timeIntervalSince1970, forKey: Key.updateLastCheckedAt)
        } else {
            defaults.removeObject(forKey: Key.updateLastCheckedAt)
        }
    }

    // MARK: - Helpers

    private func loadHotkey(_ key: String) -> Hotkey? {
        guard let dict = defaults.dictionary(forKey: key) as? [String: UInt32] else { return nil }
        return Hotkey(dictionary: dict)
    }

    private func saveHotkey(_ hotkey: Hotkey, key: String) {
        defaults.set(hotkey.asDictionary, forKey: key)
    }

    private func loadURL(_ key: String) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func saveURL(_ url: URL, key: String) {
        defaults.set(url.path, forKey: key)
    }

    private func loadEnum(_ key: String) -> StillImageFormat? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return StillImageFormat(rawValue: raw)
    }

    private func loadRect(_ key: String) -> CGRect? {
        guard let dict = defaults.dictionary(forKey: key) as? [String: Double] else { return nil }
        guard let x = dict["x"], let y = dict["y"],
              let w = dict["w"], let h = dict["h"] else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func saveRect(_ rect: CGRect?, key: String) {
        guard let rect else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set([
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "w": Double(rect.size.width),
            "h": Double(rect.size.height)
        ], forKey: key)
    }
}
