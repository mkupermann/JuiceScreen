import Foundation

public struct OCRResult: Equatable, Hashable, Sendable, Codable {
    public var regions: [OCRRegion]
    public var extractedAt: Date

    public init(regions: [OCRRegion], extractedAt: Date) {
        self.regions = regions
        self.extractedAt = extractedAt
    }

    public var fullText: String {
        regions.map { $0.text }.joined(separator: "\n")
    }
}
