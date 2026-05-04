import SwiftUI

struct GeneralTab: View {
    var body: some View {
        Form {
            Section {
                Text("General settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("General")
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
