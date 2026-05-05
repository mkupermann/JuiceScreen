import Foundation

public enum StillImageFormat: String, Sendable, CaseIterable {
    case png
    case jpg
}

public enum ImageScale: String, Sendable, CaseIterable {
    case retina      // native scale (2× on Retina displays)
    case oneToOne    // force 1× even on Retina
}

/// All user preferences for JuiceScreen. Pure value type — no I/O.
/// Persisted via `PreferencesStore`.
public struct Preferences: Equatable, Sendable {

    public var firstRunComplete: Bool
    public var startAtLogin: Bool

    public var saveDirectory: URL
    public var defaultStillFormat: StillImageFormat
    public var jpegQuality: Double          // 0.0 – 1.0

    public var captureRegionHotkey: Hotkey
    public var captureWindowHotkey: Hotkey
    public var captureFullScreenHotkey: Hotkey
    public var captureLastRegionHotkey: Hotkey
    public var recordScreenHotkey: Hotkey
    public var openLibraryHotkey: Hotkey
    public var captureScrollHotkey: Hotkey

    public var hotkeysPaused: Bool
    public var lastRegion: CGRect?

    // v0.9 additions
    public var recordingOptions: VideoRecordingOptions
    public var includeCursorInStills: Bool
    public var imageScale: ImageScale
    public var updateAutoCheckEnabled: Bool
    public var updateLastCheckedAt: Date?

    public static let defaults: Preferences = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        let saveDir = pictures.appendingPathComponent("JuiceScreen", isDirectory: true)

        return Preferences(
            firstRunComplete: false,
            startAtLogin: false,
            saveDirectory: saveDir,
            defaultStillFormat: .png,
            jpegQuality: 0.9,
            // virtual keycodes per Carbon: 21=4, 19=2, 20=3, 15=R, 23=5, 37=L, 22=6
            captureRegionHotkey:     Hotkey(keyCode: 21, modifiers: [.command, .shift]),
            captureWindowHotkey:     Hotkey(keyCode: 19, modifiers: [.command, .shift]),
            captureFullScreenHotkey: Hotkey(keyCode: 20, modifiers: [.command, .shift]),
            captureLastRegionHotkey: Hotkey(keyCode: 15, modifiers: [.command, .shift]),
            recordScreenHotkey:      Hotkey(keyCode: 23, modifiers: [.command, .shift]),
            openLibraryHotkey:       Hotkey(keyCode: 37, modifiers: [.command, .shift]),
            captureScrollHotkey:     Hotkey(keyCode: 22, modifiers: [.command, .shift]),
            hotkeysPaused: false,
            lastRegion: nil,
            recordingOptions: .defaults,
            includeCursorInStills: false,
            imageScale: .retina,
            updateAutoCheckEnabled: true,
            updateLastCheckedAt: nil
        )
    }()
}
