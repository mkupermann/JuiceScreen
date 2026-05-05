import AppKit
import PDFKit
import Testing
@testable import JuiceScreen

@Suite("ExportService.pdf")
@MainActor
struct ExportServicePDFTests {

    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        color.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return img
    }

    private func tempURL(ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JS-export-\(UUID().uuidString).\(ext)")
    }

    @Test("Export PDF produces a valid single-page PDFDocument (round-trip via PDFKit)")
    func exportsPDF() async throws {
        let doc = AnnotationDocument(baseImage: solidImage(width: 64, height: 64, color: .red))
        let url = tempURL(ext: "pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.export(document: doc, format: .pdf, jpegQuality: 0.9, to: url)

        let data = try Data(contentsOf: url)
        let pdfDoc = PDFDocument(data: data)
        #expect(pdfDoc != nil)
        #expect(pdfDoc?.pageCount == 1)
    }

    @Test("Format.pdf is present in CaseIterable allCases")
    func pdfIsCaseIterable() {
        #expect(ExportService.Format.allCases.contains(.pdf))
    }
}
