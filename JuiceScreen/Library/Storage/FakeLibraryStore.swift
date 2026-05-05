import Foundation

/// Test double for `LibraryStore`. Simple in-memory dict; not optimized.
public final class FakeLibraryStore: LibraryStore, @unchecked Sendable {

    private let lock = NSLock()
    private var rows: [UUID: CaptureRow] = [:]

    public init() {}

    public func insert(_ row: CaptureRow) async throws {
        lock.lock(); defer { lock.unlock() }
        rows[row.uuid] = row
    }

    public func fetch(id: UUID) async throws -> CaptureRow? {
        lock.lock(); defer { lock.unlock() }
        return rows[id]
    }

    public func list(filter: SmartFilter) async throws -> [CaptureRow] {
        lock.lock()
        let snapshot = Array(rows.values)
        lock.unlock()

        let now = Date()
        let cal = Calendar.current

        let filtered = snapshot.filter { row in
            let matchesTrash = filter.includesTrash ? row.isDeleted : !row.isDeleted
            guard matchesTrash else { return false }
            switch filter {
            case .all, .trash:
                return true
            case .today:
                return cal.isDateInToday(row.capturedAt)
            case .thisWeek:
                return cal.isDate(row.capturedAt, equalTo: now, toGranularity: .weekOfYear)
            case .thisMonth:
                return cal.isDate(row.capturedAt, equalTo: now, toGranularity: .month)
            case .videos:
                return row.mediaType == .video
            case .images:
                return row.mediaType == .image
            }
        }
        return filtered.sorted { $0.capturedAt > $1.capturedAt }
    }

    public func softDelete(id: UUID) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let existing = rows[id] else { throw LibraryStoreError.notFound }
        rows[id] = withDeletedAt(existing, date: Date())
    }

    public func restore(id: UUID) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let existing = rows[id] else { throw LibraryStoreError.notFound }
        rows[id] = withDeletedAt(existing, date: nil)
    }

    public func permanentlyDelete(id: UUID) async throws {
        lock.lock(); defer { lock.unlock() }
        rows.removeValue(forKey: id)
    }

    public func updateThumbnailPath(id: UUID, thumbnailPath: String) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let existing = rows[id] else { throw LibraryStoreError.notFound }
        rows[id] = withThumbnailPath(existing, path: thumbnailPath)
    }

    public func updateAnnotationPath(id: UUID, annotationPath: String?) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let existing = rows[id] else { throw LibraryStoreError.notFound }
        rows[id] = withAnnotationPath(existing, path: annotationPath)
    }

    // MARK: - Helpers

    private func withDeletedAt(_ row: CaptureRow, date: Date?) -> CaptureRow {
        CaptureRow(
            uuid: row.uuid, filePath: row.filePath, annotationPath: row.annotationPath,
            thumbnailPath: row.thumbnailPath, mediaType: row.mediaType, capturedAt: row.capturedAt,
            pixelWidth: row.pixelWidth, pixelHeight: row.pixelHeight, durationMs: row.durationMs,
            fileSizeBytes: row.fileSizeBytes, sourceApp: row.sourceApp, deletedAt: date
        )
    }

    private func withThumbnailPath(_ row: CaptureRow, path: String) -> CaptureRow {
        CaptureRow(
            uuid: row.uuid, filePath: row.filePath, annotationPath: row.annotationPath,
            thumbnailPath: path, mediaType: row.mediaType, capturedAt: row.capturedAt,
            pixelWidth: row.pixelWidth, pixelHeight: row.pixelHeight, durationMs: row.durationMs,
            fileSizeBytes: row.fileSizeBytes, sourceApp: row.sourceApp, deletedAt: row.deletedAt
        )
    }

    private func withAnnotationPath(_ row: CaptureRow, path: String?) -> CaptureRow {
        CaptureRow(
            uuid: row.uuid, filePath: row.filePath, annotationPath: path,
            thumbnailPath: row.thumbnailPath, mediaType: row.mediaType, capturedAt: row.capturedAt,
            pixelWidth: row.pixelWidth, pixelHeight: row.pixelHeight, durationMs: row.durationMs,
            fileSizeBytes: row.fileSizeBytes, sourceApp: row.sourceApp, deletedAt: row.deletedAt
        )
    }
}
