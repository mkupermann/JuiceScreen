import SwiftUI

struct RecordingTab: View {
    var body: some View {
        Form {
            Section {
                Text("Recording settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Recording")
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
