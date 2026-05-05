import AVFoundation
import CoreMedia
import Foundation

/// Wraps `AVAssetWriter` for H.264 MP4 video + AAC audio output.
/// Created once per recording. Caller appends sample buffers via the typed methods,
/// then calls `finish()` to flush + close the file.
public final class VideoFileWriter: @unchecked Sendable {

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let videoAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let log = AppLog.logger(category: "VideoFileWriter")

    private var sessionStarted = false
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.video-writer")

    public init(outputURL: URL, frameSize: CGSize, includesAudio: Bool) throws {
        do {
            self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw VideoRecordingError.writerSetupFailed("\(error)")
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(frameSize.width),
            AVVideoHeightKey: Int(frameSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        self.videoInput.expectsMediaDataInRealTime = true

        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(frameSize.width),
            kCVPixelBufferHeightKey as String: Int(frameSize.height)
        ]
        self.videoAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: bufferAttrs
        )
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        if includesAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 192_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) { writer.add(audioInput) }
            self.audioInput = audioInput
        } else {
            self.audioInput = nil
        }

        guard writer.startWriting() else {
            throw VideoRecordingError.writerSetupFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    public func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        if !sessionStarted {
            writer.startSession(atSourceTime: presentationTime)
            sessionStarted = true
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        if !videoAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            log.error("Failed to append pixel buffer at \(presentationTime.seconds)")
        }
    }

    public func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted else { return }
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    public func finish() async throws -> CMTime {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            throw VideoRecordingError.writeFailed("\(error)")
        }
        // Final duration = last sample time minus session start; AVAssetWriter exposes via tracks
        return writer.movieFragmentInterval == .invalid ? .zero : writer.movieFragmentInterval
    }
}
