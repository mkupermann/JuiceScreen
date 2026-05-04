import SwiftUI

struct HotkeysTab: View {
    var body: some View {
        Form {
            Section {
                Text("Hotkey configuration will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkeys")
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
