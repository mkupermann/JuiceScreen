import AppKit
import GRDB
import SwiftUI

struct StorageTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences
    @State private var stats: StorageStats = .empty
    @State private var isEmptyingTrash = false
    @State private var showEmptyTrashConfirm = false

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                statsRow("Captures", value: "\(stats.captureCount)")
                statsRow("Disk usage", value: ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file))
                statsRow("Trashed", value: "\(stats.trashedCount) (\(ByteCountFormatter.string(fromByteCount: stats.trashedBytes, countStyle: .file)))")
            } header: { Text("Library") }

            Section {
                Button("Open save folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([prefs.saveDirectory])
                }
                Button(isEmptyingTrash ? "Emptying…" : "Empty trash now") {
                    showEmptyTrashConfirm = true
                }
                .disabled(isEmptyingTrash || stats.trashedCount == 0)
                .confirmationDialog(
                    "Permanently delete \(stats.trashedCount) trashed item(s)?",
                    isPresented: $showEmptyTrashConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Empty Trash", role: .destructive) {
                        Task { await emptyTrash() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This frees \(ByteCountFormatter.string(fromByteCount: stats.trashedBytes, countStyle: .file)) but cannot be undone.")
                }
            } header: { Text("Actions") }

            Section {
                Text("OCR languages: en-US, de-DE")
                    .foregroundStyle(.secondary)
                Text("Custom language selection lands in v1.1.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } header: { Text("OCR") }
        }
        .formStyle(.grouped)
        .padding()
        .task { await reloadStats() }
    }

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func reloadStats() async {
        do {
            let paths = LibraryPaths()
            let dbURL = try paths.databaseURL()
            let queue = try DatabaseQueue(path: dbURL.path)
            try LibrarySchema.migrator().migrate(queue)
            let store = LibraryStoreLive(databaseQueue: queue)
            let live = try await store.list(filter: .all)
            let trashed = try await store.list(filter: .trash)
            stats = StorageStats.compute(from: live + trashed)
        } catch {
            stats = .empty
            AppLog.logger(category: "Settings").error("StorageTab stats failed: \(String(describing: error))")
        }
    }

    private func emptyTrash() async {
        isEmptyingTrash = true
        defer { isEmptyingTrash = false }
        do {
            let paths = LibraryPaths()
            let dbURL = try paths.databaseURL()
            let queue = try DatabaseQueue(path: dbURL.path)
            try LibrarySchema.migrator().migrate(queue)
            let store = LibraryStoreLive(databaseQueue: queue)

            let trashed = try await store.list(filter: .trash)
            let trashService = TrashService(captureRoot: prefs.saveDirectory)
            for row in trashed {
                let url = URL(fileURLWithPath: row.filePath)
                try? trashService.permanentlyDelete(trashedFile: url)
            }
            _ = try await store.emptyTrash()
            await reloadStats()
        } catch {
            AppLog.logger(category: "Settings").error("emptyTrash failed: \(String(describing: error))")
        }
    }
}
