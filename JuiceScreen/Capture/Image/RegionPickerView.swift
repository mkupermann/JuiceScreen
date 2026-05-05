import SwiftUI

/// Overlay rendering: dim everything by 35% black, punch a clear hole over
/// the current selection, draw a 1pt white stroke around the selection,
/// and show the live pixel dimensions next to the cursor.
struct RegionPickerView: View {

    let canvasSize: CGSize
    let selection: RegionSelection?
    let cursor: CGPoint?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .mask(maskPath)

            if let rect = selection?.normalized {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            if let cursor, let rect = selection?.normalized, rect.width > 0, rect.height > 0 {
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: cursor.x + 16, y: cursor.y + 16)
            }
        }
    }

    /// A mask that darkens everything EXCEPT the selection rectangle.
    /// Implemented as the canvas with an even-odd-filled rectangle removed.
    @ViewBuilder
    private var maskPath: some View {
        if let rect = selection?.normalized, rect.width > 0, rect.height > 0 {
            ZStack {
                Color.white
                Color.black
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            Color.white
        }
    }
}
