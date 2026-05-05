import Foundation

/// Generates filenames in the canonical JuiceScreen format:
/// `JuiceScreen_YYYY-MM-DD_at_HH.MM.SS.<ext>`. All values zero-padded.
/// Calendar is injected so tests can be timezone-deterministic; production
/// uses the user's local calendar.
public struct FilenameGenerator: Sendable {

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func filename(for date: Date, extension ext: String) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "JuiceScreen_%04d-%02d-%02d_at_%02d.%02d.%02d.%@",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0,
            ext
        )
    }

    public func dateSubfolderName(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
