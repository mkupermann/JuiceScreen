import Foundation

public enum LibraryStoreError: Error, Equatable {
    case notFound
    case databaseError(String)
}

public protocol LibraryStore: Sendable {
    func insert(_ row: CaptureRow) async throws
    func fetch(id: UUID) async throws -> CaptureRow?
    func list(filter: SmartFilter) async throws -> [CaptureRow]
    func softDelete(id: UUID) async throws
    func restore(id: UUID) async throws
    func permanentlyDelete(id: UUID) async throws
    func updateThumbnailPath(id: UUID, thumbnailPath: String) async throws
    func updateAnnotationPath(id: UUID, annotationPath: String?) async throws
}
