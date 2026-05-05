import SwiftUI

struct SidebarView: View {
    @Bindable var vm: LibraryViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        List {
            Section("Library") {
                ForEach(SmartFilter.allCases) { f in row(filter: f) }
            }
            Section {
                Button(action: onOpenSettings) { Label("Settings…", systemImage: "gear") }
                    .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    private func row(filter f: SmartFilter) -> some View {
        Button { Task { await vm.setFilter(f) } } label: {
            Label(f.displayName, systemImage: f.sfSymbol)
                .foregroundStyle(vm.filter == f ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
