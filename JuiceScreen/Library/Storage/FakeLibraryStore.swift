import Foundation

/// Test double for `LibraryStore`. Simple in-memory dict; not optimized.
public final class FakeLibraryStore: LibraryStore, @unchecked Sendable {

    private let lock = NSLock()
    private var rows: [UUID: CaptureRow] = [:]
    private var ocrText: [UUID: String] = [:]

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

    public func upsertOCRText(id: UUID, text: String) async throws {
        lock.lock(); defer { lock.unlock() }
        ocrText[id] = text
    }

    public func captureIDsWithoutOCR() async throws -> [(id: UUID, filePath: String)] {
        lock.lock(); defer { lock.unlock() }
        return rows.values
            .filter { !$0.isDeleted && $0.mediaType == .image && ocrText[$0.uuid] == nil }
            .sorted { $0.capturedAt > $1.capturedAt }
            .map { ($0.uuid, $0.filePath) }
    }

    public func search(query: SearchQuery) async throws -> [CaptureRow] {
        lock.lock()
        let snapshot = Array(rows.values)
        let textIndex = ocrText
        lock.unlock()

        return snapshot.filter { row in
            guard !row.isDeleted else { return false }
            if let app = query.sourceApp, row.sourceApp?.lowercased() != app.lowercased() { return false }
            if let after = query.after, row.capturedAt < after { return false }
            if let before = query.before, row.capturedAt > before { return false }
            if let type = query.mediaType, row.mediaType != type { return false }
            if !query.text.isEmpty {
                let haystack = (textIndex[row.uuid] ?? "").lowercased()
                let needle = query.text.lowercased()
                if !haystack.contains(needle) { return false }
            }
            return true
        }
        .sorted { $0.capturedAt > $1.capturedAt }
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
