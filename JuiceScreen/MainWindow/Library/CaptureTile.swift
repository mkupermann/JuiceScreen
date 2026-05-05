import AppKit
import SwiftUI

struct CaptureTile: View {

    let row: CaptureRow
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: size, height: size * 0.7)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(formatBadge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(6)
            }

            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: size)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if FileManager.default.fileExists(atPath: row.thumbnailPath),
           let img = NSImage(contentsOfFile: row.thumbnailPath) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "photo")
                .font(.system(size: size / 4))
                .foregroundStyle(.tertiary)
        }
    }

    private var formatBadge: String {
        switch row.mediaType {
        case .image: return URL(fileURLWithPath: row.filePath).pathExtension.uppercased()
        case .video: return "MP4"
        }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: row.capturedAt, relativeTo: Date())
    }
}
