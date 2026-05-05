import AppKit
import Foundation
import Vision

/// Production OCR service backed by Vision's `VNRecognizeTextRequest`.
/// Runs on a private dispatch queue at `.utility` QoS so capture/UI is never blocked.
public final class OCRServiceLive: OCRService {

    private let log = AppLog.logger(category: "OCRServiceLive")
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.ocr", qos: .utility)
    private let recognitionLanguages: [String]

    public init(recognitionLanguages: [String] = ["en-US", "de-DE"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    public func recognize(imageAt url: URL) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<OCRResult, Error>) in
            queue.async {
                do {
                    let result = try Self.runVision(at: url, languages: self.recognitionLanguages)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Vision plumbing

    /// Synchronous Vision execution. Called on the OCR queue.
    private static func runVision(at url: URL, languages: [String]) throws -> OCRResult {
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageLoadFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        if #available(macOS 14, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed("\(error)")
        }

        let observations = (request.results ?? [])
        let imgWidth = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)

        var regions: [OCRRegion] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            // Vision boundingBox is normalized (0–1) with origin BOTTOM-LEFT.
            // Convert to top-left convention (matches CGImage / our InspectorView).
            let bb = obs.boundingBox
            let topLeftBox = CGRect(
                x: bb.minX,
                y: 1.0 - bb.maxY,
                width: bb.width,
                height: bb.height
            )
            regions.append(OCRRegion(text: candidate.string, boundingBox: topLeftBox))

            // The pixel-space rect would be:
            //   CGRect(x: bb.minX*imgWidth, y: (1-bb.maxY)*imgHeight, ...)
            // We keep normalized so the InspectorView scales correctly with thumbnails.
            _ = imgWidth; _ = imgHeight
        }

        return OCRResult(regions: regions, extractedAt: Date())
    }
}
