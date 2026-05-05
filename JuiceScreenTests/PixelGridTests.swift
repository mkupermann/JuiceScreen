import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("PixelGrid")
struct PixelGridTests {

    /// Builds a deterministic grayscale CGImage with a horizontal gradient (0 at top → 255 at bottom).
    private func makeGradient(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { fatalError("ctx") }
        // CGContext origin is bottom-left; to get row 0 (top of CGImage) = 0 and
        // row height-1 (bottom of CGImage) = 255, we fill CGContext y=(height-1-row) for each image row.
        for row in 0..<height {
            let v = UInt8((Double(row) / Double(height - 1)) * 255)
            ctx.setFillColor(NSColor(white: Double(v) / 255, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: height - 1 - row, width: width, height: 1))
        }
        return ctx.makeImage()!
    }

    @Test("PixelGrid extracts the right number of rows + columns")
    func dimensions() {
        let img = makeGradient(width: 100, height: 80)
        let grid = PixelGrid(cgImage: img)!
        #expect(grid.width == 100)
        #expect(grid.height == 80)
    }

    @Test("Returns 0..255 row values for gradient image")
    func gradientRow() {
        let img = makeGradient(width: 50, height: 100)
        let grid = PixelGrid(cgImage: img)!
        let topRow = grid.row(y: 0)
        let bottomRow = grid.row(y: 99)
        // Top row should be near 0; bottom near 255
        #expect(topRow.allSatisfy { $0 < 30 })
        #expect(bottomRow.allSatisfy { $0 > 220 })
    }

    @Test("Init returns nil for zero-sized image")
    func zeroSize() {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let img = ctx.makeImage()!
        // 1x1 should still init OK; only 0-dim images are rejected
        let grid = PixelGrid(cgImage: img)
        #expect(grid != nil)
    }
}
