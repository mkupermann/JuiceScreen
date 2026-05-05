import SwiftUI

struct EmptyStateView: View {

    let filter: SmartFilter

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .trash ? "trash.slash" : "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(emptyMessage)
                .font(.title3)
                .foregroundStyle(.secondary)

            if filter == .all {
                Text("Press ⌘⇧4 to capture a region.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyMessage: String {
        switch filter {
        case .all:        return "No captures yet"
        case .today:      return "No captures today"
        case .thisWeek:   return "No captures this week"
        case .thisMonth:  return "No captures this month"
        case .videos:     return "No videos"
        case .images:     return "No images"
        case .trash:      return "Trash is empty"
        }
    }
}
