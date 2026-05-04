import SwiftUI

struct WelcomePanelView: View {

    let regionShortcut: String
    let recordShortcut: String
    let libraryShortcut: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to JuiceScreen")
                .font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                line("Press \(regionShortcut) to capture a region")
                line("Press \(recordShortcut) to record your screen")
                line("Open the Library with \(libraryShortcut)")
            }

            HStack {
                Spacer()
                Button("Got it") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 460)
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.body)
    }
}
