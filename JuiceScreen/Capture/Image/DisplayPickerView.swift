import ScreenCaptureKit
import SwiftUI

/// Minimal SwiftUI picker shown when the user has 2+ displays attached.
/// The display rows render their dimensions ("3024 × 1964") and a numeric label.
struct DisplayPickerView: View {

    let displays: [SCDisplay]
    let onPick: (SCDisplay) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a display")
                .font(.title3).fontWeight(.semibold)

            ForEach(Array(displays.enumerated()), id: \.element.displayID) { (idx, display) in
                Button {
                    onPick(display)
                } label: {
                    HStack {
                        Image(systemName: "display")
                        Text("Display \(idx + 1)")
                        Spacer()
                        Text("\(display.width) × \(display.height)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(8)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
