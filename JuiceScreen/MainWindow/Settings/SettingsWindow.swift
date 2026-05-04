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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
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

private struct SettingsContainer: View {
    @State private var selection: SettingsTab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab().tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }.tag(SettingsTab.general)
            CaptureTab().tabItem { Label(SettingsTab.capture.title, systemImage: SettingsTab.capture.symbol) }.tag(SettingsTab.capture)
            RecordingTab().tabItem { Label(SettingsTab.recording.title, systemImage: SettingsTab.recording.symbol) }.tag(SettingsTab.recording)
            HotkeysTab().tabItem { Label(SettingsTab.hotkeys.title, systemImage: SettingsTab.hotkeys.symbol) }.tag(SettingsTab.hotkeys)
            StorageTab().tabItem { Label(SettingsTab.storage.title, systemImage: SettingsTab.storage.symbol) }.tag(SettingsTab.storage)
            AboutTab().tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.symbol) }.tag(SettingsTab.about)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
