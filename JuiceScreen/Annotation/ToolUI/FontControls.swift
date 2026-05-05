import AppKit
import SwiftUI

struct FontControls: View {

    @Binding var fontName: String
    @Binding var fontSize: CGFloat

    private let fonts = ["Helvetica", "Helvetica Neue", "Menlo", "SF Pro", "Times New Roman"]

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $fontName) {
                ForEach(fonts, id: \.self) { f in
                    Text(f).tag(f)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Stepper(value: $fontSize, in: 8...96, step: 1) {
                Text("\(Int(fontSize))pt")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 36)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
