import AppKit
import SwiftUI

struct InspectorView: View {

    let row: CaptureRow
    @Bindable var vm: LibraryViewModel
    let onOpen: (CaptureRow) -> Void

    @State private var ocrText: String? = nil

    private func loadOCR() async {
        let paths = LibraryPaths()
        let store = OCRSidecarStore(paths: paths)
        do {
            if let result = try store.read(for: row.uuid) {
                ocrText = result.fullText
            } else {
                ocrText = nil
            }
        } catch {
            ocrText = nil
        }
    }

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

            VStack(alignment: .leading, spacing: 4) {
                Text("OCR Text").font(.caption).foregroundStyle(.secondary)

                if let text = ocrText, !text.isEmpty {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)

                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    } label: {
                        Label("Copy text", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                } else if ocrText == nil {
                    Text("OCR pending…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary).italic()
                } else {
                    Text("No text recognised.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary).italic()
                }
            }
            .task(id: row.uuid) {
                await loadOCR()
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
