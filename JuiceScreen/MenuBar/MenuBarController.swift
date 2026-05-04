import AppKit

@MainActor
public final class MenuBarController {

    private let log = AppLog.logger(category: "MenuBar")
    private let statusItem: NSStatusItem
    private var prefs: Preferences
    private let actions: MenuBarActions

    public init(prefs: Preferences, actions: MenuBarActions) {
        self.prefs = prefs
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()
        rebuildMenu()
        log.info("Menu bar item created")
    }

    /// Rebuild the menu when preferences (e.g., hotkeys) change.
    public func update(prefs: Preferences) {
        self.prefs = prefs
        rebuildMenu()
    }

    /// Toggle the menu-bar icon to indicate an active recording.
    public func setRecordingIndicator(_ recording: Bool) {
        statusItem.button?.image = recording ? recordingImage : idleImage
    }

    // MARK: - Setup

    private func configureButton() {
        statusItem.button?.image = idleImage
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "JuiceScreen"
    }

    private func rebuildMenu() {
        statusItem.menu = MenuBarMenuBuilder.build(prefs: prefs, actions: actions)
    }

    // MARK: - Icons (system-symbol stubs; designed art lands in Plan 10)

    private var idleImage: NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "JuiceScreen")
        img?.isTemplate = true
        return img?.withSymbolConfiguration(cfg)
    }

    private var recordingImage: NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
        img?.isTemplate = true
        return img?.withSymbolConfiguration(cfg)
    }
}
