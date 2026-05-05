import SwiftUI

/// Overlays a dashed selection outline and 8 resize handles around a selected
/// `AnnotationLayer`. Hit-testing is disabled — gestures live in `CanvasGestures`.
struct SelectionHandlesView: View {

    let layer: AnnotationLayer

    var body: some View {
        let rect = layer.boundingRect
        ZStack {
            // Dashed rectangle outline
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // 8 handles at corners and edge midpoints
            ForEach(handlePositions(in: rect), id: \.self) { pt in
                Rectangle()
                    .fill(Color.white)
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .position(pt)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Private

    /// Returns the 8 handle positions: 4 corners (TL, TR, BR, BL) + 4 edge midpoints
    /// (top, right, bottom, left).
    private func handlePositions(in r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY), // top-left
            CGPoint(x: r.midX, y: r.minY), // top-center
            CGPoint(x: r.maxX, y: r.minY), // top-right
            CGPoint(x: r.maxX, y: r.midY), // right-center
            CGPoint(x: r.maxX, y: r.maxY), // bottom-right
            CGPoint(x: r.midX, y: r.maxY), // bottom-center
            CGPoint(x: r.minX, y: r.maxY), // bottom-left
            CGPoint(x: r.minX, y: r.midY), // left-center
        ]
    }
}
