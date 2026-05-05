import AppKit
import Foundation

@MainActor
public final class LibraryWindowManager {

    private var window: LibraryWindow?
    private let store: LibraryStore
    private let thumbnailStore: ThumbnailStore
    private let onOpenCapture: (CaptureRow) -> Void
    private let onOpenSettings: () -> Void

    public init(store: LibraryStore,
                thumbnailStore: ThumbnailStore,
                onOpenCapture: @escaping (CaptureRow) -> Void,
                onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.thumbnailStore = thumbnailStore
        self.onOpenCapture = onOpenCapture
        self.onOpenSettings = onOpenSettings
    }

    public func show() {
        if let existing = window {
            existing.show()
            return
        }
        let win = LibraryWindow(
            store: store,
            thumbnailStore: thumbnailStore,
            onOpenCapture: onOpenCapture,
            onOpenSettings: onOpenSettings
        )
        window = win
        win.show()
    }
}
