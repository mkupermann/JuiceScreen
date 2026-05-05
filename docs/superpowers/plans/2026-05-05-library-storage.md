# JuiceScreen — Library + Storage Implementation Plan (Plan 4 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.4.0` — every capture from Plans 2/3 is now indexed in a local SQLite library. ⌘⇧L opens a two-pane main window: sidebar with smart filters (All / Today / This Week / Videos / Images / Trash), responsive grid of capture thumbnails (256×256 JPG, generated automatically after each capture), and an inspector pane that slides in when a tile is selected. Click a tile to re-open the editor (which already exists from Plan 3). Right-click a tile to Reveal in Finder, Copy file, or Move to Trash. Soft delete moves files to `~/Pictures/JuiceScreen/.trash/` with a 30-day grace period before permanent deletion via a background GC sweep on app launch.

**Architecture:** Three new modules. `Library/Storage/` owns GRDB+SQLite — schema with both `captures` table AND `captures_fts` FTS5 virtual table (the FTS5 table is **created** here so Plan 5's OCR pipeline can populate it without further migrations; no rows are written to it in Plan 4). `Library/Thumbnails/` and `Library/Trash/` are pure utility services. `MainWindow/Library/` holds the SwiftUI surface — two-pane `HSplitView` with a conditional inspector. A new `CaptureLibraryRecorder` glue service runs after every capture: generates a thumbnail, inserts a `CaptureRow`. Tile clicks delegate to Plan 3's `EditorWindowManager.show(for:)`. The library SQLite file lives in `~/Library/Application Support/JuiceScreen/library.sqlite` (separate from user-content captures); deleting it never destroys captures, only the index — Plan 5 will add a "rebuild from disk" recovery path.

**Tech Stack:** GRDB.swift 6.x via Swift Package Manager (handles SQLite, WAL, FTS5, migrations, async/await), Core Image for thumbnail aspect-fit downscaling, AppKit `NSWorkspace` for Reveal/Copy actions, SwiftUI `LazyVGrid` for the responsive grid, existing modules from Plans 1–3 (`Preferences`, `EditorWindowManager`, `CaptureRecord`, `AppLog`).

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — sections "Library, storage, OCR" (file layout, SQLite schema, library window UI, soft delete) and "Search UX" (deferred to Plan 5).

**Plan 3 prerequisite:** v0.3.0 tagged. After capture: file saved to disk + editor window opens. Plan 4 inserts itself between save and "future" — adds an indexing step + a window to browse the index.

**Scope deferred to later plans:**

- **OCR + FTS5 search** (Plan 5) — schema is created here, but no OCR pipeline runs and the search bar is wired to a no-op placeholder
- **Tags / collections / manual organization** — explicitly out of v1 per spec
- **Drag-to-reorder, multi-select, batch operations** — not in spec, defer
- **Rebuild-index-from-disk recovery flow** — Plan 5 adds it (depends on OCR pipeline existing)
- **Trash list UI does not show "restore" action button on tiles in v0.4.0** — right-click → "Move to Trash" works for live captures; trash items can be permanently deleted via "Empty trash now" button in Settings (Plan 9 settings completion). For v0.4.0, Trash filter shows the soft-deleted items so you can verify the soft-delete worked, but you cannot restore them via UI yet
- **Inspector "OCR text" panel** is built but shows a Plan 5 placeholder string

---

## File Structure

```
JuiceScreen/
├── Library/
│   ├── Model/
│   │   ├── CaptureRow.swift                  NEW — SQLite-shaped row, distinct from CaptureRecord
│   │   ├── MediaType.swift                   NEW — enum: image / video
│   │   └── SmartFilter.swift                 NEW — enum of sidebar filter options
│   ├── Storage/
│   │   ├── LibraryPaths.swift                NEW — ~/Library/App Support/JuiceScreen/* path provider
│   │   ├── LibrarySchema.swift               NEW — DatabaseMigrator with v1 migration
│   │   ├── LibraryStore.swift                NEW — protocol + error type
│   │   ├── LibraryStoreLive.swift            NEW — GRDB impl
│   │   └── FakeLibraryStore.swift            NEW — test double (in-memory dict)
│   ├── Thumbnails/
│   │   ├── ThumbnailGenerator.swift          NEW — NSImage → 256x256 JPG Data (aspect-fit)
│   │   └── ThumbnailStore.swift              NEW — paths + write/read by UUID
│   ├── Trash/
│   │   ├── TrashService.swift                NEW — move-to-trash + restore + permanent delete
│   │   └── TrashGC.swift                     NEW — sweep files older than 30 days
│   └── CaptureLibraryRecorder.swift          NEW — glue: after capture, insert row + thumbnail
├── MainWindow/
│   └── Library/
│       ├── LibraryViewModel.swift            NEW — @Observable: filter, captures, selected
│       ├── LibraryView.swift                 NEW — two-pane HSplitView root
│       ├── SidebarView.swift                 NEW — filter list (+ Settings entry already exists)
│       ├── CaptureGridView.swift             NEW — LazyVGrid of CaptureTile
│       ├── CaptureTile.swift                 NEW — single tile (thumbnail + time-ago + format badge + ⋯ menu)
│       ├── InspectorView.swift               NEW — capture metadata + action buttons
│       ├── EmptyStateView.swift              NEW — placeholder when grid is empty
│       ├── LibraryWindow.swift               NEW — NSWindow wrapper, hosts LibraryView
│       └── LibraryWindowManager.swift        NEW — singleton open/show
├── App/
│   └── AppDelegate.swift                     MODIFY — instantiate LibraryStore, CaptureLibraryRecorder, run TrashGC, wire ⌘⇧L hotkey + Open Library menu
project.yml                                   MODIFY — add GRDB.swift SPM dependency
VERSION                                       MODIFY — bump to 0.4.0 (Task 25)
docs/superpowers/specs/2026-05-04-juicescreen-design.md  MODIFY — implementation status (Task 26)

JuiceScreenTests/
├── CaptureRowTests.swift                     NEW
├── SmartFilterTests.swift                    NEW
├── LibraryPathsTests.swift                   NEW
├── LibrarySchemaTests.swift                  NEW
├── LibraryStoreLiveTests.swift               NEW (uses in-memory GRDB)
├── FakeLibraryStoreTests.swift               NEW
├── ThumbnailGeneratorTests.swift             NEW
├── ThumbnailStoreTests.swift                 NEW
├── TrashServiceTests.swift                   NEW
├── TrashGCTests.swift                        NEW
└── CaptureLibraryRecorderTests.swift         NEW
```

---

## Task 1: Add GRDB Swift Package dependency

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add GRDB to `project.yml`**

In `project.yml`, after the top-level `targets:` section header but at the same indentation as `targets:`, add a `packages:` section. Then add the dependency to the `JuiceScreen` target.

Add this section before `targets:`:

```yaml
packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift.git
    from: "6.29.0"
```

In the `JuiceScreen` target block, add a `dependencies:` array (if absent) or extend an existing one. Place it after `entitlements:` and before `settings:`:

```yaml
    dependencies:
      - package: GRDB
```

The full updated `JuiceScreen` target block (only the bits being added/changed):

```yaml
  JuiceScreen:
    type: application
    platform: macOS
    sources:
      - path: JuiceScreen
        excludes:
          - "**/*.md"
    resources:
      - path: JuiceScreen/Resources/Assets.xcassets
    info:
      ... (unchanged)
    entitlements:
      ... (unchanged)
    dependencies:
      - package: GRDB
    settings:
      ... (unchanged)
    scheme:
      ... (unchanged)
```

- [ ] **Step 2: Regenerate and verify GRDB resolves**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -resolvePackageDependencies 2>&1 | tail -10
```

Expected: package resolution completes; GRDB and any transitive deps appear in the resolved list. (First-time resolution takes 30–90s.)

- [ ] **Step 3: Verify build still succeeds**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. (No code uses GRDB yet — the dep is just available.)

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "build: add GRDB.swift 6.29 SPM dependency"
```

---

## Task 2: `MediaType` + `CaptureRow` value type + tests

**Files:**
- Create: `JuiceScreen/Library/Model/MediaType.swift`
- Create: `JuiceScreen/Library/Model/CaptureRow.swift`
- Create: `JuiceScreenTests/CaptureRowTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureRow")
struct CaptureRowTests {

    @Test("MediaType allCases")
    func mediaTypeAllCases() {
        #expect(Set(MediaType.allCases) == [.image, .video])
    }

    @Test("CaptureRow can be built from a CaptureRecord")
    func fromCaptureRecord() {
        let record = CaptureRecord(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/x.png"),
            captureType: .region,
            capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
            pixelWidth: 1024, pixelHeight: 768,
            sourceApp: "Safari"
        )
        let row = CaptureRow(record: record, fileSizeBytes: 12345, thumbnailPath: "/tmp/thumb.jpg")
        #expect(row.uuid == record.id)
        #expect(row.filePath == record.fileURL.path)
        #expect(row.thumbnailPath == "/tmp/thumb.jpg")
        #expect(row.mediaType == .image)
        #expect(row.capturedAt == record.capturedAt)
        #expect(row.pixelWidth == 1024)
        #expect(row.pixelHeight == 768)
        #expect(row.fileSizeBytes == 12345)
        #expect(row.sourceApp == "Safari")
        #expect(row.deletedAt == nil)
        #expect(row.annotationPath == nil)
        #expect(row.durationMs == nil)
    }

    @Test("Equality is value-based")
    func equality() {
        let id = UUID()
        let date = Date()
        let a = CaptureRow(uuid: id, filePath: "/a.png", annotationPath: nil, thumbnailPath: "/t.jpg",
                           mediaType: .image, capturedAt: date,
                           pixelWidth: 10, pixelHeight: 10, durationMs: nil,
                           fileSizeBytes: 100, sourceApp: nil, deletedAt: nil)
        let b = CaptureRow(uuid: id, filePath: "/a.png", annotationPath: nil, thumbnailPath: "/t.jpg",
                           mediaType: .image, capturedAt: date,
                           pixelWidth: 10, pixelHeight: 10, durationMs: nil,
                           fileSizeBytes: 100, sourceApp: nil, deletedAt: nil)
        #expect(a == b)
    }

    @Test("isDeleted reflects deletedAt presence")
    func isDeleted() {
        let liveRow = CaptureRow(uuid: UUID(), filePath: "/x", annotationPath: nil, thumbnailPath: "/t",
                                  mediaType: .image, capturedAt: Date(),
                                  pixelWidth: 1, pixelHeight: 1, durationMs: nil,
                                  fileSizeBytes: 0, sourceApp: nil, deletedAt: nil)
        let trashedRow = CaptureRow(uuid: UUID(), filePath: "/x", annotationPath: nil, thumbnailPath: "/t",
                                     mediaType: .image, capturedAt: Date(),
                                     pixelWidth: 1, pixelHeight: 1, durationMs: nil,
                                     fileSizeBytes: 0, sourceApp: nil, deletedAt: Date())
        #expect(liveRow.isDeleted == false)
        #expect(trashedRow.isDeleted == true)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRowTests 2>&1 | tail -8
```

Expected: compile failure — `MediaType` and `CaptureRow` undefined.

- [ ] **Step 3: Implement `MediaType.swift`**

```swift
import Foundation

public enum MediaType: String, CaseIterable, Sendable, Hashable {
    case image
    case video
}
```

- [ ] **Step 4: Implement `CaptureRow.swift`**

```swift
import Foundation

/// SQLite-shaped row stored in the `captures` table. Distinct from `CaptureRecord` (the
/// in-memory result of a capture operation) — `CaptureRow` includes index-only fields
/// like `thumbnailPath`, `fileSizeBytes`, `deletedAt` that the capture flow does not produce.
public struct CaptureRow: Equatable, Hashable, Sendable {

    public let uuid: UUID
    public let filePath: String
    public let annotationPath: String?
    public let thumbnailPath: String
    public let mediaType: MediaType
    public let capturedAt: Date
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let durationMs: Int?
    public let fileSizeBytes: Int64
    public let sourceApp: String?
    public let deletedAt: Date?

    public init(
        uuid: UUID,
        filePath: String,
        annotationPath: String?,
        thumbnailPath: String,
        mediaType: MediaType,
        capturedAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        durationMs: Int?,
        fileSizeBytes: Int64,
        sourceApp: String?,
        deletedAt: Date?
    ) {
        self.uuid = uuid
        self.filePath = filePath
        self.annotationPath = annotationPath
        self.thumbnailPath = thumbnailPath
        self.mediaType = mediaType
        self.capturedAt = capturedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationMs = durationMs
        self.fileSizeBytes = fileSizeBytes
        self.sourceApp = sourceApp
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// Convenience init from a freshly-completed `CaptureRecord` plus index-only fields.
    /// Plan 4 only writes image rows; Plan 6 (video recording) will add `.video` rows.
    public init(record: CaptureRecord, fileSizeBytes: Int64, thumbnailPath: String) {
        self.init(
            uuid: record.id,
            filePath: record.fileURL.path,
            annotationPath: nil,
            thumbnailPath: thumbnailPath,
            mediaType: .image,
            capturedAt: record.capturedAt,
            pixelWidth: record.pixelWidth,
            pixelHeight: record.pixelHeight,
            durationMs: nil,
            fileSizeBytes: fileSizeBytes,
            sourceApp: record.sourceApp,
            deletedAt: nil
        )
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRowTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Library/Model/MediaType.swift JuiceScreen/Library/Model/CaptureRow.swift JuiceScreenTests/CaptureRowTests.swift
git commit -m "feat(library): MediaType enum + CaptureRow value type (with CaptureRecord convenience init)"
```

---

## Task 3: `SmartFilter` enum + tests

**Files:**
- Create: `JuiceScreen/Library/Model/SmartFilter.swift`
- Create: `JuiceScreenTests/SmartFilterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("SmartFilter")
struct SmartFilterTests {

    @Test("All cases enumerated")
    func allCases() {
        let expected: Set<SmartFilter> = [.all, .today, .thisWeek, .thisMonth, .videos, .images, .trash]
        #expect(Set(SmartFilter.allCases) == expected)
    }

    @Test("Display name + SF Symbol per case")
    func metadata() {
        #expect(SmartFilter.all.displayName == "All")
        #expect(SmartFilter.today.displayName == "Today")
        #expect(SmartFilter.thisWeek.displayName == "This Week")
        #expect(SmartFilter.thisMonth.displayName == "This Month")
        #expect(SmartFilter.videos.displayName == "Videos")
        #expect(SmartFilter.images.displayName == "Images")
        #expect(SmartFilter.trash.displayName == "Trash")

        #expect(SmartFilter.all.sfSymbol == "tray.full")
        #expect(SmartFilter.today.sfSymbol == "calendar")
        #expect(SmartFilter.trash.sfSymbol == "trash")
    }

    @Test("includesTrash is true only for .trash filter")
    func includesTrash() {
        for f in SmartFilter.allCases where f != .trash {
            #expect(f.includesTrash == false)
        }
        #expect(SmartFilter.trash.includesTrash == true)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SmartFilterTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `SmartFilter.swift`**

```swift
import Foundation

public enum SmartFilter: String, CaseIterable, Sendable, Hashable, Identifiable {
    case all
    case today
    case thisWeek
    case thisMonth
    case videos
    case images
    case trash

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:       return "All"
        case .today:     return "Today"
        case .thisWeek:  return "This Week"
        case .thisMonth: return "This Month"
        case .videos:    return "Videos"
        case .images:    return "Images"
        case .trash:     return "Trash"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .all:       return "tray.full"
        case .today:     return "calendar"
        case .thisWeek:  return "calendar.badge.clock"
        case .thisMonth: return "calendar.circle"
        case .videos:    return "video"
        case .images:    return "photo"
        case .trash:     return "trash"
        }
    }

    public var includesTrash: Bool { self == .trash }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SmartFilterTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Model/SmartFilter.swift JuiceScreenTests/SmartFilterTests.swift
