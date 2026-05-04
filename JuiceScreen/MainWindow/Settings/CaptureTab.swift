import SwiftUI

struct CaptureTab: View {
    var body: some View {
        Form {
            Section {
                Text("Capture settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Capture")
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
