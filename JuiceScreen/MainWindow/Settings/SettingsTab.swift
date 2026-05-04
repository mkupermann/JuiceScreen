import Foundation

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, capture, recording, hotkeys, storage, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general:   return "General"
        case .capture:   return "Capture"
        case .recording: return "Recording"
        case .hotkeys:   return "Hotkeys"
        case .storage:   return "Storage"
        case .about:     return "About"
        }
    }

    public var symbol: String {
        switch self {
        case .general:   return "gear"
        case .capture:   return "camera"
        case .recording: return "record.circle"
        case .hotkeys:   return "keyboard"
        case .storage:   return "internaldrive"
        case .about:     return "info.circle"
        }
    }
}
