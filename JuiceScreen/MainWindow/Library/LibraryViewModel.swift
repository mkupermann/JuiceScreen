import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class LibraryViewModel {

    public private(set) var filter: SmartFilter = .all
    public private(set) var captures: [CaptureRow] = []
    public var selectedID: UUID? = nil
    public var tileSize: CGFloat = 150     // 100–300pt slider
    public var searchText: String = ""     // wired to a no-op Plan 5 placeholder for now

    private let store: LibraryStore
    public let thumbnailStore: ThumbnailStore
    private let log = AppLog.logger(category: "LibraryViewModel")

    public init(store: LibraryStore, thumbnailStore: ThumbnailStore) {
        self.store = store
        self.thumbnailStore = thumbnailStore
    }

    public func reload() async {
        do {
            captures = try await store.list(filter: filter)
        } catch {
            log.error("List failed: \(String(describing: error))")
            captures = []
        }
    }

    public func setFilter(_ new: SmartFilter) async {
        filter = new
        selectedID = nil
        await reload()
    }

    public var selectedCapture: CaptureRow? {
        guard let id = selectedID else { return nil }
        return captures.first { $0.uuid == id }
    }

    public func moveSelectedToTrash() async {
        guard let id = selectedID else { return }
        do {
            try await store.softDelete(id: id)
            selectedID = nil
            await reload()
        } catch {
            log.error("softDelete failed: \(String(describing: error))")
        }
    }

    public func revealSelectedInFinder() {
        guard let row = selectedCapture else { return }
        let url = URL(fileURLWithPath: row.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func copySelectedFile() {
        guard let row = selectedCapture else { return }
        let url = URL(fileURLWithPath: row.filePath)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
}