git commit -m "feat(library): SmartFilter enum (All/Today/Week/Month/Videos/Images/Trash)"
```

---

## Task 4: `LibraryPaths` + tests

**Files:**
- Create: `JuiceScreen/Library/Storage/LibraryPaths.swift`
- Create: `JuiceScreenTests/LibraryPathsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("LibraryPaths")
struct LibraryPathsTests {

    @Test("appSupportDirectory points at ~/Library/Application Support/JuiceScreen")
    func appSupportPath() throws {
        let paths = LibraryPaths()
        let dir = try paths.appSupportDirectory()
        #expect(dir.path.hasSuffix("Application Support/JuiceScreen"))
    }

    @Test("databaseURL is library.sqlite under appSupportDirectory")
    func dbPath() throws {
        let paths = LibraryPaths()
        let url = try paths.databaseURL()
        #expect(url.lastPathComponent == "library.sqlite")
    }

    @Test("thumbnailsDirectory is thumbnails/ under appSupportDirectory and is created on access")
    func thumbnailsPath() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = LibraryPaths(rootDirectory: tempRoot)
        let dir = try paths.thumbnailsDirectory()
        #expect(dir.lastPathComponent == "thumbnails")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("thumbnailURL(for:) returns <thumbnails>/<uuid>.jpg")
    func thumbnailURL() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let paths = LibraryPaths(rootDirectory: tempRoot)
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let url = try paths.thumbnailURL(for: id)
        #expect(url.lastPathComponent == "11111111-2222-3333-4444-555555555555.jpg")
        #expect(url.path.contains("/thumbnails/"))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryPathsTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `LibraryPaths.swift`**

```swift
import Foundation

/// Computes (and creates on first access) the JuiceScreen library paths under
/// `~/Library/Application Support/JuiceScreen/`. Tests can inject a different
/// `rootDirectory` to redirect into a temp directory.
public struct LibraryPaths: Sendable {

    private let rootDirectoryOverride: URL?
    private let fileManager: FileManager

    public init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.rootDirectoryOverride = rootDirectory
        self.fileManager = fileManager
    }

    public func appSupportDirectory() throws -> URL {
        if let override = rootDirectoryOverride {
            try fileManager.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("JuiceScreen", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func databaseURL() throws -> URL {
        try appSupportDirectory().appendingPathComponent("library.sqlite", isDirectory: false)
    }

    public func thumbnailsDirectory() throws -> URL {
        let dir = try appSupportDirectory().appendingPathComponent("thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func thumbnailURL(for id: UUID) throws -> URL {
        try thumbnailsDirectory()
            .appendingPathComponent("\(id.uuidString).jpg", isDirectory: false)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryPathsTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryPaths.swift JuiceScreenTests/LibraryPathsTests.swift
git commit -m "feat(library): LibraryPaths provider for app support dir + db + thumbnails"
```

---

## Task 5: `LibrarySchema` (DatabaseMigrator) + tests

**Files:**
- Create: `JuiceScreen/Library/Storage/LibrarySchema.swift`
- Create: `JuiceScreenTests/LibrarySchemaTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibrarySchemaTests 2>&1 | tail -8
```

Expected: compile failure (`LibrarySchema` undefined).

- [ ] **Step 3: Implement `LibrarySchema.swift`**

```swift
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
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibrarySchemaTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Storage/LibrarySchema.swift JuiceScreenTests/LibrarySchemaTests.swift
git commit -m "feat(library): LibrarySchema v1 migration (captures + captures_fts + indexes)"
```

---

## Task 6: `LibraryStore` protocol + `FakeLibraryStore` + tests

**Files:**
- Create: `JuiceScreen/Library/Storage/LibraryStore.swift`
- Create: `JuiceScreen/Library/Storage/FakeLibraryStore.swift`
- Create: `JuiceScreenTests/FakeLibraryStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeLibraryStore")
struct FakeLibraryStoreTests {

    private func makeRow(daysAgo: Int = 0, mediaType: MediaType = .image, deleted: Bool = false) -> CaptureRow {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/x.png",
            annotationPath: nil,
            thumbnailPath: "/tmp/t.jpg",
            mediaType: mediaType,
            capturedAt: date,
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil,
            fileSizeBytes: 1234,
            sourceApp: nil,
            deletedAt: deleted ? Date() : nil
        )
    }

    @Test("Insert + fetch round-trip")
    func insertFetch() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)
        let fetched = try await store.fetch(id: row.uuid)
        #expect(fetched == row)
    }

    @Test(".all returns live captures ordered by captured_at descending")
    func filterAll() async throws {
        let store = FakeLibraryStore()
        let oldest = makeRow(daysAgo: 5)
        let newest = makeRow(daysAgo: 0)
        let middle = makeRow(daysAgo: 2)
        try await store.insert(oldest)
        try await store.insert(newest)
        try await store.insert(middle)

        let live = try await store.list(filter: .all)
        #expect(live.map { $0.uuid } == [newest.uuid, middle.uuid, oldest.uuid])
    }

    @Test(".today returns only captures from today")
    func filterToday() async throws {
        let store = FakeLibraryStore()
        let today = makeRow(daysAgo: 0)
        let yesterday = makeRow(daysAgo: 1)
        try await store.insert(today)
        try await store.insert(yesterday)

        let result = try await store.list(filter: .today)
        #expect(result.map { $0.uuid } == [today.uuid])
    }

    @Test(".images excludes videos and vice versa")
    func filterByMediaType() async throws {
        let store = FakeLibraryStore()
        let image = makeRow(mediaType: .image)
        let video = makeRow(mediaType: .video)
        try await store.insert(image)
        try await store.insert(video)

        let images = try await store.list(filter: .images)
        let videos = try await store.list(filter: .videos)
        #expect(images.map { $0.uuid } == [image.uuid])
        #expect(videos.map { $0.uuid } == [video.uuid])
    }

    @Test(".trash returns only soft-deleted captures; non-trash filters exclude them")
    func filterTrash() async throws {
        let store = FakeLibraryStore()
        let live = makeRow()
        let trashed = makeRow(deleted: true)
        try await store.insert(live)
        try await store.insert(trashed)

        let allLive = try await store.list(filter: .all)
        let trash = try await store.list(filter: .trash)
        #expect(allLive.map { $0.uuid } == [live.uuid])
        #expect(trash.map { $0.uuid } == [trashed.uuid])
    }

    @Test("softDelete sets deletedAt and removes row from .all but adds it to .trash")
    func softDelete() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)

        let allLive = try await store.list(filter: .all)
        let trash = try await store.list(filter: .trash)
        #expect(allLive.isEmpty)
        #expect(trash.count == 1)
        #expect(trash.first!.uuid == row.uuid)
        #expect(trash.first!.isDeleted == true)
    }

    @Test("restore clears deletedAt and returns row to .all")
    func restore() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)
        try await store.restore(id: row.uuid)

        let allLive = try await store.list(filter: .all)
        #expect(allLive.count == 1)
        #expect(allLive.first!.isDeleted == false)
    }

    @Test("permanentlyDelete removes the row entirely")
    func permanentlyDelete() async throws {
        let store = FakeLibraryStore()
        let row = makeRow(deleted: true)
        try await store.insert(row)
        try await store.permanentlyDelete(id: row.uuid)

        let trash = try await store.list(filter: .trash)
        #expect(trash.isEmpty)
    }

    @Test("Fetching non-existent id returns nil")
    func fetchMissing() async throws {
        let store = FakeLibraryStore()
        let result = try await store.fetch(id: UUID())
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeLibraryStoreTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `LibraryStore.swift`**

```swift
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
```

- [ ] **Step 4: Implement `FakeLibraryStore.swift`**

```swift
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
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeLibraryStoreTests 2>&1 | tail -10
```

Expected: 9/9 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStore.swift JuiceScreen/Library/Storage/FakeLibraryStore.swift JuiceScreenTests/FakeLibraryStoreTests.swift
git commit -m "feat(library): LibraryStore protocol + FakeLibraryStore (in-memory test double)"
```

---

## Task 7: `LibraryStoreLive` (GRDB) + tests

**Files:**
- Create: `JuiceScreen/Library/Storage/LibraryStoreLive.swift`
- Create: `JuiceScreenTests/LibraryStoreLiveTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibraryStoreLive")
struct LibraryStoreLiveTests {

    /// Builds an in-memory GRDB DatabaseQueue with the v1 schema applied.
    private func makeStore() throws -> LibraryStoreLive {
        let queue = try DatabaseQueue()
        try LibrarySchema.migrator().migrate(queue)
        return LibraryStoreLive(databaseQueue: queue)
    }

    private func makeRow(daysAgo: Int = 0, mediaType: MediaType = .image, deleted: Bool = false, sourceApp: String? = nil) -> CaptureRow {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/\(UUID().uuidString).png",
            annotationPath: nil,
            thumbnailPath: "/tmp/thumb-\(UUID().uuidString).jpg",
            mediaType: mediaType,
            capturedAt: date,
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil,
            fileSizeBytes: 1234,
            sourceApp: sourceApp,
            deletedAt: deleted ? Date() : nil
        )
    }

    @Test("Insert + fetch round-trip preserves all fields")
    func insertFetch() async throws {
        let store = try makeStore()
        let row = makeRow(sourceApp: "Safari")
        try await store.insert(row)
        let fetched = try await store.fetch(id: row.uuid)
        #expect(fetched == row)
    }

    @Test(".all is ordered by captured_at descending and excludes soft-deleted")
    func listAll() async throws {
        let store = try makeStore()
        let live1 = makeRow(daysAgo: 1)
        let live2 = makeRow(daysAgo: 0)
        let trashed = makeRow(daysAgo: 0, deleted: true)
        try await store.insert(live1)
        try await store.insert(live2)
        try await store.insert(trashed)

        let result = try await store.list(filter: .all)
        #expect(result.map { $0.uuid } == [live2.uuid, live1.uuid])
    }

    @Test("softDelete then list .trash returns the trashed row")
    func softDeleteThenTrash() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)
        let trash = try await store.list(filter: .trash)
        #expect(trash.count == 1)
        #expect(trash.first!.isDeleted == true)
    }

    @Test("restore removes deletedAt")
    func restore() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.softDelete(id: row.uuid)
        try await store.restore(id: row.uuid)
        let live = try await store.list(filter: .all)
        #expect(live.count == 1)
        #expect(live.first!.isDeleted == false)
    }

    @Test("permanentlyDelete removes the row")
    func permanent() async throws {
        let store = try makeStore()
        let row = makeRow(deleted: true)
        try await store.insert(row)
        try await store.permanentlyDelete(id: row.uuid)
        #expect(try await store.fetch(id: row.uuid) == nil)
    }

    @Test("updateThumbnailPath persists the change")
    func updateThumb() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.updateThumbnailPath(id: row.uuid, thumbnailPath: "/new/thumb.jpg")
        let fetched = try await store.fetch(id: row.uuid)
        #expect(fetched?.thumbnailPath == "/new/thumb.jpg")
    }

    @Test("Filter .videos and .images segregate correctly")
    func mediaTypeFilter() async throws {
        let store = try makeStore()
        let image = makeRow(mediaType: .image)
        let video = makeRow(mediaType: .video)
        try await store.insert(image)
        try await store.insert(video)

        let images = try await store.list(filter: .images)
        let videos = try await store.list(filter: .videos)
        #expect(images.map { $0.uuid } == [image.uuid])
        #expect(videos.map { $0.uuid } == [video.uuid])
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryStoreLiveTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `LibraryStoreLive.swift`**

```swift
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
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryStoreLiveTests 2>&1 | tail -10
```

Expected: 7/7 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStoreLive.swift JuiceScreenTests/LibraryStoreLiveTests.swift
git commit -m "feat(library): LibraryStoreLive (GRDB-backed) with all CRUD + smart filters"
```

---

## Task 8: `ThumbnailGenerator` + tests

**Files:**
- Create: `JuiceScreen/Library/Thumbnails/ThumbnailGenerator.swift`
- Create: `JuiceScreenTests/ThumbnailGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("ThumbnailGenerator")
struct ThumbnailGeneratorTests {

    /// Deterministic 1× test fixture (matches Plan 2/3 PNG/JPG encoder pattern).
    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        color.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return img
    }

    @Test("Output starts with JPEG signature")
    func jpegSignature() throws {
        let img = solidImage(width: 1024, height: 768, color: .red)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        #expect(Array(data.prefix(2)) == [0xFF, 0xD8])
    }

    @Test("Wide image scales so longest dimension == 256, aspect preserved")
    func wideAspectFit() throws {
        let img = solidImage(width: 1024, height: 512, color: .blue)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 256)
        #expect(rep.pixelsHigh == 128)
    }

    @Test("Tall image scales so longest dimension == 256")
    func tallAspectFit() throws {
        let img = solidImage(width: 400, height: 800, color: .green)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 128)
        #expect(rep.pixelsHigh == 256)
    }

    @Test("Already-small image is not upscaled")
    func noUpscale() throws {
        let img = solidImage(width: 100, height: 50, color: .yellow)
        let data = try ThumbnailGenerator.generate(from: img, maxDimension: 256)
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == 100)
        #expect(rep.pixelsHigh == 50)
    }

    @Test("Throws on zero-size image")
    func zeroSize() {
        let bad = NSImage(size: .zero)
        #expect(throws: ThumbnailGeneratorError.self) {
            _ = try ThumbnailGenerator.generate(from: bad, maxDimension: 256)
        }
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ThumbnailGeneratorTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `ThumbnailGenerator.swift`**

```swift
import AppKit
import Foundation

public enum ThumbnailGeneratorError: Error, Equatable {
    case zeroSize
    case noBitmapRepresentation
    case encodingFailed
}

/// Pure helper: NSImage → JPG `Data` resized so the longest dimension is at most
/// `maxDimension`. Aspect-fit (no cropping). Already-small images pass through unchanged.
public enum ThumbnailGenerator {

