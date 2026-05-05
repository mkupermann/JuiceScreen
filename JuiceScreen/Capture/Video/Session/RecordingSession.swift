import AppKit
import Foundation

@MainActor
public final class RecordingSession {

    private let recorder: VideoRecorder
    private let onStopComplete: (CaptureRecord) -> Void
    private var controlWindow: RecordingControlWindow?
    private var elapsedTimer: Timer?
    private var options: VideoRecordingOptions = .defaults
    private let log = AppLog.logger(category: "RecordingSession")

    public init(recorder: VideoRecorder, onStopComplete: @escaping (CaptureRecord) -> Void) {
        self.recorder = recorder
        self.onStopComplete = onStopComplete
    }

    public var isActive: Bool { recorder.isRecording }

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        self.options = options

        let micEnabled = options.captureMicrophone
        let onStopHandler: () -> Void = { [weak self] in
            Task { @MainActor [weak self] in try? await self?.stop() }
        }
        let onToggleMic: () -> Void = { [weak self] in
            self?.recorder.toggleMicrophoneMute()
        }

        let win = RecordingControlWindow(
            initialMicEnabled: micEnabled,
            onStop: onStopHandler,
            onToggleMic: onToggleMic
        )
        self.controlWindow = win
        win.show()

        try await recorder.start(mode: mode, options: options, outputURL: outputURL)

        // Tick UI every 200ms to update the elapsed counter
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.controlWindow?.update(
                    elapsed: self.recorder.elapsed,
                    micEnabled: self.options.captureMicrophone,
                    onStop: onStopHandler,
                    onToggleMic: onToggleMic
                )
            }
        }
    }

    public func stop() async throws {
        guard recorder.isRecording else { return }
        let record = try await recorder.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        controlWindow?.close()
        controlWindow = nil
        onStopComplete(record)
        log.info("Session ended → \(record.fileURL.path)")
    }
}
