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

        // Start the recorder FIRST. If it throws, no zombie control bar is left
        // hovering over the screen with a broken stop button.
        try await recorder.start(mode: mode, options: options, outputURL: outputURL)

        // Recorder is live — show the floating control bar.
        let win = RecordingControlWindow(
            initialMicEnabled: micEnabled,
            onStop: onStopHandler,
            onToggleMic: onToggleMic
        )
        self.controlWindow = win
        win.show()

        // Tick UI every 200ms to update the elapsed counter.
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
        // Always tear down the UI/timer/state, even if the recorder throws — a
        // zombie control bar with an unstoppable recording is worse than a
        // partially-saved MP4.
        defer {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            controlWindow?.close()
            controlWindow = nil
        }

        guard recorder.isRecording else {
            log.info("stop() called but recorder.isRecording = false; cleaning up UI only")
            return
        }

        do {
            let record = try await recorder.stop()
            onStopComplete(record)
            log.info("Session ended → \(record.fileURL.path)")
        } catch {
            log.error("recorder.stop failed: \(String(describing: error))")
            throw error
        }
    }
}
