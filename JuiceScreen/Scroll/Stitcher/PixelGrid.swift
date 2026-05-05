import CoreGraphics
import Foundation

/// Reads a CGImage (any color space) into a flat grayscale byte buffer for SSD computation.
/// Conversion uses standard luminance weights (0.30 R + 0.59 G + 0.11 B).
public struct PixelGrid: Sendable {

    public let width: Int
    public let height: Int
    private let bytes: [UInt8]   // length = width * height, row-major, top-left origin

    public init?(cgImage: CGImage) {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }

        let w = cgImage.width
        let h = cgImage.height
        var buffer = [UInt8](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()

        let ctx = buffer.withUnsafeMutableBytes { ptr -> CGContext? in
            CGContext(
                data: ptr.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }
        guard let ctx else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        self.width = w
        self.height = h
        self.bytes = buffer
    }

    /// Returns the byte values for row `y` (0 == top).
    public func row(y: Int) -> [UInt8] {
        guard y >= 0, y < height else { return [] }
        let start = y * width
        return Array(bytes[start..<(start + width)])
    }

    /// Sum-of-squared-differences between row `y1` of self and row `y2` of `other`.
    /// Both grids must have the same width; returns `.infinity` if they don't.
    public func rowSSD(y1: Int, other: PixelGrid, y2: Int) -> Double {
        guard width == other.width,
              y1 >= 0, y1 < height,
              y2 >= 0, y2 < other.height else {
            return .infinity
        }
        var ssd: Double = 0
        let off1 = y1 * width
        let off2 = y2 * other.width
        for x in 0..<width {
            let d = Double(bytes[off1 + x]) - Double(other.bytes[off2 + x])
            ssd += d * d
        }
        return ssd
    }
}
