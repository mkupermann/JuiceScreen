import AppKit
import PDFKit
import Testing
@testable import JuiceScreen

@Suite("PDFEncoder")
struct PDFEncoderTests {

    private func makeImage(size: CGSize, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    @Test("Encodes a non-empty PDF that PDFKit can re-open")
    func encodesValidPDF() throws {
        let image = makeImage(size: CGSize(width: 200, height: 100), color: .systemBlue)
        let data = try PDFEncoder.encode(image)
        #expect(data.count > 0)

        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == 1)
    }

    @Test("Page bounds match image pixel size")
    func pageBoundsMatchImage() throws {
        let image = makeImage(size: CGSize(width: 320, height: 240), color: .systemRed)
        let data = try PDFEncoder.encode(image)
        let doc = try #require(PDFDocument(data: data))
        let page = try #require(doc.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(bounds.width == 320)
        #expect(bounds.height == 240)
    }

    @Test("Throws renderFailed when image has no representations")
    func emptyImageThrows() {
        let empty = NSImage()
        #expect(throws: PDFEncoder.PDFEncoderError.self) {
            try PDFEncoder.encode(empty)
        }
    }
}
