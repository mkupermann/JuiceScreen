import SwiftUI
import AppKit

@MainActor
public final class SettingsWindow {

    private static var window: NSWindow?

    public static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "JuiceScreen Settings"
        window.contentView = NSHostingView(rootView: SettingsContainer())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }
}

/// Sidebar (list of tabs) + detail (the selected tab's content) — the modern macOS
/// Settings layout. Replaces the older `TabView` build which rendered blank content
/// outside the SwiftUI `Settings` scene on some macOS configurations.
private struct SettingsContainer: View {
    @State private var selection: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .tag(Optional(tab))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection ?? .general {
            case .general:   GeneralTab()
            case .capture:   CaptureTab()
            case .recording: RecordingTab()
            case .hotkeys:   HotkeysTab()
            case .storage:   StorageTab()
            case .about:     AboutTab()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
