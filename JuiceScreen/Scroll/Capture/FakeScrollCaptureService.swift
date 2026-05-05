import CoreGraphics

@MainActor
public final class FakeScrollCaptureService: ScrollCaptureService {
    public var queuedFrames: [CGImage] = []
    public private(set) var isRunning: Bool = false
    private var handler: FrameHandler?

    public init() {}

    public func start(region: CGRect, handler: @escaping FrameHandler) async throws {
        self.handler = handler
        self.isRunning = true
    }

    public func stop() async throws {
        isRunning = false
        handler = nil
    }

    public func emitAllQueuedNow() async {
        guard let handler else { return }
        for frame in queuedFrames {
            handler(frame)
            await Task.yield()
        }
        queuedFrames.removeAll()
    }
}
