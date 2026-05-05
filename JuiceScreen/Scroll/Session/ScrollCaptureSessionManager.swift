import Foundation

@MainActor
public final class ScrollCaptureSessionManager {

    private let serviceFactory: () -> ScrollCaptureService
    private let saveDirectory: SaveDirectoryProvider
    private let onComplete: (CaptureRecord) -> Void
    private let onError: (ScrollCaptureError) -> Void
    private var session: ScrollCaptureSession?

    public init(
        serviceFactory: @escaping () -> ScrollCaptureService,
        saveDirectory: SaveDirectoryProvider,
        onComplete: @escaping (CaptureRecord) -> Void,
        onError: @escaping (ScrollCaptureError) -> Void
    ) {
        self.serviceFactory = serviceFactory
        self.saveDirectory = saveDirectory
        self.onComplete = onComplete
        self.onError = onError
    }

    public var isActive: Bool { session != nil }

    public func begin() {
        if isActive { return }
        let session = ScrollCaptureSession(
            service: serviceFactory(),
            saveDirectory: saveDirectory,
            onComplete: { [weak self] record in
                self?.session = nil
                self?.onComplete(record)
            },
            onError: { [weak self] error in
                self?.session = nil
                self?.onError(error)
            }
        )
        self.session = session
        session.begin()
    }
}
