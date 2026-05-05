import AppKit
import SwiftUI

@MainActor
final class LibraryWindow {

    let window: NSWindow
    private let vm: LibraryViewModel

    init(store: LibraryStore, thumbnailStore: ThumbnailStore,
         onOpenCapture: @escaping (CaptureRow) -> Void,
         onOpenSettings: @escaping () -> Void) {
        let vm = LibraryViewModel(store: store, thumbnailStore: thumbnailStore)
        self.vm = vm

        let frame = NSRect(x: 0, y: 0, width: 980, height: 640)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "JuiceScreen — Library"
        win.contentView = NSHostingView(rootView: LibraryView(vm: vm, onOpen: onOpenCapture, onOpenSettings: onOpenSettings))
        win.center()
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 720, height: 480)
        self.window = win
    }

    func show() {
        Task { await vm.reload() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
