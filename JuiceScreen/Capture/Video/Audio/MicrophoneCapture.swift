import AVFoundation
import Foundation

/// Captures microphone audio via `AVCaptureSession` and forwards CMSampleBuffers
/// to a delegate. Started/stopped by the recorder when `captureMicrophone` is enabled.
public final class MicrophoneCapture: NSObject, @unchecked Sendable {

    public typealias SampleHandler = (CMSampleBuffer) -> Void

    private let session: AVCaptureSession
    private let output: AVCaptureAudioDataOutput
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.mic")
    private var handler: SampleHandler?
    private let log = AppLog.logger(category: "MicrophoneCapture")

    public override init() {
        self.session = AVCaptureSession()
        self.output = AVCaptureAudioDataOutput()
        super.init()
    }

    public func start(handler: @escaping SampleHandler) throws {
        self.handler = handler

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw VideoRecordingError.streamConfigurationFailed("No default audio input device")
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw VideoRecordingError.streamConfigurationFailed("\(error)")
        }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() {
        session.stopRunning()
        handler = nil
    }
}

extension MicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        handler?(sampleBuffer)
    }
}
