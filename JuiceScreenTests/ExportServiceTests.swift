import AppKit
import Testing
@testable import JuiceScreen

@Suite("ExportService")
@MainActor
struct ExportServiceTests {

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

    @Test("Export PNG produces a file starting with PNG signature")
    func exportPNG() async throws {
        let doc = AnnotationDocument(baseImage: solidImage(width: 64, height: 64, color: .red))
        let url = tempURL(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.export(document: doc, format: .png, jpegQuality: 0.9, to: url)

        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test("Export JPG produces a file starting with JPEG SOI")
    func exportJPG() async throws {
        let doc = AnnotationDocument(baseImage: solidImage(width: 64, height: 64, color: .blue))
        let url = tempURL(ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.export(document: doc, format: .jpg, jpegQuality: 0.85, to: url)

        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(2)) == [0xFF, 0xD8])
    }

    @Test("Crop reduces output dimensions")
    func cropReducesSize() async throws {
        var doc = AnnotationDocument(baseImage: solidImage(width: 100, height: 100, color: .green))
        doc.canvasCrop = CGRect(x: 0, y: 0, width: 25, height: 25)
        let url = tempURL(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.export(document: doc, format: .png, jpegQuality: 0.9, to: url)

        let data = try Data(contentsOf: url)
        let rep = NSBitmapImageRep(data: data)
        #expect(rep != nil)
        #expect((rep?.pixelsWide ?? 0) <= 50)   // significantly smaller than original 100
        #expect((rep?.pixelsHigh ?? 0) <= 50)
    }
}