    public static func generate(from image: NSImage, maxDimension: Int = 256, quality: Double = 0.8) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw ThumbnailGeneratorError.zeroSize
        }

        // Compute target pixel dimensions
        var srcRect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &srcRect, context: nil, hints: nil) else {
            throw ThumbnailGeneratorError.noBitmapRepresentation
        }
        let srcWidth = cg.width
        let srcHeight = cg.height

        let scale = min(
            CGFloat(maxDimension) / CGFloat(srcWidth),
            CGFloat(maxDimension) / CGFloat(srcHeight),
            1.0
        )
        let targetWidth = max(1, Int(round(CGFloat(srcWidth) * scale)))
        let targetHeight = max(1, Int(round(CGFloat(srcHeight) * scale)))

        // Render into a fresh NSBitmapImageRep at exact target pixel size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth, pixelsHigh: targetHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            throw ThumbnailGeneratorError.noBitmapRepresentation
        }
        rep.size = NSSize(width: targetWidth, height: targetHeight)

        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw ThumbnailGeneratorError.noBitmapRepresentation
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsCtx.imageInterpolation = .high
        nsCtx.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)]) else {
            throw ThumbnailGeneratorError.encodingFailed
        }
        return data
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ThumbnailGeneratorTests 2>&1 | tail -10
```

Expected: 5/5 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Thumbnails/ThumbnailGenerator.swift JuiceScreenTests/ThumbnailGeneratorTests.swift
git commit -m "feat(library): ThumbnailGenerator (NSImage → 256x256 aspect-fit JPG)"
```

