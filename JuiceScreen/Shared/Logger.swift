import os

/// Factory for category-tagged loggers under the `com.bks-lab.juicescreen` subsystem.
///
/// Usage:
/// ```
/// private let log = AppLog.logger(category: "MenuBar")
/// log.info("status item created")
/// ```
public enum AppLog {
    public static let subsystem = "com.bks-lab.juicescreen"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
