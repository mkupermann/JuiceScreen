import AppKit

/// Action callbacks supplied to the menu builder. Each is fired when the corresponding
/// menu item is chosen. Real implementations land in later plans (capture, recording, etc.);
/// for Foundation they log a TODO message.
@MainActor
public struct MenuBarActions {
    public var captureRegion: () -> Void
    public var captureWindow: () -> Void
    public var captureFullScreen: () -> Void
    public var captureLastRegion: () -> Void
    public var recordScreen: () -> Void
    public var openLibrary: () -> Void
    public var openPreferences: () -> Void
    public var quit: () -> Void

    public init(captureRegion: @escaping () -> Void,
                captureWindow: @escaping () -> Void,
                captureFullScreen: @escaping () -> Void,
                captureLastRegion: @escaping () -> Void,
                recordScreen: @escaping () -> Void,
                openLibrary: @escaping () -> Void,
                openPreferences: @escaping () -> Void,
                quit: @escaping () -> Void) {
        self.captureRegion = captureRegion
        self.captureWindow = captureWindow
        self.captureFullScreen = captureFullScreen
        self.captureLastRegion = captureLastRegion
        self.recordScreen = recordScreen
        self.openLibrary = openLibrary
        self.openPreferences = openPreferences
        self.quit = quit
    }
}

@MainActor
public enum MenuBarMenuBuilder {

    public static func build(prefs: Preferences, actions: MenuBarActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item("Capture Region",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureRegionHotkey),
                          action: actions.captureRegion))
        menu.addItem(item("Capture Window",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureWindowHotkey),
                          action: actions.captureWindow))
        menu.addItem(item("Capture Full Screen",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureFullScreenHotkey),
                          action: actions.captureFullScreen))
        menu.addItem(item("Capture Last Region",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureLastRegionHotkey),
                          action: actions.captureLastRegion))

        menu.addItem(.separator())
        menu.addItem(item("Record Screen",
                          shortcut: KeyCodeFormatter.string(for: prefs.recordScreenHotkey),
                          action: actions.recordScreen))

        menu.addItem(.separator())
        menu.addItem(item("Open Library",
                          shortcut: KeyCodeFormatter.string(for: prefs.openLibraryHotkey),
                          action: actions.openLibrary))

        menu.addItem(.separator())
        menu.addItem(item("Preferences…",
                          shortcut: "⌘,",
                          action: actions.openPreferences))
        menu.addItem(item("Quit JuiceScreen",
                          shortcut: "⌘Q",
                          action: actions.quit))

        return menu
    }

    private static func item(_ title: String, shortcut: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.keyEquivalent = ""             // hotkeys handled by HotkeyService, not NSMenu
        item.toolTip = shortcut
        let attr = NSMutableAttributedString(string: title)
        // Render shortcut in a faded trailing chunk for visual parity with system menus
        let pad = String(repeating: " ", count: max(2, 28 - title.count))
        attr.append(NSAttributedString(string: pad + shortcut,
                                       attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        item.attributedTitle = attr
        return item
    }
}

/// Trampolines `NSMenuItem` action selectors into a Swift closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.closure = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { closure() }
}
