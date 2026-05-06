import SwiftUI
import AppKit

/// Live on-canvas preview for blur and pixelate layers.
///
/// The annotation editor's `LayerRenderer` runs inside SwiftUI's `GraphicsContext`,
/// which cannot blur the underlying base image (forward-rendering only). This view
/// is a separate ZStack overlay that renders the base image at full canvas size,
/// blurs or pixelates it, and masks the result to each blur layer's rect — so the
/// user sees the effect live, not a placeholder.
///
/// The destructive blur applied at export time still goes through `BlurEffect`
/// (via Core Image), so what the user sees here matches what saves.
struct BlurPreviewOverlay: View {

    let baseImage: NSImage
    let layers: [AnnotationLayer]
    let canvasSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(blurLayers, id: \.id) { entry in
                preview(for: entry.props)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private struct Entry: Identifiable {
        let id: UUID
        let props: BlurProps
    }

    private var blurLayers: [Entry] {
        layers.compactMap { layer in
            if case let .blur(p, id) = layer { return Entry(id: id, props: p) }
            return nil
        }
    }

    /// Layer rects are in canvas-point coordinates. Render the base image at canvas
    /// size with the chosen filter, then mask to a rectangle at the layer's rect.
    @ViewBuilder
    private func preview(for props: BlurProps) -> some View {
        Image(nsImage: baseImage)
            .resizable()
            .interpolation(props.style == .pixelate ? .none : .high)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .modifier(StyleEffect(style: props.style, intensity: props.intensity))
            .mask(
                Rectangle()
                    .frame(width: props.rect.width, height: props.rect.height)
                    .position(x: props.rect.midX, y: props.rect.midY)
            )
    }
}

/// Apply gaussian blur or simulate pixelate via downsample-then-upsample.
private struct StyleEffect: ViewModifier {
    let style: BlurProps.Style
    let intensity: CGFloat

    func body(content: Content) -> some View {
        switch style {
        case .gaussian:
            content.blur(radius: intensity)
        case .pixelate:
            // SwiftUI has no native pixelate. Approximate via heavy downscale with
            // nearest-neighbor interpolation, then upscale to original. The export
            // pipeline uses CIPixellate for the real artifact (BlurEffect.apply).
            let factor = 1.0 / max(intensity, 1.0)
            content
                .scaleEffect(factor, anchor: .topLeading)
                .scaleEffect(1.0 / factor, anchor: .topLeading)
        }
    }
}
