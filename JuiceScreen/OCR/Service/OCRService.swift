import Foundation

public enum OCRError: Error, Equatable {
    case imageLoadFailed
    case recognitionFailed(String)
}

public protocol OCRService: Sendable {
    func recognize(imageAt url: URL) async throws -> OCRResult
}
