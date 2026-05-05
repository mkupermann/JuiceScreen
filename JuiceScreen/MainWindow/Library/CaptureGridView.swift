import SwiftUI

struct CaptureGridView: View {

    @Bindable var vm: LibraryViewModel
    let onOpen: (CaptureRow) -> Void

    var body: some View {
        ScrollView {
            if vm.captures.isEmpty {
                EmptyStateView(filter: vm.filter)
                    .frame(minHeight: 400)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(vm.captures, id: \.uuid) { row in
                        CaptureTile(row: row, isSelected: vm.selectedID == row.uuid, size: vm.tileSize)
                            .onTapGesture { vm.selectedID = row.uuid }
                            .onTapGesture(count: 2) { onOpen(row) }
                            .contextMenu {
                                Button("Open in Editor") { onOpen(row) }
                                Button("Reveal in Finder") {
                                    vm.selectedID = row.uuid
                                    vm.revealSelectedInFinder()
                                }
                                Button("Copy File") {
                                    vm.selectedID = row.uuid
                                    vm.copySelectedFile()
                                }
                                Divider()
                                Button("Move to Trash", role: .destructive) {
                                    vm.selectedID = row.uuid
                                    Task { await vm.moveSelectedToTrash() }
                                }
                            }
                    }
                }
                .padding(16)
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: vm.tileSize, maximum: vm.tileSize), spacing: 16, alignment: .topLeading)]
    }
}
