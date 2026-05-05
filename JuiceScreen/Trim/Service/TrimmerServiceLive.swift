import AVFoundation
import Foundation

public final class TrimmerServiceLive: TrimmerService {

    private let log = AppLog.logger(category: "TrimmerServiceLive")

    public init() {}

    public func trim(sourceURL: URL, range: TrimRange, destinationURL: URL) async throws -> URL {
        guard range.isValid else {
            throw TrimmerError.invalidRange
        }
        let asset = AVURLAsset(url: sourceURL)

        // Validate readability
        do {
            _ = try await asset.load(.duration)
        } catch {
            throw TrimmerError.sourceUnreadable
        }

        // Remove any existing file at destination
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            do {
                try FileManager.default.removeItem(at: destinationURL)
            } catch {
                throw TrimmerError.destinationUnwritable("\(error)")
            }
        }

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimmerError.exportFailed("Could not create export session")
        }

        session.outputURL = destinationURL
        session.outputFileType = .mp4
        session.timeRange = range.asCMTimeRange
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        switch session.status {
        case .completed:
            log.info("Trim complete → \(destinationURL.path)")
            return destinationURL
        case .cancelled:
            throw TrimmerError.userCancelled
        case .failed:
            let message = session.error?.localizedDescription ?? "unknown"
            throw TrimmerError.exportFailed(message)
        default:
            throw TrimmerError.exportFailed("Unexpected status: \(String(describing: session.status))")
        }
    }
}
