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

    public func emptyTrash() async throws -> Int {
        try await databaseQueue.write { db in
            // Fetch IDs first so we can also clean up FTS5/OCR side tables.
            let ids: [String] = try String.fetchAll(db, sql: """
                SELECT uuid FROM captures WHERE deleted_at IS NOT NULL
            """)
            for id in ids {
                try db.execute(sql: "DELETE FROM captures WHERE uuid = ?", arguments: [id])
                // Best-effort FTS5 cleanup; ignore errors since FTS rows may not exist.
                try? db.execute(sql: "INSERT INTO captures_fts(captures_fts, rowid, text) VALUES('delete', (SELECT rowid FROM captures_ocr_cache WHERE uuid = ?), '')", arguments: [id])
                try? db.execute(sql: "DELETE FROM captures_ocr_cache WHERE uuid = ?", arguments: [id])
            }
            return ids.count
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
            // Fetch the captures row's internal rowid so FTS rowid matches, enabling the JOIN.
            guard let capturesRowid = try Int64.fetchOne(db,
                sql: "SELECT rowid FROM captures WHERE uuid = ?",
                arguments: [id.uuidString]) else { return }

            // If an old entry exists, remove its tokens from the FTS index first.
            if let oldText = try String.fetchOne(db,
                sql: "SELECT ocr_text FROM captures_ocr_cache WHERE uuid = ?",
                arguments: [id.uuidString]) {
                try db.execute(sql: """
                    INSERT INTO captures_fts(captures_fts, rowid, uuid, ocr_text, source_app)
                    VALUES ('delete', ?, ?, ?, ?)
                """, arguments: [capturesRowid, id.uuidString, oldText, ""])
            }

            // Insert new FTS entry with the captures rowid so JOIN works.
            try db.execute(sql: """
                INSERT INTO captures_fts (rowid, uuid, ocr_text, source_app) VALUES (?, ?, ?, ?)
            """, arguments: [capturesRowid, id.uuidString, text, ""])

            // Update the cache with the new text.
            try db.execute(sql: """
                INSERT INTO captures_ocr_cache (uuid, ocr_text) VALUES (?, ?)
                ON CONFLICT(uuid) DO UPDATE SET ocr_text = excluded.ocr_text
            """, arguments: [id.uuidString, text])
        }
    }

    public func search(query: SearchQuery) async throws -> [CaptureRow] {
        try await databaseQueue.read { db in
            var conditions: [String] = ["captures.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []

            if let app = query.sourceApp {
                conditions.append("LOWER(captures.source_app) = LOWER(?)")
                args.append(app)
            }
            if let after = query.after {
                conditions.append("captures.captured_at >= ?")
                args.append(Int(after.timeIntervalSince1970))
            }
            if let before = query.before {
                conditions.append("captures.captured_at <= ?")
                args.append(Int(before.timeIntervalSince1970))
            }
            if let type = query.mediaType {
                conditions.append("captures.media_type = ?")
                args.append(type.rawValue)
            }

            let sql: String
            if query.text.isEmpty {
                sql = """
                    SELECT captures.*
                    FROM captures
                    WHERE \(conditions.joined(separator: " AND "))
                    ORDER BY captures.captured_at DESC
                """
            } else {
                conditions.append("captures_fts MATCH ?")
                args.append(Self.toFTS5MatchExpression(query.text))
                sql = """
                    SELECT captures.*
                    FROM captures
                    JOIN captures_fts ON captures_fts.rowid = captures.rowid
                    WHERE \(conditions.joined(separator: " AND "))
                    ORDER BY rank, captures.captured_at DESC
                """
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map(Self.makeRow(from:))
        }
    }

    public func captureIDsWithoutOCR() async throws -> [(id: UUID, filePath: String)] {
        try await databaseQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT captures.uuid, captures.file_path
                FROM captures
                LEFT JOIN captures_fts ON captures_fts.rowid = captures.rowid
                WHERE captures.deleted_at IS NULL
                  AND captures.media_type = 'image'
                  AND captures_fts.rowid IS NULL
                ORDER BY captures.captured_at DESC
            """)
            return rows.compactMap { row -> (UUID, String)? in
                guard let id = UUID(uuidString: row["uuid"]) else { return nil }
                return (id, row["file_path"])
            }
        }
    }

    private static func toFTS5MatchExpression(_ text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
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
