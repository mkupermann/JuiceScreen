import AppKit
import SwiftUI

/// Flattens an `AnnotationDocument` into a single `NSImage`, applying:
///   1. Destructive blur regions (so recipients cannot reverse them)
///   2. All non-blur layers via `LayerRenderer` into a SwiftUI ImageRenderer pipeline
///   3. Crop, if `document.canvasCrop` is set
///
/// The output preserves the base image's pixel resolution.
@MainActor
public enum AnnotationRenderer {

    public enum RenderError: Error, Equatable {
        case noBaseCGImage
        case rendererFailed
    }

    public static func render(_ document: AnnotationDocument) throws -> NSImage {
        guard let baseCG = document.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw RenderError.noBaseCGImage
        }

        // Step 1: apply blur layers destructively to the base CGImage
        var workingCG = baseCG
        for layer in document.layers {
            if case .blur(let p, _) = layer {
                if let next = BlurEffect.apply(p, to: workingCG) {
                    workingCG = next
                }
            }
        }

        // Step 2: build a SwiftUI Canvas with the blurred base + non-blur layers, render to image
        let pixelWidth = workingCG.width
        let pixelHeight = workingCG.height
        let pointSize = NSSize(width: pixelWidth, height: pixelHeight)
        let nonBlurLayers = document.layers.filter {
            if case .blur = $0 { return false } else { return true }
        }

        let view = AnnotationCanvas(
            baseImage: NSImage(cgImage: workingCG, size: pointSize),
            layers: nonBlurLayers,
            canvasSize: pointSize
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1   // already at native pixel resolution
        guard let flattened = renderer.nsImage else {
            throw RenderError.rendererFailed
        }

        // Step 3: crop if requested
        if let crop = document.canvasCrop, crop.width >= 1, crop.height >= 1 {
            return cropped(image: flattened, to: crop)
        }
        return flattened
    }

    private static func cropped(image: NSImage, to rect: CGRect) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        // Convert top-left rect to CGImage coordinates (CGImage origin is top-left already).
        let scaleX = CGFloat(cg.width) / image.size.width
        let scaleY = CGFloat(cg.height) / image.size.height
        let scaledRect = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let croppedCG = cg.cropping(to: scaledRect) else { return image }
        return NSImage(cgImage: croppedCG, size: rect.size)
    }
}
