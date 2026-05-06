import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibrarySchema v2")
struct LibrarySchemaV2Tests {

    private func makeMemoryQueue() throws -> DatabaseQueue {
        try DatabaseQueue()
    }

    @Test("v2 migration creates captures_ocr_cache table with uuid PK + ocr_text column")
    func v2CreatesCacheTable() throws {
        let q = try makeMemoryQueue()
        try LibrarySchema.migrator().migrate(q)

        try q.read { db in
            // Table exists
            let exists = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type='table' AND name='captures_ocr_cache'
            """) ?? 0
            #expect(exists == 1)

            // Schema columns: uuid TEXT PRIMARY KEY, ocr_text TEXT NOT NULL
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(captures_ocr_cache)")
            #expect(cols.count == 2)
            let names: [String] = cols.compactMap { $0["name"] }
            #expect(names.sorted() == ["ocr_text", "uuid"])
        }
    }

    @Test("Migrator is idempotent — running twice does not error")
    func idempotent() throws {
        let q = try makeMemoryQueue()
        try LibrarySchema.migrator().migrate(q)
        try LibrarySchema.migrator().migrate(q)
        // No throw = pass.
    }

    @Test("Both migrations are applied in order")
    func bothMigrationsApplied() throws {
        let q = try makeMemoryQueue()
        try LibrarySchema.migrator().migrate(q)
        try q.read { db in
            let captures = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='captures'
            """) ?? 0
            let cache = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='captures_ocr_cache'
            """) ?? 0
            #expect(captures == 1)
            #expect(cache == 1)
        }
    }
}
