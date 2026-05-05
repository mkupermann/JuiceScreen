import CoreGraphics

@MainActor
public protocol ScrollCaptureService: AnyObject {
    typealias FrameHandler = @MainActor (CGImage) -> Void
    var isRunning: Bool { get }
    func start(region: CGRect, handler: @escaping FrameHandler) async throws
    func stop() async throws
}
