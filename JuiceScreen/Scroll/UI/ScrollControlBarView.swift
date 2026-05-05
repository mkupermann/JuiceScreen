import SwiftUI

struct ScrollControlBarView: View {
    let frameCount: Int
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill").font(.system(size: 24)).foregroundStyle(Color.red)
            }.buttonStyle(.plain).help("Stop scroll capture")

            VStack(alignment: .leading, spacing: 0) {
                Text("Scroll Capture").font(.system(size: 11, weight: .semibold))
                Text("\(frameCount) frame\(frameCount == 1 ? "" : "s") captured")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }

            Divider().frame(height: 24)
            Text("Esc to stop").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }
}
