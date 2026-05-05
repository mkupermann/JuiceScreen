import Foundation

public enum SmartFilter: String, CaseIterable, Sendable, Hashable, Identifiable {
    case all
    case today
    case thisWeek
    case thisMonth
    case videos
    case images
    case trash

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:       return "All"
        case .today:     return "Today"
        case .thisWeek:  return "This Week"
        case .thisMonth: return "This Month"
        case .videos:    return "Videos"
        case .images:    return "Images"
        case .trash:     return "Trash"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .all:       return "tray.full"
        case .today:     return "calendar"
        case .thisWeek:  return "calendar.badge.clock"
        case .thisMonth: return "calendar.circle"
        case .videos:    return "video"
        case .images:    return "photo"
        case .trash:     return "trash"
        }
    }

    public var includesTrash: Bool { self == .trash }
}
