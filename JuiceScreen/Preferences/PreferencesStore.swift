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
        static let hotkeysPaused = "hotkeysPaused"
        static let lastRegion = "lastRegion"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Preferences {
        let d = Preferences.defaults
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
            hotkeysPaused:           defaults.object(forKey: Key.hotkeysPaused) as? Bool ?? d.hotkeysPaused,
            lastRegion:              loadRect(Key.lastRegion)
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
        defaults.set(prefs.hotkeysPaused, forKey: Key.hotkeysPaused)
        saveRect(prefs.lastRegion, key: Key.lastRegion)
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
