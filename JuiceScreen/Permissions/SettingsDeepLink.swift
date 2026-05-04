import AppKit

/// Deep links into specific panes of System Settings (macOS 13+).
/// URLs change between major macOS versions; these are valid for macOS 14+.
public enum SettingsDeepLink {

    public static func open(_ permission: PermissionType) {
        let url = url(for: permission)
        NSWorkspace.shared.open(url)
    }

    public static func openKeyboardShortcuts() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!
        NSWorkspace.shared.open(url)
    }

    private static func url(for permission: PermissionType) -> URL {
        switch permission {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }
}
