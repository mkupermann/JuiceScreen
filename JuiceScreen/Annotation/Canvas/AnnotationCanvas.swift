import AppKit
import SwiftUI

/// Renders the base capture bitmap underneath, then draws every annotation layer
/// in order via `LayerRenderer`. Pure presentation — no gestures (those live in
/// `CanvasGestures` in Task 10).
struct AnnotationCanvas: View {

    let baseImage: NSImage
    let layers: [AnnotationLayer]
    let canvasSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            // Base image
            if let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(Image(cg, scale: 1, label: Text("base")), in: CGRect(origin: .zero, size: size))
            }
            // Layers (bottom-to-top)
            for layer in layers {
                var ctxCopy = ctx
                LayerRenderer.draw(layer, in: &ctxCopy)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
