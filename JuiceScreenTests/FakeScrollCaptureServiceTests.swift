import Testing
import CoreGraphics
@testable import JuiceScreen

@MainActor
struct FakeScrollCaptureServiceTests {

    @Test("emitsFrames: queued frames are delivered after emitAllQueuedNow")
    func emitsFrames() async throws {
        let sut = FakeScrollCaptureService()
        let frame1 = makeCGImage()
        let frame2 = makeCGImage()
        sut.queuedFrames = [frame1, frame2]

        var received: [CGImage] = []
        try await sut.start(region: .zero) { image in
            received.append(image)
        }
        await sut.emitAllQueuedNow()
        try await sut.stop()

        #expect(received.count == 2)
    }

    @Test("stopWithoutFrames: isRunning is false after stop")
    func stopWithoutFrames() async throws {
        let sut = FakeScrollCaptureService()
        try await sut.start(region: .zero) { _ in }
        try await sut.stop()
        #expect(sut.isRunning == false)
    }

    // MARK: - Helpers

    private func makeCGImage() -> CGImage {
        let width = 1
        let height = 1
        let bitsPerComponent = 8
        let bytesPerRow = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        var pixels: [UInt8] = [0, 0, 0, 255]
        let data = CFDataCreate(nil, &pixels, pixels.count)!
        let provider = CGDataProvider(data: data)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
