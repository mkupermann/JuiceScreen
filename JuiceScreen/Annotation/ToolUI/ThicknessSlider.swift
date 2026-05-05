import SwiftUI

struct ThicknessSlider: View {

    @Binding var thickness: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lineweight").font(.system(size: 12)).foregroundStyle(.secondary)
            Slider(value: $thickness, in: 1...20, step: 1)
                .frame(width: 100)
            Text("\(Int(thickness))")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 18)
                .foregroundStyle(.secondary)
        }
    }
}
