import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("ThumbnailStore")
struct ThumbnailStoreTests {

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    private func solidImage(_ size: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }

    @Test("write(image:for:) persists JPG at <thumbnails>/<uuid>.jpg and returns the path")
    func writeAndExists() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        let id = UUID()
        let img = solidImage(64)

        let path = try store.write(image: img, for: id)
        #expect(FileManager.default.fileExists(atPath: path))
        let url = URL(fileURLWithPath: path)
        #expect(url.lastPathComponent == "\(id.uuidString).jpg")
    }

    @Test("Overwrite is allowed (subsequent write replaces previous file)")
    func overwrite() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        let id = UUID()
        _ = try store.write(image: solidImage(32), for: id)
        _ = try store.write(image: solidImage(64), for: id)
        // Both calls succeed without throwing
    }

    @Test("delete(for:) removes the thumbnail file")
    func deleteThumb() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        let id = UUID()
        let path = try store.write(image: solidImage(16), for: id)
        try store.delete(for: id)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("delete(for:) is a no-op if the file doesn't exist")
    func deleteMissing() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        try store.delete(for: UUID())   // does not throw
    }
}
