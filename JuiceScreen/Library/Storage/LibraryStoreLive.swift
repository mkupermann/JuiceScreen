import Foundation
import GRDB

public final class LibraryStoreLive: LibraryStore {

    private let databaseQueue: DatabaseQueue

    public init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    public func insert(_ row: CaptureRow) async throws {
        try await databaseQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO captures
                  (uuid, file_path, annotation_path, thumbnail_path, media_type,
                   captured_at, width, height, duration_ms, file_size_bytes, source_app, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    row.uuid.uuidString, row.filePath, row.annotationPath, row.thumbnailPath,
                    row.mediaType.rawValue, Int(row.capturedAt.timeIntervalSince1970),
                    row.pixelWidth, row.pixelHeight, row.durationMs, row.fileSizeBytes,
                    row.sourceApp, row.deletedAt.map { Int($0.timeIntervalSince1970) }
                ]
            )
        }
    }

    public func fetch(id: UUID) async throws -> CaptureRow? {
        try await databaseQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM captures WHERE uuid = ?",
                arguments: [id.uuidString])
            return rows.first.map(Self.makeRow(from:))
        }
    }

    public func list(filter: SmartFilter) async throws -> [CaptureRow] {
        try await databaseQueue.read { db in
            let (whereClause, arguments) = Self.whereClauseAndArguments(for: filter)
            let sql = """
                SELECT * FROM captures
                \(whereClause)
                ORDER BY captured_at DESC
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.map(Self.makeRow(from:))
        }
    }

    public func softDelete(id: UUID) async throws {
        try await databaseQueue.write { db in
            try db.execute(
                sql: "UPDATE captures SET deleted_at = ? WHERE uuid = ?",
                arguments: [Int(Date().timeIntervalSince1970), id.uuidString]
            )
        }
    }

    public func restore(id: UUID) async throws {
        try await databaseQueue.write { db in
            try db.execute(
                sql: "UPDATE captures SET deleted_at = NULL WHERE uuid = ?",
                arguments: [id.uuidString]
            )
        }
    }

    public func permanentlyDelete(id: UUID) async throws {
        try await databaseQueue.write { db in
            try db.execute(
                sql: "DELETE FROM captures WHERE uuid = ?",
                arguments: [id.uuidString]
            )
        }
    }

    public func updateThumbnailPath(id: UUID, thumbnailPath: String) async throws {
        try await databaseQueue.write { db in
            try db.execute(
                sql: "UPDATE captures SET thumbnail_path = ? WHERE uuid = ?",
                arguments: [thumbnailPath, id.uuidString]
            )
        }
    }

    public func updateAnnotationPath(id: UUID, annotationPath: String?) async throws {
        try await databaseQueue.write { db in
            try db.execute(
                sql: "UPDATE captures SET annotation_path = ? WHERE uuid = ?",
                arguments: [annotationPath, id.uuidString]
            )
        }
    }

    public func upsertOCRText(id: UUID, text: String) async throws {
        try await databaseQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO captures_fts(uuid, ocr_text) VALUES (?, ?)
                ON CONFLICT(uuid) DO UPDATE SET ocr_text = excluded.ocr_text
                """,
                arguments: [id.uuidString, text]
            )
        }
    }

    public func search(query: SearchQuery) async throws -> [CaptureRow] {
        try await databaseQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM captures WHERE deleted_at IS NULL ORDER BY captured_at DESC")
            return rows.map(Self.makeRow(from:))
        }
    }

    // MARK: - Mapping

    private static func makeRow(from row: Row) -> CaptureRow {
        let uuid = UUID(uuidString: row["uuid"]) ?? UUID()
        let mediaType = MediaType(rawValue: row["media_type"]) ?? .image
        let deletedAtSeconds: Int? = row["deleted_at"]
        return CaptureRow(
            uuid: uuid,
            filePath: row["file_path"],
            annotationPath: row["annotation_path"],
            thumbnailPath: row["thumbnail_path"],
            mediaType: mediaType,
            capturedAt: Date(timeIntervalSince1970: TimeInterval(row["captured_at"] as Int)),
            pixelWidth: row["width"],
            pixelHeight: row["height"],
            durationMs: row["duration_ms"],
            fileSizeBytes: row["file_size_bytes"],
            sourceApp: row["source_app"],
            deletedAt: deletedAtSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func whereClauseAndArguments(for filter: SmartFilter) -> (String, StatementArguments) {
        let cal = Calendar.current
        let now = Date()
        switch filter {
        case .all:
            return ("WHERE deleted_at IS NULL", [])
        case .trash:
            return ("WHERE deleted_at IS NOT NULL", [])
        case .images:
            return ("WHERE deleted_at IS NULL AND media_type = ?", ["image"])
        case .videos:
            return ("WHERE deleted_at IS NULL AND media_type = ?", ["video"])
        case .today:
            let startOfDay = cal.startOfDay(for: now)
            return ("WHERE deleted_at IS NULL AND captured_at >= ?",
                    [Int(startOfDay.timeIntervalSince1970)])
        case .thisWeek:
            let week = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return ("WHERE deleted_at IS NULL AND captured_at >= ?",
                    [Int(week.timeIntervalSince1970)])
        case .thisMonth:
            let month = cal.dateInterval(of: .month, for: now)?.start ?? now
            return ("WHERE deleted_at IS NULL AND captured_at >= ?",
                    [Int(month.timeIntervalSince1970)])
        }
    }
}
