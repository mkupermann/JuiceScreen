import SwiftUI

/// One overlay's interactive surface.
///
/// Wraps everything in a `GeometryReader` so the gesture's coord space and the
/// rendering coord space are guaranteed to be the same `proxy.size` rectangle.
/// Without this, SwiftUI safe-area insets (which behave differently between
/// app launches once Screen Recording permission has been granted) can cause
/// the gesture to receive coords in a frame that no longer matches where the
/// dim layer / selection rectangle render — producing a visible offset.
struct RegionPickerView: View {

    let canvasSize: CGSize
    let isActive: Bool
    let onBegan: () -> Void
    let onCommitted: (CGRect?) -> Void

    @State private var selection: RegionSelection?
    @State private var cursor: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Dim layer with a punched-out rectangle over the selection.
                Color.black.opacity(0.35)
                    .mask(maskPath)

                if let rect = selection?.normalized {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                if let cursor,
                   let rect = selection?.normalized,
                   rect.width > 0, rect.height > 0 {
                    Text("\(Int(rect.width)) × \(Int(rect.height))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: cursor.x + 16, y: cursor.y + 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if selection == nil {
                            onBegan()
                            selection = RegionSelection(start: value.startLocation, current: value.location)
                        } else if isActive {
                            if var s = selection {
                                s.current = value.location
                                selection = s
                            }
                        }
                        cursor = value.location
                    }
                    .onEnded { _ in
                        guard isActive else { return }
                        if let s = selection, s.isUsable {
                            onCommitted(s.normalized)
                        } else {
                            onCommitted(nil)
                        }
                        selection = nil
                        cursor = nil
                    }
            )
        }
        .ignoresSafeArea()
    }

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
