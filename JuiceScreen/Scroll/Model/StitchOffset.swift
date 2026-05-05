public struct StitchOffset: Equatable, Sendable {
    public static let maxAcceptableSSD: Double = 500_000
    public let pixelsScrolled: Int
    public let ssdScore: Double
    public init(pixelsScrolled: Int, ssdScore: Double) {
        self.pixelsScrolled = pixelsScrolled
        self.ssdScore = ssdScore
    }
    public var isUsable: Bool { pixelsScrolled > 0 && ssdScore <= StitchOffset.maxAcceptableSSD }
}