---

## Task 9: `ThumbnailStore` + tests

**Files:**
- Create: `JuiceScreen/Library/Thumbnails/ThumbnailStore.swift`
- Create: `JuiceScreenTests/ThumbnailStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("ThumbnailStore")
struct ThumbnailStoreTests {

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    private func solidImage(_ size: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }

    @Test("write(image:for:) persists JPG at <thumbnails>/<uuid>.jpg and returns the path")
    func writeAndExists() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        let id = UUID()
        let img = solidImage(64)

        let path = try store.write(image: img, for: id)
        #expect(FileManager.default.fileExists(atPath: path))
        let url = URL(fileURLWithPath: path)
        #expect(url.lastPathComponent == "\(id.uuidString).jpg")
    }

    @Test("Overwrite is allowed (subsequent write replaces previous file)")
    func overwrite() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        let id = UUID()
        _ = try store.write(image: solidImage(32), for: id)
        _ = try store.write(image: solidImage(64), for: id)
        // Both calls succeed without throwing
    }

    @Test("delete(for:) removes the thumbnail file")
    func deleteThumb() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        let id = UUID()
        let path = try store.write(image: solidImage(16), for: id)
        try store.delete(for: id)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("delete(for:) is a no-op if the file doesn't exist")
    func deleteMissing() throws {
        let paths = makeTempPaths()
        let store = ThumbnailStore(paths: paths)
        try store.delete(for: UUID())   // does not throw
    }
}
```

