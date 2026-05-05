import Foundation
import GRDB

/// Versioned schema migrations for the JuiceScreen library database.
///
/// v1: Creates the `captures` table, the `captures_fts` FTS5 virtual table
/// (populated only by Plan 5's OCR pipeline — no rows are written to it in Plan 4),
/// and two indexes for common query paths.
public enum LibrarySchema {

    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE captures (
                    uuid TEXT PRIMARY KEY,
                    file_path TEXT NOT NULL,
                    annotation_path TEXT,
                    thumbnail_path TEXT NOT NULL,
                    media_type TEXT NOT NULL,
                    captured_at INTEGER NOT NULL,
                    width INTEGER NOT NULL,
                    height INTEGER NOT NULL,
                    duration_ms INTEGER,
                    file_size_bytes INTEGER NOT NULL,
                    source_app TEXT,
                    deleted_at INTEGER
                )
            """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE captures_fts USING fts5(
                    uuid UNINDEXED,
                    ocr_text,
                    source_app,
                    content='',
                    tokenize='porter unicode61'
                )
            """)

            try db.execute(sql: """
                CREATE INDEX idx_captures_captured_at
                    ON captures(captured_at DESC)
            """)

            try db.execute(sql: """
                CREATE INDEX idx_captures_deleted_at
                    ON captures(deleted_at) WHERE deleted_at IS NULL
            """)
        }

        return migrator
    }
}
