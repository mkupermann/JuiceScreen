import AppKit
import SwiftUI

struct ColorSwatchPicker: View {

    @Binding var color: NSColor

    private static let presets: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .black, .white
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.presets.indices, id: \.self) { i in
                let preset = Self.presets[i]
                Circle()
                    .fill(Color(preset))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(color == preset ? 0.9 : 0.2), lineWidth: color == preset ? 2 : 1)
                    )
                    .onTapGesture { color = preset }
            }

            // Custom color via NSColorPanel
            Image(systemName: "paintpalette")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(4)
                .onTapGesture { showCustomColorPanel() }
                .help("Custom color")
        }
    }

    private func showCustomColorPanel() {
        let panel = NSColorPanel.shared
        panel.color = color
        panel.makeKeyAndOrderFront(nil)
        // The user-selected color flows back via observation in v0.3.1; for v0.3.0
        // we rely on the seven presets and surface NSColorPanel as an open hook only.
    }
}
