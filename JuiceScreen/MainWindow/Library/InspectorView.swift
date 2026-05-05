import AppKit
import SwiftUI

struct InspectorView: View {

    let row: CaptureRow
    @Bindable var vm: LibraryViewModel
    let onOpen: (CaptureRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail
            if FileManager.default.fileExists(atPath: row.thumbnailPath),
               let img = NSImage(contentsOfFile: row.thumbnailPath) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                metaRow("Captured", value: capturedDate)
                metaRow("Size", value: "\(row.pixelWidth) × \(row.pixelHeight) px")
                metaRow("File", value: ByteCountFormatter.string(fromByteCount: row.fileSizeBytes, countStyle: .file))
                if let app = row.sourceApp { metaRow("Source", value: app) }
                metaRow("Type", value: row.mediaType == .video ? "Video" : "Image")
            }

            Divider()

            // Action buttons
            VStack(alignment: .leading, spacing: 6) {
                Button { onOpen(row) } label: {
                    Label("Open in Editor", systemImage: "pencil.tip.crop.circle")
                }
                Button { vm.revealSelectedInFinder() } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button { vm.copySelectedFile() } label: {
                    Label("Copy File", systemImage: "doc.on.doc")
                }
                if row.isDeleted == false {
                    Button(role: .destructive) {
                        Task { await vm.moveSelectedToTrash() }
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
            }
            .buttonStyle(.bordered)

            Divider()

            // OCR placeholder (Plan 5)
            VStack(alignment: .leading, spacing: 4) {
                Text("OCR Text").font(.caption).foregroundStyle(.secondary)
                Text("Extracted text will appear here in v0.5 (Plan 5).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .italic()
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 280)
        .background(.regularMaterial)
    }

    private var capturedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: row.capturedAt)
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(.primary)
            Spacer()
        }
    }
}
