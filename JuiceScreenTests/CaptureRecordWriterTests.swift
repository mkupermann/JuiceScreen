import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureRecordWriter")
struct CaptureRecordWriterTests {

    /// Builds a deterministic-pixel-size NSImage by drawing into a 1× NSBitmapImageRep.
    /// Avoids `lockFocus` which produces 2× backing on Retina screens and would make
    /// pixel-dimension assertions display-dependent.
    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        color.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private func makeTempRoot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Writes a PNG file at the expected path and returns a CaptureRecord")
    func writesPNG() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = CaptureRecordWriter(
            saveDirectory: SaveDirectoryProvider(rootDirectory: root),
            filenameGenerator: FilenameGenerator()
        )
        let img = solidImage(width: 32, height: 16, color: .green)
        let date = Date()

        let record = try writer.write(image: img, captureType: .region, capturedAt: date, sourceApp: "TestApp")

        #expect(FileManager.default.fileExists(atPath: record.fileURL.path))
        #expect(record.fileURL.pathExtension == "png")
        #expect(record.captureType == .region)
        #expect(record.pixelWidth == 32)
        #expect(record.pixelHeight == 16)
        #expect(record.sourceApp == "TestApp")
        #expect(record.capturedAt == date)
    }

    @Test("Filename matches FilenameGenerator output for the captured-at date")
    func filenameMatches() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = CaptureRecordWriter(
            saveDirectory: SaveDirectoryProvider(rootDirectory: root),
            filenameGenerator: FilenameGenerator()
        )
        let img = solidImage(width: 4, height: 4, color: .red)
        let date = Date()
        let expectedName = FilenameGenerator().filename(for: date, extension: "png")

        let record = try writer.write(image: img, captureType: .fullScreen, capturedAt: date, sourceApp: nil)

        #expect(record.fileURL.lastPathComponent == expectedName)
    }

    @Test("Handles two captures within the same second by appending a uniqueness suffix")
    func collisionHandling() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = CaptureRecordWriter(
            saveDirectory: SaveDirectoryProvider(rootDirectory: root),
            filenameGenerator: FilenameGenerator()
        )
        let img = solidImage(width: 2, height: 2, color: .black)
        let date = Date()

        let r1 = try writer.write(image: img, captureType: .region, capturedAt: date, sourceApp: nil)
        let r2 = try writer.write(image: img, captureType: .region, capturedAt: date, sourceApp: nil)

        #expect(r1.fileURL != r2.fileURL)
        #expect(FileManager.default.fileExists(atPath: r1.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: r2.fileURL.path))
    }
}
