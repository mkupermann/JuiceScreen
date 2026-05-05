import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies a destructive blur or pixelate filter to a region of a CGImage.
/// Returns a new CGImage with the original pixels in `region` replaced by the
/// filtered version (clipped to `region`). Used at export time so recipients
/// of the exported file cannot reverse the blur.
public enum BlurEffect {

    public static func apply(_ props: BlurProps, to image: CGImage) -> CGImage? {
        let ciContext = CIContext(options: nil)
        let baseCI = CIImage(cgImage: image)

        // The blur region in CI coordinates. CI uses bottom-left origin; AppKit/SwiftUI use top-left.
        // We assume `image` is already in the same coordinate space as `props.rect` (both AppKit/top-left)
        // and convert to CI's bottom-left here.
        let imgHeight = CGFloat(image.height)
        let ciRect = CGRect(
            x: props.rect.minX,
            y: imgHeight - props.rect.maxY,
            width: props.rect.width,
            height: props.rect.height
        )

        let filter: CIFilter
        switch props.style {
        case .gaussian:
            let f = CIFilter.gaussianBlur()
            f.inputImage = baseCI.cropped(to: ciRect).clampedToExtent()
            f.radius = Float(props.intensity)
            filter = f
        case .pixelate:
            let f = CIFilter.pixellate()
            f.inputImage = baseCI.cropped(to: ciRect).clampedToExtent()
            f.scale = Float(props.intensity)
            filter = f
        }

        guard let blurredFull = filter.outputImage else { return image }
        let blurredCropped = blurredFull.cropped(to: ciRect)
        let composite = blurredCropped.composited(over: baseCI)

        return ciContext.createCGImage(composite, from: baseCI.extent)
    }
}
