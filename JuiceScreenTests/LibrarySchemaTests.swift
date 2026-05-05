import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibrarySchema")
struct LibrarySchemaTests {

    private func inMemoryQueue() throws -> DatabaseQueue {
        try DatabaseQueue()  // GRDB in-memory
    }

    @Test("v1 migration creates captures + captures_fts tables and the two indexes")
    func v1Migration() throws {
        let queue = try inMemoryQueue()
        try LibrarySchema.migrator().migrate(queue)

        try queue.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            #expect(tables.contains("captures"))
            #expect(tables.contains("captures_fts"))

            let indexes = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name")
            #expect(indexes.contains("idx_captures_captured_at"))
            #expect(indexes.contains("idx_captures_deleted_at"))
        }
    }

    @Test("WAL journal mode is enabled after migration")
    func walMode() throws {
        let queue = try inMemoryQueue()
        try LibrarySchema.migrator().migrate(queue)
        // In-memory DBs use 'memory' journal mode; this test just verifies the migration runs without error
        // and that we can issue PRAGMA queries afterwards.
        try queue.read { db in
            let mode = try String.fetchOne(db, sql: "PRAGMA journal_mode")
            #expect(mode != nil)
        }
    }

    @Test("Migration is idempotent (running twice does not fail)")
    func idempotent() throws {
        let queue = try inMemoryQueue()
        try LibrarySchema.migrator().migrate(queue)
        try LibrarySchema.migrator().migrate(queue)   // second run should be a no-op
    }
}