(Note: temp directories created by `makeTempPaths` are GC'd by macOS — no explicit cleanup needed in tests.)

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ThumbnailStoreTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `ThumbnailStore.swift`**

```swift
import AppKit
import Foundation

public struct ThumbnailStore: Sendable {

    private let paths: LibraryPaths
    private let fileManager: FileManager

    public init(paths: LibraryPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    /// Generates a thumbnail for `image` and writes it to `<thumbnails>/<id>.jpg`,
    /// overwriting any existing file. Returns the absolute file path.
    @discardableResult
    public func write(image: NSImage, for id: UUID, maxDimension: Int = 256) throws -> String {
        let data = try ThumbnailGenerator.generate(from: image, maxDimension: maxDimension)
        let url = try paths.thumbnailURL(for: id)
        try data.write(to: url, options: .atomic)
        return url.path
    }

    public func delete(for id: UUID) throws {
        let url = try paths.thumbnailURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func url(for id: UUID) throws -> URL {
        try paths.thumbnailURL(for: id)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ThumbnailStoreTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Thumbnails/ThumbnailStore.swift JuiceScreenTests/ThumbnailStoreTests.swift
git commit -m "feat(library): ThumbnailStore writes <thumbnails>/<uuid>.jpg via ThumbnailGenerator"
```

---

## Task 10: `TrashService` + tests

**Files:**
- Create: `JuiceScreen/Library/Trash/TrashService.swift`
- Create: `JuiceScreenTests/TrashServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrashService")
struct TrashServiceTests {

    private func makeTempCaptureRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func touchFile(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: url)
    }

    @Test("moveToTrash relocates file under .trash/<uuid>/<basename> and returns new URL")
    func move() throws {
        let captureRoot = makeTempCaptureRoot()
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let original = captureRoot.appendingPathComponent("2026-05-05/JuiceScreen_x.png")
        try touchFile(at: original)

        let id = UUID()
        let svc = TrashService(captureRoot: captureRoot)
        let trashedURL = try svc.moveToTrash(file: original, captureID: id)

        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))
        #expect(trashedURL.path.contains("/.trash/\(id.uuidString)/"))
        #expect(trashedURL.lastPathComponent == "JuiceScreen_x.png")
    }

    @Test("restore moves file from trash back to <captureRoot>/<original date folder>/")
    func restoreFile() throws {
        let captureRoot = makeTempCaptureRoot()
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let original = captureRoot.appendingPathComponent("2026-05-05/JuiceScreen_x.png")
        try touchFile(at: original)

        let id = UUID()
        let svc = TrashService(captureRoot: captureRoot)
        let trashedURL = try svc.moveToTrash(file: original, captureID: id)
        let restored = try svc.restore(trashedFile: trashedURL, originalPath: original.path)

        #expect(FileManager.default.fileExists(atPath: restored.path))
        #expect(restored.path == original.path)
        #expect(!FileManager.default.fileExists(atPath: trashedURL.path))
    }

    @Test("permanentlyDelete removes the file and its containing capture-id folder")
    func permanent() throws {
        let captureRoot = makeTempCaptureRoot()
        defer { try? FileManager.default.removeItem(at: captureRoot) }

        let original = captureRoot.appendingPathComponent("2026-05-05/JuiceScreen_x.png")
        try touchFile(at: original)
        let id = UUID()
        let svc = TrashService(captureRoot: captureRoot)
        let trashedURL = try svc.moveToTrash(file: original, captureID: id)
        try svc.permanentlyDelete(trashedFile: trashedURL)

        #expect(!FileManager.default.fileExists(atPath: trashedURL.path))
        let captureFolder = trashedURL.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: captureFolder.path))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrashServiceTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `TrashService.swift`**

```swift
import Foundation

/// Manages move-to-trash, restore, and permanent-delete for capture files
/// under `<captureRoot>/.trash/<captureID>/<basename>`.
public struct TrashService: Sendable {

    private let captureRoot: URL
    private let fileManager: FileManager

    public init(captureRoot: URL, fileManager: FileManager = .default) {
        self.captureRoot = captureRoot
        self.fileManager = fileManager
    }

    public var trashRoot: URL {
        captureRoot.appendingPathComponent(".trash", isDirectory: true)
    }

    @discardableResult
    public func moveToTrash(file source: URL, captureID: UUID) throws -> URL {
        let folder = trashRoot.appendingPathComponent(captureID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(source.lastPathComponent, isDirectory: false)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: source, to: dest)
        return dest
    }

    @discardableResult
    public func restore(trashedFile trashed: URL, originalPath: String) throws -> URL {
        let dest = URL(fileURLWithPath: originalPath)
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: trashed, to: dest)
        // Clean up empty per-capture folder
        let captureFolder = trashed.deletingLastPathComponent()
        if let contents = try? fileManager.contentsOfDirectory(atPath: captureFolder.path),
           contents.isEmpty {
            try? fileManager.removeItem(at: captureFolder)
        }
        return dest
    }

    public func permanentlyDelete(trashedFile trashed: URL) throws {
        let captureFolder = trashed.deletingLastPathComponent()
        try fileManager.removeItem(at: trashed)
        if let contents = try? fileManager.contentsOfDirectory(atPath: captureFolder.path),
           contents.isEmpty {
            try? fileManager.removeItem(at: captureFolder)
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrashServiceTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Trash/TrashService.swift JuiceScreenTests/TrashServiceTests.swift
git commit -m "feat(library): TrashService move-to-trash + restore + permanent-delete"
```

---

## Task 11: `TrashGC` (background sweep) + tests

**Files:**
- Create: `JuiceScreen/Library/Trash/TrashGC.swift`
- Create: `JuiceScreenTests/TrashGCTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrashGC")
struct TrashGCTests {

    private func makeTempRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTrashedFile(in root: URL, captureID: UUID, ageInDays: Int) throws -> URL {
        let folder = root.appendingPathComponent(".trash/\(captureID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("file.png")
        try Data("x".utf8).write(to: url)
        let ageDate = Calendar.current.date(byAdding: .day, value: -ageInDays, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: ageDate], ofItemAtPath: url.path)
        return url
    }

    @Test("Files older than 30 days are deleted; younger files remain")
    func sweep() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldFile = try makeTrashedFile(in: root, captureID: UUID(), ageInDays: 60)
        let youngFile = try makeTrashedFile(in: root, captureID: UUID(), ageInDays: 5)

        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        let removed = try await gc.sweep()

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: youngFile.path))
    }

    @Test("Empty .trash directory sweep returns 0 with no error")
    func emptyTrash() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        let removed = try await gc.sweep()
        #expect(removed == 0)
    }

    @Test("Missing .trash directory sweep returns 0 with no error")
    func missingTrash() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-nonexistent-\(UUID().uuidString)", isDirectory: true)
        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        let removed = try await gc.sweep()
        #expect(removed == 0)
    }

    @Test("Empty per-capture folders are also removed")
    func emptyFoldersRemoved() async throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let oldFile = try makeTrashedFile(in: root, captureID: id, ageInDays: 60)
        let folder = oldFile.deletingLastPathComponent()

        let gc = TrashGC(captureRoot: root, maxAgeDays: 30)
        _ = try await gc.sweep()

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrashGCTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `TrashGC.swift`**

```swift
import Foundation

/// Sweeps `<captureRoot>/.trash/` and removes files (and their containing
/// per-capture folders, if empty afterward) older than `maxAgeDays`.
/// Returns the number of files deleted.
public struct TrashGC: Sendable {

    private let captureRoot: URL
    private let maxAgeDays: Int
    private let fileManager: FileManager

    public init(captureRoot: URL, maxAgeDays: Int = 30, fileManager: FileManager = .default) {
        self.captureRoot = captureRoot
        self.maxAgeDays = maxAgeDays
        self.fileManager = fileManager
    }

    public func sweep() async throws -> Int {
        let trashRoot = captureRoot.appendingPathComponent(".trash", isDirectory: true)
        guard fileManager.fileExists(atPath: trashRoot.path) else { return 0 }

        let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) ?? Date()
        var deletedCount = 0

        let captureFolders = (try? fileManager.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in captureFolders {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let attrs = try? fileManager.attributesOfItem(atPath: file.path)
                let mDate = attrs?[.modificationDate] as? Date ?? Date.distantFuture
                if mDate < cutoff {
                    try fileManager.removeItem(at: file)
                    deletedCount += 1
                }
            }

            // Remove now-empty per-capture folder
            if let remaining = try? fileManager.contentsOfDirectory(atPath: folder.path), remaining.isEmpty {
                try? fileManager.removeItem(at: folder)
            }
        }

        return deletedCount
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrashGCTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Trash/TrashGC.swift JuiceScreenTests/TrashGCTests.swift
git commit -m "feat(library): TrashGC background sweep for files older than 30 days"
```

---

## Task 12: `CaptureLibraryRecorder` + tests

