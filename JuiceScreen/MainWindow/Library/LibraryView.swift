import AppKit
import SwiftUI

struct LibraryView: View {

    @Bindable var vm: LibraryViewModel
    let onOpen: (CaptureRow) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(vm: vm, onOpenSettings: onOpenSettings)

            Divider()

            VStack(spacing: 0) {
                searchBar
                CaptureGridView(vm: vm, onOpen: onOpen)
            }

            if let row = vm.selectedCapture {
                Divider()
                InspectorView(row: row, vm: vm, onOpen: onOpen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: vm.selectedID)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Slider(value: $vm.tileSize, in: 100...300, step: 10)
                    .frame(width: 120)
                    .help("Tile size")
            }
        }
        .task { await vm.reload() }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search by OCR text (Plan 5)", text: $vm.searchText)
                .textFieldStyle(.plain)
                .disabled(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}
