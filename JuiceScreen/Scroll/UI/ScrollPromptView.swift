import SwiftUI

struct ScrollPromptView: View {

    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scroll Capture")
                        .font(.title3).fontWeight(.semibold)
                    Text("Captures a tall image while you scroll.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                bullet("Click Start, then scroll the chosen area slowly.")
                bullet("JuiceScreen captures frames at 10fps and stitches them.")
                bullet("Press Esc or click Stop on the floating bar when done.")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Honest limits")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Sticky headers/footers, lazy-loaded content, and pages with parallax effects can produce ghosting or torn images. Native macOS apps and simple web pages stitch cleanly.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start") { onStart() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.tertiary)
            Text(text).font(.system(size: 12))
        }
    }
}