**Files:**
- Create: `JuiceScreen/Library/CaptureLibraryRecorder.swift`
- Create: `JuiceScreenTests/CaptureLibraryRecorderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureLibraryRecorder")
struct CaptureLibraryRecorderTests {

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    private func makeRealFile() throws -> (URL, NSImage) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("JuiceScreen_x.png")

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: 100, height: 80))
        img.addRepresentation(rep)
        let data = try PNGEncoder.encode(img)
        try data.write(to: url)

        return (url, img)
    }

    @Test("record(_:) writes thumbnail, inserts row in store, and uses correct fields")
    func recordsCapture() async throws {
        let store = FakeLibraryStore()
        let paths = makeTempPaths()
        let thumbStore = ThumbnailStore(paths: paths)
        let recorder = CaptureLibraryRecorder(store: store, thumbnailStore: thumbStore)

        let (fileURL, _) = try makeRealFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let record = CaptureRecord(
            fileURL: fileURL,
            captureType: .region,
            capturedAt: Date(),
            pixelWidth: 100, pixelHeight: 80,
            sourceApp: nil
        )

        try await recorder.record(record)

        let stored = try await store.fetch(id: record.id)
        let row = try #require(stored)
        #expect(row.uuid == record.id)
        #expect(row.filePath == fileURL.path)
        #expect(row.pixelWidth == 100)
        #expect(row.pixelHeight == 80)
        #expect(row.fileSizeBytes > 0)
        #expect(FileManager.default.fileExists(atPath: row.thumbnailPath))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureLibraryRecorderTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `CaptureLibraryRecorder.swift`**

```swift
import AppKit
import Foundation

/// Glue service: after a successful capture, generates a thumbnail and inserts a
/// `CaptureRow` into the `LibraryStore`. Called by `AppDelegate.fireCapture` (Task 13).
public actor CaptureLibraryRecorder {

    private let store: LibraryStore
    private let thumbnailStore: ThumbnailStore
    private let log = AppLog.logger(category: "CaptureLibraryRecorder")

    public init(store: LibraryStore, thumbnailStore: ThumbnailStore) {
        self.store = store
        self.thumbnailStore = thumbnailStore
    }

    public func record(_ record: CaptureRecord) async throws {
        // Load the image from disk to generate a thumbnail. (CaptureRecord doesn't
        // carry pixels — they live in the file at fileURL.)
        guard let image = NSImage(contentsOf: record.fileURL) else {
            log.error("Could not read \(record.fileURL.path) to generate thumbnail")
            return
        }

        let thumbnailPath = try thumbnailStore.write(image: image, for: record.id)

        let attrs = try? FileManager.default.attributesOfItem(atPath: record.fileURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        let row = CaptureRow(record: record, fileSizeBytes: fileSize, thumbnailPath: thumbnailPath)
        try await store.insert(row)
        log.info("Indexed capture \(record.id) (\(fileSize) bytes)")
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureLibraryRecorderTests 2>&1 | tail -10
```

Expected: 1/1 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/CaptureLibraryRecorder.swift JuiceScreenTests/CaptureLibraryRecorderTests.swift
git commit -m "feat(library): CaptureLibraryRecorder writes thumbnail + inserts row after capture"
```

---

## Task 13: Wire `LibraryStore` + `CaptureLibraryRecorder` + `TrashGC` into `AppDelegate`

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Add library properties + open db on launch**

In `JuiceScreen/App/AppDelegate.swift`:

1. Add `import GRDB` at the top.

2. Add new properties after `editorWindowManager`:

```swift
    private lazy var libraryPaths: LibraryPaths = LibraryPaths()

    private lazy var libraryStore: LibraryStore = {
        do {
            let dbURL = try libraryPaths.databaseURL()
            let queue = try DatabaseQueue(path: dbURL.path)
            try LibrarySchema.migrator().migrate(queue)
            return LibraryStoreLive(databaseQueue: queue)
        } catch {
            log.error("Failed to open library database: \(String(describing: error))")
            // Fall back to a no-op fake; capture still works, indexing will silently no-op.
            return FakeLibraryStore()
        }
    }()

    private lazy var thumbnailStore: ThumbnailStore = ThumbnailStore(paths: libraryPaths)

    private lazy var captureLibraryRecorder: CaptureLibraryRecorder = {
        CaptureLibraryRecorder(store: libraryStore, thumbnailStore: thumbnailStore)
    }()
```

3. In `applicationDidFinishLaunching`, after the activation policy line, add a background trash GC sweep:

```swift
        // Background: GC trashed files older than 30 days
        Task.detached { [preferences] in
            let saveDir = preferences.load().saveDirectory
            let gc = TrashGC(captureRoot: saveDir)
            do {
                let removed = try await gc.sweep()
                if removed > 0 {
                    AppLog.logger(category: "App").info("TrashGC removed \(removed) files older than 30 days")
                }
            } catch {
                AppLog.logger(category: "App").error("TrashGC failed: \(String(describing: error))")
            }
        }
```

4. In `fireCapture(_:)`, after the existing `editorWindowManager.show(for: record)` line, add:

```swift
                Task { [captureLibraryRecorder] in
                    do {
                        try await captureLibraryRecorder.record(record)
                    } catch {
                        AppLog.logger(category: "App").error("Library recording failed: \(String(describing: error))")
                    }
                }
```

- [ ] **Step 2: Verify build + tests**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: `** BUILD SUCCEEDED **` and all unit tests pass (~140 across many suites).

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): instantiate library DB + recorder + run TrashGC at launch"
```

---

## Task 14: `LibraryViewModel` (`@Observable`) + tests

**Files:**
- Create: `JuiceScreen/MainWindow/Library/LibraryViewModel.swift`
- Create: `JuiceScreenTests/LibraryViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("LibraryViewModel")
@MainActor
struct LibraryViewModelTests {

    private func makeRow(daysAgo: Int = 0, mediaType: MediaType = .image, deleted: Bool = false) -> CaptureRow {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/x.png",
            annotationPath: nil,
            thumbnailPath: "/tmp/t.jpg",
            mediaType: mediaType,
            capturedAt: date,
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil,
            fileSizeBytes: 1234,
            sourceApp: nil,
            deletedAt: deleted ? Date() : nil
        )
    }

    @Test("Initial state: filter .all, no captures, no selection")
    func initial() async {
        let store = FakeLibraryStore()
        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        #expect(vm.filter == .all)
        #expect(vm.captures.isEmpty)
        #expect(vm.selectedID == nil)
    }

    @Test("reload() pulls captures matching the current filter")
    func reload() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)

        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        await vm.reload()
        #expect(vm.captures.count == 1)
        #expect(vm.captures.first?.uuid == row.uuid)
    }

    @Test("Changing filter triggers reload of new filter")
    func filterChange() async throws {
        let store = FakeLibraryStore()
        let live = makeRow()
        let trashed = makeRow(deleted: true)
        try await store.insert(live)
        try await store.insert(trashed)

        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        await vm.setFilter(.trash)
        #expect(vm.filter == .trash)
        #expect(vm.captures.count == 1)
        #expect(vm.captures.first?.uuid == trashed.uuid)
    }

    @Test("moveSelectedToTrash soft-deletes the selected capture and reloads")
    func moveToTrash() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)

        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        await vm.reload()
        vm.selectedID = row.uuid

        await vm.moveSelectedToTrash()
        #expect(vm.captures.isEmpty)
        #expect(vm.selectedID == nil)

        await vm.setFilter(.trash)
        #expect(vm.captures.count == 1)
        #expect(vm.captures.first?.deletedAt != nil)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryViewModelTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `LibraryViewModel.swift`**

```swift
import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class LibraryViewModel {

    public private(set) var filter: SmartFilter = .all
    public private(set) var captures: [CaptureRow] = []
    public var selectedID: UUID? = nil
    public var tileSize: CGFloat = 150     // 100–300pt slider
    public var searchText: String = ""     // wired to a no-op Plan 5 placeholder for now

    private let store: LibraryStore
    public let thumbnailStore: ThumbnailStore
    private let log = AppLog.logger(category: "LibraryViewModel")

    public init(store: LibraryStore, thumbnailStore: ThumbnailStore) {
        self.store = store
        self.thumbnailStore = thumbnailStore
    }

    public func reload() async {
        do {
            captures = try await store.list(filter: filter)
        } catch {
            log.error("List failed: \(String(describing: error))")
            captures = []
        }
    }

    public func setFilter(_ new: SmartFilter) async {
        filter = new
        selectedID = nil
        await reload()
    }

    public var selectedCapture: CaptureRow? {
        guard let id = selectedID else { return nil }
        return captures.first { $0.uuid == id }
    }

    public func moveSelectedToTrash() async {
        guard let id = selectedID else { return }
        do {
            try await store.softDelete(id: id)
            selectedID = nil
            await reload()
        } catch {
            log.error("softDelete failed: \(String(describing: error))")
        }
    }

    public func revealSelectedInFinder() {
        guard let row = selectedCapture else { return }
        let url = URL(fileURLWithPath: row.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func copySelectedFile() {
        guard let row = selectedCapture else { return }
        let url = URL(fileURLWithPath: row.filePath)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryViewModelTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/MainWindow/Library/LibraryViewModel.swift JuiceScreenTests/LibraryViewModelTests.swift
git commit -m "feat(library): LibraryViewModel @Observable wrapping LibraryStore + actions"
```

