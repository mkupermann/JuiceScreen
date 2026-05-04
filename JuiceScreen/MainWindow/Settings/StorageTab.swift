import SwiftUI

struct StorageTab: View {
    var body: some View {
        Form {
            Section {
                Text("Storage settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Storage")
            } footer: {
                Text("Wired up in a later plan.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
