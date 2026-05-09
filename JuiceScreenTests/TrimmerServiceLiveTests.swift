import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import JuiceScreen

/// Exercises the real `TrimmerServiceLive` against AVFoundation. The happy-path
/// test synthesises a tiny single-frame mp4 via `AVAssetWriter` so we don't ship
/// any binary fixtures with the repo.
@Suite("TrimmerServiceLive")
struct TrimmerServiceLiveTests {

    // MARK: - Helpers

    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    private func tmpURL(suffix: String = "mp4") -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jc-trim-\(UUID().uuidString).\(suffix)")
    }

    /// Writes a short mp4 with two frames (so the asset has measurable duration)
    /// to `url`. The video is 64x64 BGRA encoded as h264.
    private static func makeTinyMP4(at url: URL, durationSec: Double = 1.0) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let pixelBuffer = pb else {
            throw NSError(domain: "TrimmerServiceLiveTests", code: -1)
        }

        let frameDuration = CMTime(seconds: durationSec, preferredTimescale: 600)
        adaptor.append(pixelBuffer, withPresentationTime: .zero)
        adaptor.append(pixelBuffer, withPresentationTime: frameDuration)

        input.markAsFinished()
        await writer.finishWriting()
    }

    // MARK: - Tests

    @Test("invalidRange: throws when start >= end")
    func throwsOnInvalidRange() async {
        let svc = TrimmerServiceLive()
        let source = URL(fileURLWithPath: "/tmp/whatever.mp4")
        let dest = tmpURL()
        // start == end → durationSeconds == 0 → isValid == false
        let range = TrimRange(start: t(1.0), end: t(1.0))
        do {
            _ = try await svc.trim(sourceURL: source, range: range, destinationURL: dest)
            Issue.record("Expected throw")
        } catch let error as TrimmerError {
            #expect(error == .invalidRange)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("invalidRange: throws when start > end")
    func throwsOnReversedRange() async {
        let svc = TrimmerServiceLive()
        let range = TrimRange(start: t(5.0), end: t(2.0))
        do {
            _ = try await svc.trim(
                sourceURL: URL(fileURLWithPath: "/tmp/whatever.mp4"),
                range: range,
                destinationURL: tmpURL()
            )
            Issue.record("Expected throw")
        } catch let error as TrimmerError {
            #expect(error == .invalidRange)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("invalidRange: throws when range duration is below minimum")
    func throwsOnSubMinimumRange() async {
        let svc = TrimmerServiceLive()
        // 0.05s is below TrimRange.minimumDurationSeconds (0.1)
        let range = TrimRange(start: t(0.0), end: t(0.05))
        do {
            _ = try await svc.trim(
                sourceURL: URL(fileURLWithPath: "/tmp/whatever.mp4"),
                range: range,
                destinationURL: tmpURL()
            )
            Issue.record("Expected throw")
        } catch let error as TrimmerError {
            #expect(error == .invalidRange)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("sourceUnreadable: throws when source file does not exist")
    func throwsOnMissingSource() async {
        let svc = TrimmerServiceLive()
        let missing = URL(fileURLWithPath: "/tmp/jc-no-such-file-\(UUID().uuidString).mp4")
        let dest = tmpURL()
        let range = TrimRange(start: t(0.0), end: t(0.5))
        do {
            _ = try await svc.trim(sourceURL: missing, range: range, destinationURL: dest)
            Issue.record("Expected throw")
        } catch let error as TrimmerError {
            #expect(error == .sourceUnreadable)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("happy path: produces a non-empty file at the destination")
    func happyPath() async throws {
        let source = tmpURL()
        let dest = tmpURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        try await Self.makeTinyMP4(at: source, durationSec: 1.0)
        #expect(FileManager.default.fileExists(atPath: source.path))

        let svc = TrimmerServiceLive()
        // Trim a sub-range well inside the synthetic asset duration.
        let range = TrimRange(start: t(0.0), end: t(0.5))
        let result = try await svc.trim(sourceURL: source, range: range, destinationURL: dest)

        #expect(result == dest)
        #expect(FileManager.default.fileExists(atPath: dest.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        #expect(size > 0)
    }

    @Test("destination overwrite: pre-existing file at destination is replaced")
    func overwritesExistingDestination() async throws {
        let source = tmpURL()
        let dest = tmpURL()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: dest)
        }

        try await Self.makeTinyMP4(at: source, durationSec: 1.0)

        // Plant a placeholder at the destination so the live service has to
        // remove it before exporting.
        let placeholder = Data("sentinel".utf8)
        try placeholder.write(to: dest)
        #expect(FileManager.default.fileExists(atPath: dest.path))

        let svc = TrimmerServiceLive()
        let range = TrimRange(start: t(0.0), end: t(0.5))
        let result = try await svc.trim(sourceURL: source, range: range, destinationURL: dest)

        #expect(result == dest)
        #expect(FileManager.default.fileExists(atPath: dest.path))

        // After overwrite, the file should no longer be the 8-byte sentinel.
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        #expect(size > placeholder.count)
    }
}