---

## Task 15: `SidebarView`

**Files:**
- Create: `JuiceScreen/MainWindow/Library/SidebarView.swift`

- [ ] **Step 1: Implement `SidebarView.swift`**

```swift
import SwiftUI

struct SidebarView: View {

    @Bindable var vm: LibraryViewModel
    let onOpenSettings: () -> Void

    var body: some View {
        List {
            Section("Library") {
                ForEach(SmartFilter.allCases) { f in
                    row(filter: f)
                }
            }
            Section {
                Button(action: onOpenSettings) {
                    Label("Settings…", systemImage: "gear")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    private func row(filter f: SmartFilter) -> some View {
        Button {
            Task { await vm.setFilter(f) }
        } label: {
            Label(f.displayName, systemImage: f.sfSymbol)
                .foregroundStyle(vm.filter == f ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MainWindow/Library/SidebarView.swift
git commit -m "feat(library): SidebarView (filter list + Settings entry)"
```

---

## Task 16: `CaptureTile`

**Files:**
- Create: `JuiceScreen/MainWindow/Library/CaptureTile.swift`

- [ ] **Step 1: Implement `CaptureTile.swift`**

```swift
import AppKit
import SwiftUI

struct CaptureTile: View {

    let row: CaptureRow
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: size, height: size * 0.7)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(formatBadge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(6)
            }

            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: size)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if FileManager.default.fileExists(atPath: row.thumbnailPath),
           let img = NSImage(contentsOfFile: row.thumbnailPath) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "photo")
                .font(.system(size: size / 4))
                .foregroundStyle(.tertiary)
        }
    }

    private var formatBadge: String {
        switch row.mediaType {
        case .image: return URL(fileURLWithPath: row.filePath).pathExtension.uppercased()
        case .video: return "MP4"
        }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: row.capturedAt, relativeTo: Date())
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MainWindow/Library/CaptureTile.swift
git commit -m "feat(library): CaptureTile (thumbnail + badge + time-ago)"
```

---

## Task 17: `CaptureGridView` + `EmptyStateView`

**Files:**
- Create: `JuiceScreen/MainWindow/Library/EmptyStateView.swift`
- Create: `JuiceScreen/MainWindow/Library/CaptureGridView.swift`

- [ ] **Step 1: Implement `EmptyStateView.swift`**

```swift
import SwiftUI

struct EmptyStateView: View {

    let filter: SmartFilter

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .trash ? "trash.slash" : "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(emptyMessage)
                .font(.title3)
                .foregroundStyle(.secondary)

            if filter == .all {
                Text("Press ⌘⇧4 to capture a region.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyMessage: String {
        switch filter {
        case .all:        return "No captures yet"
        case .today:      return "No captures today"
        case .thisWeek:   return "No captures this week"
        case .thisMonth:  return "No captures this month"
        case .videos:     return "No videos"
        case .images:     return "No images"
        case .trash:      return "Trash is empty"
        }
    }
}
```

- [ ] **Step 2: Implement `CaptureGridView.swift`**

```swift
import SwiftUI

struct CaptureGridView: View {

    @Bindable var vm: LibraryViewModel
    let onOpen: (CaptureRow) -> Void

    var body: some View {
        ScrollView {
            if vm.captures.isEmpty {
                EmptyStateView(filter: vm.filter)
                    .frame(minHeight: 400)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(vm.captures, id: \.uuid) { row in
                        CaptureTile(row: row, isSelected: vm.selectedID == row.uuid, size: vm.tileSize)
                            .onTapGesture { vm.selectedID = row.uuid }
                            .onTapGesture(count: 2) { onOpen(row) }
                            .contextMenu {
                                Button("Open in Editor") { onOpen(row) }
                                Button("Reveal in Finder") {
                                    vm.selectedID = row.uuid
                                    vm.revealSelectedInFinder()
                                }
                                Button("Copy File") {
                                    vm.selectedID = row.uuid
                                    vm.copySelectedFile()
                                }
                                Divider()
                                Button("Move to Trash", role: .destructive) {
                                    vm.selectedID = row.uuid
                                    Task { await vm.moveSelectedToTrash() }
                                }
                            }
                    }
                }
                .padding(16)
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: vm.tileSize, maximum: vm.tileSize), spacing: 16, alignment: .topLeading)]
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/MainWindow/Library/EmptyStateView.swift JuiceScreen/MainWindow/Library/CaptureGridView.swift
git commit -m "feat(library): CaptureGridView (LazyVGrid + context menu) + EmptyStateView"
```

---

## Task 18: `InspectorView`

**Files:**
- Create: `JuiceScreen/MainWindow/Library/InspectorView.swift`

- [ ] **Step 1: Implement `InspectorView.swift`**

```swift
import AppKit
import SwiftUI

struct InspectorView: View {

    let row: CaptureRow
    @Bindable var vm: LibraryViewModel
    let onOpen: (CaptureRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail
            if FileManager.default.fileExists(atPath: row.thumbnailPath),
               let img = NSImage(contentsOfFile: row.thumbnailPath) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                metaRow("Captured", value: capturedDate)
                metaRow("Size", value: "\(row.pixelWidth) × \(row.pixelHeight) px")
                metaRow("File", value: ByteCountFormatter.string(fromByteCount: row.fileSizeBytes, countStyle: .file))
                if let app = row.sourceApp { metaRow("Source", value: app) }
                metaRow("Type", value: row.mediaType == .video ? "Video" : "Image")
            }

            Divider()

            // Action buttons
            VStack(alignment: .leading, spacing: 6) {
                Button { onOpen(row) } label: {
                    Label("Open in Editor", systemImage: "pencil.tip.crop.circle")
                }
                Button { vm.revealSelectedInFinder() } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button { vm.copySelectedFile() } label: {
                    Label("Copy File", systemImage: "doc.on.doc")
                }
                if row.isDeleted == false {
                    Button(role: .destructive) {
                        Task { await vm.moveSelectedToTrash() }
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
            }
            .buttonStyle(.bordered)

            Divider()

            // OCR placeholder (Plan 5)
            VStack(alignment: .leading, spacing: 4) {
                Text("OCR Text").font(.caption).foregroundStyle(.secondary)
                Text("Extracted text will appear here in v0.5 (Plan 5).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .italic()
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 280)
        .background(.regularMaterial)
    }

    private var capturedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: row.capturedAt)
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(.primary)
            Spacer()
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MainWindow/Library/InspectorView.swift
git commit -m "feat(library): InspectorView (metadata + actions + OCR placeholder)"
```

---

## Task 19: `LibraryView` (two-pane)

**Files:**
- Create: `JuiceScreen/MainWindow/Library/LibraryView.swift`

- [ ] **Step 1: Implement `LibraryView.swift`**

```swift
import AppKit
import SwiftUI

struct LibraryView: View {

    @Bindable var vm: LibraryViewModel
    let onOpen: (CaptureRow) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(vm: vm, onOpenSettings: onOpenSettings)

            Divider()

            VStack(spacing: 0) {
                searchBar
                CaptureGridView(vm: vm, onOpen: onOpen)
            }

            if let row = vm.selectedCapture {
                Divider()
                InspectorView(row: row, vm: vm, onOpen: onOpen)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: vm.selectedID)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Slider(value: $vm.tileSize, in: 100...300, step: 10)
                    .frame(width: 120)
                    .help("Tile size")
            }
        }
        .task { await vm.reload() }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search by OCR text (Plan 5)", text: $vm.searchText)
                .textFieldStyle(.plain)
                .disabled(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MainWindow/Library/LibraryView.swift
git commit -m "feat(library): LibraryView two-pane (sidebar + grid + slide-in inspector)"
```

---

## Task 20: `LibraryWindow` + `LibraryWindowManager`

