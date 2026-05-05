import Foundation
import Testing
@testable import JuiceScreen

@Suite("PreferencesStore")
struct PreferencesStoreTests {

    /// Each test gets its own ephemeral UserDefaults to avoid bleed.
    private func makeEphemeralStore() -> (PreferencesStore, UserDefaults) {
        let suiteName = "JuiceScreenTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (PreferencesStore(defaults: defaults), defaults)
    }

    @Test("First read returns sensible defaults")
    func defaults() {
        let (store, _) = makeEphemeralStore()
        let prefs = store.load()
        #expect(prefs.firstRunComplete == false)
        #expect(prefs.startAtLogin == false)
        #expect(prefs.captureRegionHotkey == Hotkey(keyCode: 21, modifiers: [.command, .shift]))
        #expect(prefs.saveDirectory.path.hasSuffix("Pictures/JuiceScreen"))
        #expect(prefs.defaultStillFormat == .png)
        #expect(prefs.jpegQuality == 0.9)
    }

    @Test("Saved hotkey round-trips")
    func hotkeyRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.captureFullScreenHotkey = Hotkey(keyCode: 20, modifiers: [.command, .control])
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.captureFullScreenHotkey == Hotkey(keyCode: 20, modifiers: [.command, .control]))
    }

    @Test("firstRunComplete persists")
    func firstRunCompletePersists() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.firstRunComplete = true
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.firstRunComplete == true)
    }

    @Test("Save directory persists")
    func saveDirectoryPersists() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.saveDirectory = URL(fileURLWithPath: "/tmp/jstest")
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.saveDirectory.path == "/tmp/jstest")
    }

    @Test("lastRegion round-trips")
    func lastRegionRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        #expect(prefs.lastRegion == nil)

        prefs.lastRegion = CGRect(x: 100, y: 200, width: 300, height: 400)
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.lastRegion == CGRect(x: 100, y: 200, width: 300, height: 400))
    }

    @Test("captureScrollHotkey round-trips")
    func captureScrollHotkeyRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.captureScrollHotkey = Hotkey(keyCode: 22, modifiers: [.command, .control])
        store.save(prefs)
        let reloaded = store.load()
        #expect(reloaded.captureScrollHotkey == Hotkey(keyCode: 22, modifiers: [.command, .control]))
    }

    @Test("Defaults expose new v0.9 fields")
    func newFieldDefaults() {
        let (store, _) = makeEphemeralStore()
        let prefs = store.load()
        #expect(prefs.recordingOptions == VideoRecordingOptions.defaults)
        #expect(prefs.includeCursorInStills == false)
        #expect(prefs.imageScale == .retina)
        #expect(prefs.updateAutoCheckEnabled == true)
        #expect(prefs.updateLastCheckedAt == nil)
    }
}