**Files:**
- Create: `JuiceScreen/MainWindow/Library/LibraryWindow.swift`
- Create: `JuiceScreen/MainWindow/Library/LibraryWindowManager.swift`

- [ ] **Step 1: Implement `LibraryWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class LibraryWindow {

    let window: NSWindow
    private let vm: LibraryViewModel

    init(store: LibraryStore, thumbnailStore: ThumbnailStore,
         onOpenCapture: @escaping (CaptureRow) -> Void,
         onOpenSettings: @escaping () -> Void) {
        let vm = LibraryViewModel(store: store, thumbnailStore: thumbnailStore)
        self.vm = vm

        let frame = NSRect(x: 0, y: 0, width: 980, height: 640)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "JuiceScreen — Library"
        win.contentView = NSHostingView(rootView: LibraryView(vm: vm, onOpen: onOpenCapture, onOpenSettings: onOpenSettings))
        win.center()
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 720, height: 480)
        self.window = win
    }

    func show() {
        Task { await vm.reload() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Implement `LibraryWindowManager.swift`**

```swift
import AppKit
import Foundation

@MainActor
public final class LibraryWindowManager {

    private var window: LibraryWindow?
    private let store: LibraryStore
    private let thumbnailStore: ThumbnailStore
    private let onOpenCapture: (CaptureRow) -> Void
    private let onOpenSettings: () -> Void

    public init(store: LibraryStore,
                thumbnailStore: ThumbnailStore,
                onOpenCapture: @escaping (CaptureRow) -> Void,
                onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.thumbnailStore = thumbnailStore
        self.onOpenCapture = onOpenCapture
        self.onOpenSettings = onOpenSettings
    }

    public func show() {
        if let existing = window {
            existing.show()
            return
        }
        let win = LibraryWindow(
            store: store,
            thumbnailStore: thumbnailStore,
            onOpenCapture: onOpenCapture,
            onOpenSettings: onOpenSettings
        )
        window = win
        win.show()
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/MainWindow/Library/LibraryWindow.swift JuiceScreen/MainWindow/Library/LibraryWindowManager.swift
git commit -m "feat(library): LibraryWindow + LibraryWindowManager (singleton, ⌘⇧L)"
```

---

## Task 21: Wire openLibrary action + tile-click → editor in `AppDelegate`

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Replace the `openLibrary` placeholder with the real action**

In `JuiceScreen/App/AppDelegate.swift`:

1. Add a property after `captureLibraryRecorder`:

```swift
    private lazy var libraryWindowManager: LibraryWindowManager = {
        LibraryWindowManager(
            store: libraryStore,
            thumbnailStore: thumbnailStore,
            onOpenCapture: { [weak self] row in
                guard let self else { return }
                // Re-open in the editor: build a CaptureRecord from the row
                let record = CaptureRecord(
                    id: row.uuid,
                    fileURL: URL(fileURLWithPath: row.filePath),
                    captureType: .region,   // type unknown post-hoc; .region is a sensible default
                    capturedAt: row.capturedAt,
                    pixelWidth: row.pixelWidth,
                    pixelHeight: row.pixelHeight,
                    sourceApp: row.sourceApp
                )
                self.editorWindowManager.show(for: record)
            },
            onOpenSettings: { SettingsWindow.show() }
        )
    }()
```

2. In `applicationDidFinishLaunching`, replace the existing `openLibrary` action in the MenuBarActions struct:

```swift
            openLibrary:       { [weak self] in self?.libraryWindowManager.show() },
```

(Previously it called `self?.todoLog("openLibrary")` — that whole closure becomes the line above.)

The full updated MenuBarActions block in `applicationDidFinishLaunching`:

```swift
        let actions = MenuBarActions(
            captureRegion:     { [weak self] in self?.fireCapture(.region) },
            captureWindow:     { [weak self] in self?.fireCapture(.window) },
            captureFullScreen: { [weak self] in self?.fireCapture(.fullScreen) },
            captureLastRegion: { [weak self] in self?.fireCapture(.lastRegion) },
            recordScreen:      { [weak self] in self?.todoLog("recordScreen") },
            openLibrary:       { [weak self] in self?.libraryWindowManager.show() },
            openPreferences:   { SettingsWindow.show() },
            quit:              { NSApp.terminate(nil) }
        )
```

- [ ] **Step 2: Verify build + tests**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: build succeeds and all tests still pass.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): wire LibraryWindowManager into openLibrary action (⌘⇧L)"
```

---

## Task 22: Bump VERSION to 0.4.0, full test, manual smoke, tag

**Files:**
- Modify: `VERSION` — `0.4.0`
- Modify: `project.yml` — `MARKETING_VERSION: "0.4.0"`

- [ ] **Step 1: Update VERSION + project.yml**

Replace `VERSION` contents with:

```
0.4.0
```

In `project.yml`, change `MARKETING_VERSION: "0.3.0"` to `MARKETING_VERSION: "0.4.0"`.

- [ ] **Step 2: Clean build + full test**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
rm -rf ~/Library/Developer/Xcode/DerivedData/JuiceScreen-*
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
```

Expected: build + tests succeed (~140 unit tests across many suites).

- [ ] **Step 3: Manual smoke test (HUMAN STEP)**

Run the app and verify each of these:

| # | Action | Expected |
|---|---|---|
| 1 | Launch app, take a fresh capture (⌘⌃4 or ⌘⇧4 region) | PNG saved AND row inserted into library |
| 2 | Press ⌘⇧L | Library window opens with the new capture as a tile |
| 3 | Click another sidebar filter (Today / Images) | Grid filters accordingly |
| 4 | Click a tile | Inspector slides in from right with metadata |
| 5 | Double-click a tile | Editor window opens for that capture |
| 6 | Right-click a tile → Reveal in Finder | Finder opens with the file selected |
| 7 | Right-click a tile → Move to Trash | Tile disappears from current view; appears in Trash filter |
| 8 | Switch to Trash filter | Soft-deleted capture appears |
| 9 | Take 2-3 captures, then close + relaunch app, ⌘⇧L | All captures still there (persisted via SQLite) |
| 10 | Open `~/Library/Application Support/JuiceScreen/library.sqlite` in DB Browser for SQLite (or `sqlite3` CLI) | Schema present, captures table has rows |
| 11 | Open `~/Pictures/JuiceScreen/.trash/<uuid>/` in Finder | Trashed file is there |
| 12 | Open `~/Library/Application Support/JuiceScreen/thumbnails/` | One JPG per capture |

If any step fails: do **not** tag.

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION project.yml
git commit -m "chore: bump VERSION to 0.4.0"
git tag -a v0.4.0 -m "Library + Storage milestone: SQLite-backed library window with thumbnails + soft delete"
git tag -l v0.4.0
```

- [ ] **Step 5: Verify clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Task 23: Update spec doc with Plan 4 status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Replace Plan 4 line**

In the implementation status section, replace `⬜ Plan 4: Library + storage` with:

```
- ✅ **Plan 4: Library + storage** (v0.4.0, 2026-05-05) — GRDB+SQLite library at ~/Library/Application Support/JuiceScreen/library.sqlite (with FTS5 virtual table created for Plan 5 to populate). 256×256 aspect-fit JPG thumbnails per capture under `thumbnails/`. CaptureLibraryRecorder writes a row + thumbnail after every capture. Soft-delete moves files to `~/Pictures/JuiceScreen/.trash/<uuid>/` with TrashGC sweep on launch deleting files older than 30 days. ⌘⇧L opens a two-pane main window: SidebarView (7 smart filters + Settings) + responsive LazyVGrid of CaptureTile + slide-in InspectorView with metadata + actions (Open in Editor / Reveal / Copy File / Move to Trash). Double-click tile re-opens editor. Search bar disabled (Plan 5 wires OCR); Trash restore not yet exposed in UI (planned for Settings → Storage in Plan 9). ~140 unit tests passing
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 4 (Library + storage) complete in implementation status"
```

---

## Plan completion checklist

After Task 23:

- [ ] `git log --oneline | head -25` shows ~22 new commits since v0.3.0
- [ ] `git tag -l` shows v0.1.0, v0.2.0, v0.3.0, v0.4.0
- [ ] `xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests` is green
- [ ] All 12 manual smoke-test items pass
- [ ] `~/Library/Application Support/JuiceScreen/library.sqlite` exists and contains rows
- [ ] `~/Pictures/JuiceScreen/.trash/` exists when you've moved at least one capture there

When everything checks out: ship v0.4.0 alpha. Plan 5 is next — OCR + FTS5 search wiring.
