# JuiceScreen — Image Capture Implementation Plan (Plan 2 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.2.0` — replaces the four `todoLog` placeholders in `AppDelegate` with real image capture for region / window / full-screen / last-region modes. Saves PNG files to `~/Pictures/JuiceScreen/YYYY-MM-DD/` with timestamped filenames. End state: pressing the configured hotkey (default `⌘⌃4` after Plan 1's first-run wizard chose alternative defaults, or `⌘⇧4` if the user disabled the macOS screenshot shortcuts) produces a real screenshot file on disk.

**Architecture:** New `Capture/Image/` module. `CaptureEngine` protocol with a `Live` impl wrapping ScreenCaptureKit (`SCScreenshotManager`, `SCContentSharingPicker`, `SCShareableContent`) and a `Fake` for tests. Region picker is a custom transparent `NSWindow` covering all displays with mouse/keyboard handling. Storage layer (`CaptureRecordWriter`, `FilenameGenerator`, `SaveDirectoryProvider`) is fully unit-tested with fixture `NSImage`s; ScreenCaptureKit-touching code is verified by manual smoke test.

**Tech Stack:** ScreenCaptureKit (`SCScreenshotManager`, `SCContentFilter`, `SCShareableContent`, `SCContentSharingPicker`), AppKit (`NSWindow` overlay, `NSBitmapImageRep` for PNG encoding), SwiftUI (region picker view + multi-display picker), Swift Testing (unit tests), existing Foundation modules from Plan 1 (`Preferences`, `PreferencesStore`, `MenuBarController`, `HotkeyService`, `AppLog`).

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — sections "Image capture" and "Region picker overlay details".

**Plan 1 prerequisite:** v0.1.0 tagged. The app builds, the menu bar item shows, hotkeys are registered, and the four capture menu items currently call `AppDelegate.todoLog(...)`. Plan 2 replaces those four call sites with real captures.

**Scope deferred to later plans:**

- Magnifier loupe at the cursor (defer to a Plan 2.1 polish pass — adds complexity, not core value)
- Window-edge snapping (same — needs SCShareableContent window list integration)
- Cursor cosmetic in stills (the `includeCursor` setting from spec § Settings)
- Multi-display picker UI polish (we ship a minimal SwiftUI picker — decoration in later plan)

The decision to defer the loupe and snapping is honest YAGNI: the spec explicitly mentions them under "Region picker overlay details" but they are pure polish on top of a working drag-to-select. Shipping v0.2.0 without them gets us to a usable screenshot tool faster.

---

## File Structure

```
JuiceScreen/
├── Shared/
│   ├── CaptureRecord.swift           NEW — value type describing a successful capture
│   ├── CaptureType.swift             NEW — enum: region / window / fullScreen / lastRegion
│   ├── FilenameGenerator.swift       NEW — produces "JuiceScreen_2026-05-05_at_14.32.18.png"
│   └── SaveDirectoryProvider.swift   NEW — ensures ~/Pictures/JuiceScreen/YYYY-MM-DD/ exists
├── Capture/
│   └── Image/
│       ├── CaptureEngine.swift           NEW — protocol
│       ├── CaptureEngineLive.swift       NEW — ScreenCaptureKit impl
│       ├── FakeCaptureEngine.swift       NEW — test double
│       ├── CaptureError.swift            NEW — Error enum
│       ├── PNGEncoder.swift              NEW — NSImage → Data (for writer + tests)
│       ├── CaptureRecordWriter.swift     NEW — writes CaptureRecord + PNG to disk
│       ├── ScreenCaptureKitHelpers.swift NEW — SCShareableContent async wrapper, SCContentFilter builders
│       ├── DisplayPickerView.swift       NEW — multi-display SwiftUI picker (used when 2+ displays for full-screen)
│       ├── DisplayPickerWindow.swift     NEW — modal NSWindow hosting DisplayPickerView
│       ├── WindowPickerService.swift     NEW — wraps SCContentSharingPicker
│       ├── RegionSelection.swift         NEW — value type for in-progress drag selection
│       ├── RegionPickerOverlayWindow.swift NEW — transparent NSWindow covering all displays
│       ├── RegionPickerView.swift        NEW — SwiftUI dimming + selection rectangle + dimensions label
│       └── RegionPickerController.swift  NEW — orchestrator, returns CGRect via async API
├── App/
│   └── AppDelegate.swift             MODIFY — replace 4 todoLog call sites with real captures (Task 18)
├── Preferences/
│   ├── Preferences.swift             MODIFY — add lastRegion: CGRect? (Task 16)
│   └── PreferencesStore.swift        MODIFY — load/save lastRegion (Task 16)
└── (tests added under JuiceScreenTests/ as each task lands)

VERSION                               MODIFY — bump to 0.2.0 (Task 19)
docs/superpowers/specs/2026-05-04-juicescreen-design.md  MODIFY — implementation status (Task 20)
```

---

## Task 1: `CaptureType` enum + `CaptureRecord` value type + tests

**Files:**
- Create: `JuiceScreen/Shared/CaptureType.swift`
- Create: `JuiceScreen/Shared/CaptureRecord.swift`
- Create: `JuiceScreenTests/CaptureRecordTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/CaptureRecordTests.swift`:

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureRecord")
struct CaptureRecordTests {

    @Test("CaptureType is exhaustively case-iterable")
    func captureTypeAllCases() {
        let all = Set(CaptureType.allCases)
        #expect(all == [.region, .window, .fullScreen, .lastRegion])
    }

    @Test("CaptureRecord stores all metadata fields")
    func storesFields() {
        let url = URL(fileURLWithPath: "/tmp/JuiceScreen_2026-05-05_at_14.32.18.png")
        let date = Date(timeIntervalSince1970: 1_770_000_000)
        let record = CaptureRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            fileURL: url,
            captureType: .region,
            capturedAt: date,
            pixelWidth: 1024,
            pixelHeight: 768,
            sourceApp: "Safari"
        )

        #expect(record.fileURL == url)
        #expect(record.captureType == .region)
        #expect(record.capturedAt == date)
        #expect(record.pixelWidth == 1024)
        #expect(record.pixelHeight == 768)
        #expect(record.sourceApp == "Safari")
    }

    @Test("sourceApp is optional")
    func sourceAppNullable() {
        let record = CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/x.png"),
            captureType: .fullScreen,
            capturedAt: Date(),
            pixelWidth: 100,
            pixelHeight: 100,
            sourceApp: nil
        )
        #expect(record.sourceApp == nil)
    }

    @Test("Convenience init generates a UUID when not supplied")
    func convenienceInit() {
        let a = CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/a.png"),
            captureType: .window,
            capturedAt: Date(),
            pixelWidth: 1, pixelHeight: 1,
            sourceApp: nil
        )
        let b = CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/b.png"),
            captureType: .window,
            capturedAt: Date(),
            pixelWidth: 1, pixelHeight: 1,
            sourceApp: nil
        )
        #expect(a.id != b.id)
    }

    @Test("Equatable: same field values are equal")
    func equatable() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/x.png")
        let date = Date(timeIntervalSince1970: 0)
        let a = CaptureRecord(id: id, fileURL: url, captureType: .region,
                              capturedAt: date, pixelWidth: 10, pixelHeight: 10, sourceApp: nil)
        let b = CaptureRecord(id: id, fileURL: url, captureType: .region,
                              capturedAt: date, pixelWidth: 10, pixelHeight: 10, sourceApp: nil)
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRecordTests 2>&1 | tail -10
```

Expected: compile failure — `CaptureType` and `CaptureRecord` undefined.

- [ ] **Step 3: Implement `CaptureType.swift`**

```swift
import Foundation

/// What kind of capture produced a `CaptureRecord`.
public enum CaptureType: String, CaseIterable, Sendable, Hashable {
    case region
    case window
    case fullScreen
    case lastRegion
}
```

- [ ] **Step 4: Implement `CaptureRecord.swift`**

```swift
import Foundation

/// Metadata describing a successful capture. Pure value type — no I/O, no NSImage payload
/// (the pixels live in the file at `fileURL`).
public struct CaptureRecord: Equatable, Hashable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let captureType: CaptureType
    public let capturedAt: Date
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sourceApp: String?

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        captureType: CaptureType,
        capturedAt: Date,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceApp: String?
    ) {
        self.id = id
        self.fileURL = fileURL
        self.captureType = captureType
        self.capturedAt = capturedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceApp = sourceApp
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRecordTests 2>&1 | tail -10
```

Expected: 5/5 cases pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Shared/CaptureType.swift JuiceScreen/Shared/CaptureRecord.swift JuiceScreenTests/CaptureRecordTests.swift
git commit -m "feat(shared): add CaptureType enum + CaptureRecord value type"
```

---

## Task 2: `FilenameGenerator` + tests

**Files:**
- Create: `JuiceScreen/Shared/FilenameGenerator.swift`
- Create: `JuiceScreenTests/FilenameGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FilenameGenerator")
struct FilenameGeneratorTests {

    private let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test("Default PNG filename for a known timestamp")
    func pngFilename() {
        let comps = DateComponents(year: 2026, month: 5, day: 4, hour: 14, minute: 32, second: 18)
        let date = utcCalendar.date(from: comps)!
        let gen = FilenameGenerator(calendar: utcCalendar)
        #expect(gen.filename(for: date, extension: "png") ==
                "JuiceScreen_2026-05-04_at_14.32.18.png")
    }

    @Test("Different extensions are honored")
    func differentExtensions() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5))!
        let gen = FilenameGenerator(calendar: utcCalendar)
        #expect(gen.filename(for: date, extension: "jpg") == "JuiceScreen_2026-01-02_at_03.04.05.jpg")
        #expect(gen.filename(for: date, extension: "mp4") == "JuiceScreen_2026-01-02_at_03.04.05.mp4")
    }

    @Test("Zero-padding for single-digit month / day / time components")
    func zeroPadding() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5))!
        let gen = FilenameGenerator(calendar: utcCalendar)
        let name = gen.filename(for: date, extension: "png")
        #expect(name == "JuiceScreen_2026-01-02_at_03.04.05.png")
    }

    @Test("Date subfolder ('2026-05-04') for grouping")
    func subfolderName() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 5, day: 4))!
        let gen = FilenameGenerator(calendar: utcCalendar)
        #expect(gen.dateSubfolderName(for: date) == "2026-05-04")
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FilenameGeneratorTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `FilenameGenerator.swift`**

```swift
import Foundation

/// Generates filenames in the canonical JuiceScreen format:
/// `JuiceScreen_YYYY-MM-DD_at_HH.MM.SS.<ext>`. All values zero-padded.
/// Calendar is injected so tests can be timezone-deterministic; production
/// uses the user's local calendar.
public struct FilenameGenerator: Sendable {

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func filename(for date: Date, extension ext: String) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "JuiceScreen_%04d-%02d-%02d_at_%02d.%02d.%02d.%@",
            c.year ?? 0, c.month ?? 0, c.day ?? 0,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0,
            ext
        )
    }

    public func dateSubfolderName(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FilenameGeneratorTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Shared/FilenameGenerator.swift JuiceScreenTests/FilenameGeneratorTests.swift
git commit -m "feat(shared): FilenameGenerator for JuiceScreen_YYYY-MM-DD_at_HH.MM.SS.<ext>"
```

---

## Task 3: `SaveDirectoryProvider` + tests

**Files:**
- Create: `JuiceScreen/Shared/SaveDirectoryProvider.swift`
- Create: `JuiceScreenTests/SaveDirectoryProviderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("SaveDirectoryProvider")
struct SaveDirectoryProviderTests {

    private func makeTempRoot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Creates the date subfolder under the configured root and returns its URL")
    func createsDateFolder() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = SaveDirectoryProvider(rootDirectory: root, filenameGenerator: FilenameGenerator())
        let date = Date()
        let folder = try provider.directory(for: date)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
        // Folder name matches FilenameGenerator's dateSubfolderName output
        let expectedName = FilenameGenerator().dateSubfolderName(for: date)
        #expect(folder.lastPathComponent == expectedName)
    }

    @Test("Idempotent: calling twice for same date returns same path and does not error")
    func idempotent() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = SaveDirectoryProvider(rootDirectory: root, filenameGenerator: FilenameGenerator())
        let date = Date()
        let a = try provider.directory(for: date)
        let b = try provider.directory(for: date)
        #expect(a == b)
    }

    @Test("Creates the root directory if absent")
    func createsRootIfMissing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)/Pictures/JuiceScreen", isDirectory: true)
        defer {
            // Clean up a couple of levels
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent())
        }

        let provider = SaveDirectoryProvider(rootDirectory: root, filenameGenerator: FilenameGenerator())
        let folder = try provider.directory(for: Date())

        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SaveDirectoryProviderTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `SaveDirectoryProvider.swift`**

```swift
import Foundation

/// Ensures the dated capture folder exists under the configured root
/// (default `~/Pictures/JuiceScreen/`) and returns its URL.
///
/// Layout:
///   <root>/2026-05-04/
///   <root>/2026-05-05/
public struct SaveDirectoryProvider: Sendable {

    public let rootDirectory: URL
    private let filenameGenerator: FilenameGenerator
    private let fileManager: FileManager

    public init(
        rootDirectory: URL,
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.filenameGenerator = filenameGenerator
        self.fileManager = fileManager
    }

    /// Returns the URL of the date-subfolder, creating it (and any missing intermediates) if needed.
    public func directory(for date: Date) throws -> URL {
        let folder = rootDirectory.appendingPathComponent(
            filenameGenerator.dateSubfolderName(for: date),
            isDirectory: true
        )
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SaveDirectoryProviderTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Shared/SaveDirectoryProvider.swift JuiceScreenTests/SaveDirectoryProviderTests.swift
git commit -m "feat(shared): SaveDirectoryProvider creates dated capture folders"
```

---

## Task 4: `PNGEncoder` + tests

**Files:**
- Create: `JuiceScreen/Capture/Image/PNGEncoder.swift`
- Create: `JuiceScreenTests/PNGEncoderTests.swift`

(Note: `Capture/Image/` doesn't exist yet — `xcodegen generate` will pick up the new folder once a file is added.)

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("PNGEncoder")
struct PNGEncoderTests {

    /// Builds a small solid-color NSImage for use as a fixture.
    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    @Test("Encodes a small solid-color image and returns PNG bytes starting with the PNG signature")
    func pngSignature() throws {
        let img = solidImage(width: 4, height: 4, color: .red)
        let data = try PNGEncoder.encode(img)
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let prefix = Array(data.prefix(signature.count))
        #expect(prefix == signature)
    }

    @Test("Round-trip: encode then decode produces an image with the same pixel dimensions")
    func roundTripDimensions() throws {
        let original = solidImage(width: 17, height: 11, color: .blue)
        let data = try PNGEncoder.encode(original)
        guard let rep = NSBitmapImageRep(data: data) else {
            Issue.record("Failed to decode PNG data back into NSBitmapImageRep")
            return
        }
        #expect(rep.pixelsWide == 17)
        #expect(rep.pixelsHigh == 11)
    }

    @Test("Throws on a zero-size image")
    func zeroSize() {
        let bad = NSImage(size: .zero)
        #expect(throws: PNGEncoderError.self) {
            _ = try PNGEncoder.encode(bad)
        }
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PNGEncoderTests 2>&1 | tail -8
```

Expected: compile failure (`PNGEncoder` undefined).

- [ ] **Step 3: Implement `PNGEncoder.swift`**

```swift
import AppKit
import Foundation

public enum PNGEncoderError: Error, Equatable {
    case zeroSize
    case noBitmapRepresentation
    case encodingFailed
}

/// Pure-function helper: NSImage → PNG Data. Used by `CaptureRecordWriter`
/// (production) and tests directly.
public enum PNGEncoder {

    public static func encode(_ image: NSImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw PNGEncoderError.zeroSize
        }

        // CGImage path produces a bitmap rep with deterministic pixel dimensions.
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw PNGEncoderError.noBitmapRepresentation
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw PNGEncoderError.encodingFailed
        }
        return data
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PNGEncoderTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/PNGEncoder.swift JuiceScreenTests/PNGEncoderTests.swift
git commit -m "feat(capture): PNGEncoder for NSImage → PNG Data"
```

---

## Task 5: `CaptureRecordWriter` + tests

**Files:**
- Create: `JuiceScreen/Capture/Image/CaptureRecordWriter.swift`
- Create: `JuiceScreenTests/CaptureRecordWriterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CaptureRecordWriter")
struct CaptureRecordWriterTests {

    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    private func makeTempRoot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Writes a PNG file at the expected path and returns a CaptureRecord")
    func writesPNG() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = CaptureRecordWriter(
            saveDirectory: SaveDirectoryProvider(rootDirectory: root),
            filenameGenerator: FilenameGenerator()
        )
        let img = solidImage(width: 32, height: 16, color: .green)
        let date = Date()

        let record = try writer.write(image: img, captureType: .region, capturedAt: date, sourceApp: "TestApp")

        #expect(FileManager.default.fileExists(atPath: record.fileURL.path))
        #expect(record.fileURL.pathExtension == "png")
        #expect(record.captureType == .region)
        #expect(record.pixelWidth == 32)
        #expect(record.pixelHeight == 16)
        #expect(record.sourceApp == "TestApp")
        #expect(record.capturedAt == date)
    }

    @Test("Filename matches FilenameGenerator output for the captured-at date")
    func filenameMatches() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = CaptureRecordWriter(
            saveDirectory: SaveDirectoryProvider(rootDirectory: root),
            filenameGenerator: FilenameGenerator()
        )
        let img = solidImage(width: 4, height: 4, color: .red)
        let date = Date()
        let expectedName = FilenameGenerator().filename(for: date, extension: "png")

        let record = try writer.write(image: img, captureType: .fullScreen, capturedAt: date, sourceApp: nil)

        #expect(record.fileURL.lastPathComponent == expectedName)
    }

    @Test("Handles two captures within the same second by appending a uniqueness suffix")
    func collisionHandling() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let writer = CaptureRecordWriter(
            saveDirectory: SaveDirectoryProvider(rootDirectory: root),
            filenameGenerator: FilenameGenerator()
        )
        let img = solidImage(width: 2, height: 2, color: .black)
        let date = Date()

        let r1 = try writer.write(image: img, captureType: .region, capturedAt: date, sourceApp: nil)
        let r2 = try writer.write(image: img, captureType: .region, capturedAt: date, sourceApp: nil)

        #expect(r1.fileURL != r2.fileURL)
        #expect(FileManager.default.fileExists(atPath: r1.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: r2.fileURL.path))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRecordWriterTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `CaptureRecordWriter.swift`**

```swift
import AppKit
import Foundation

/// Writes an `NSImage` to disk as PNG and returns the resulting `CaptureRecord`.
/// Combines `SaveDirectoryProvider` (creates the dated subfolder) and
/// `FilenameGenerator` (produces the filename). On filename collision, appends
/// `-1`, `-2`, … until a free name is found.
public struct CaptureRecordWriter {

    private let saveDirectory: SaveDirectoryProvider
    private let filenameGenerator: FilenameGenerator
    private let fileManager: FileManager

    public init(
        saveDirectory: SaveDirectoryProvider,
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        fileManager: FileManager = .default
    ) {
        self.saveDirectory = saveDirectory
        self.filenameGenerator = filenameGenerator
        self.fileManager = fileManager
    }

    public func write(
        image: NSImage,
        captureType: CaptureType,
        capturedAt: Date,
        sourceApp: String?
    ) throws -> CaptureRecord {
        let folder = try saveDirectory.directory(for: capturedAt)
        let baseName = filenameGenerator.filename(for: capturedAt, extension: "png")
        let url = uniqueURL(in: folder, preferredName: baseName)

        let data = try PNGEncoder.encode(image)
        try data.write(to: url, options: .atomic)

        // Pixel dimensions: prefer the actual encoded representation, fall back to image.size.
        let (pw, ph) = pixelDimensions(of: image)

        return CaptureRecord(
            fileURL: url,
            captureType: captureType,
            capturedAt: capturedAt,
            pixelWidth: pw,
            pixelHeight: ph,
            sourceApp: sourceApp
        )
    }

    // MARK: - Helpers

    private func uniqueURL(in folder: URL, preferredName: String) -> URL {
        let candidate = folder.appendingPathComponent(preferredName)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        let stem = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        var n = 1
        while true {
            let suffixed = "\(stem)-\(n).\(ext)"
            let url = folder.appendingPathComponent(suffixed)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            n += 1
        }
    }

    private func pixelDimensions(of image: NSImage) -> (Int, Int) {
        var rect = CGRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return (cg.width, cg.height)
        }
        return (Int(image.size.width), Int(image.size.height))
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRecordWriterTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/CaptureRecordWriter.swift JuiceScreenTests/CaptureRecordWriterTests.swift
git commit -m "feat(capture): CaptureRecordWriter writes PNG + returns CaptureRecord"
```

---

## Task 6: `CaptureError` + `CaptureEngine` protocol

**Files:**
- Create: `JuiceScreen/Capture/Image/CaptureError.swift`
- Create: `JuiceScreen/Capture/Image/CaptureEngine.swift`

(No tests — protocol + error enum.)

- [ ] **Step 1: Implement `CaptureError.swift`**

```swift
import Foundation

public enum CaptureError: Error, Equatable {
    /// The Screen Recording TCC permission has not been granted.
    case missingScreenRecordingPermission

    /// The user dismissed the picker / overlay (region picker or window picker)
    /// without selecting anything. Not a true error; UI surfaces ignore this.
    case userCancelled

    /// `SCShareableContent` returned an empty display list — extremely rare,
    /// usually means the system is in a transition state.
    case noDisplaysAvailable

    /// `SCScreenshotManager.captureImage` returned nil.
    case captureFailed(underlying: String)

    /// A coordinate outside any display was requested for a region capture.
    case regionOutsideDisplays

    /// File system write failed.
    case writeFailed(underlying: String)
}
```

- [ ] **Step 2: Implement `CaptureEngine.swift`**

```swift
import Foundation

/// Abstraction over image capture. Production impl is `CaptureEngineLive`
/// (uses ScreenCaptureKit). Test impl is `FakeCaptureEngine`.
///
/// All four methods are async — region/window pickers involve user interaction,
/// and ScreenCaptureKit itself is async.
public protocol CaptureEngine: Sendable {
    func captureRegion() async throws -> CaptureRecord
    func captureWindow() async throws -> CaptureRecord
    func captureFullScreen() async throws -> CaptureRecord
    func captureLastRegion() async throws -> CaptureRecord
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
git add JuiceScreen/Capture/Image/CaptureError.swift JuiceScreen/Capture/Image/CaptureEngine.swift
git commit -m "feat(capture): CaptureEngine protocol + CaptureError enum"
```

---

## Task 7: `FakeCaptureEngine` + tests

**Files:**
- Create: `JuiceScreen/Capture/Image/FakeCaptureEngine.swift`
- Create: `JuiceScreenTests/FakeCaptureEngineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeCaptureEngine")
struct FakeCaptureEngineTests {

    private func makeRecord(_ type: CaptureType) -> CaptureRecord {
        CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/fake.png"),
            captureType: type,
            capturedAt: Date(),
            pixelWidth: 100, pixelHeight: 100, sourceApp: nil
        )
    }

    @Test("Returns the configured record for each capture type")
    func returnsConfiguredRecord() async throws {
        let region = makeRecord(.region)
        let window = makeRecord(.window)
        let full = makeRecord(.fullScreen)
        let last = makeRecord(.lastRegion)

        let engine = FakeCaptureEngine()
        engine.recordsToReturn = [
            .region: .success(region),
            .window: .success(window),
            .fullScreen: .success(full),
            .lastRegion: .success(last),
        ]

        let r1 = try await engine.captureRegion()
        let r2 = try await engine.captureWindow()
        let r3 = try await engine.captureFullScreen()
        let r4 = try await engine.captureLastRegion()

        #expect(r1 == region)
        #expect(r2 == window)
        #expect(r3 == full)
        #expect(r4 == last)
    }

    @Test("Throws the configured error")
    func throwsConfiguredError() async {
        let engine = FakeCaptureEngine()
        engine.recordsToReturn[.region] = .failure(.userCancelled)

        await #expect(throws: CaptureError.self) {
            _ = try await engine.captureRegion()
        }
    }

    @Test("Records each call so tests can assert which capture types fired")
    func recordsCalls() async throws {
        let engine = FakeCaptureEngine()
        engine.recordsToReturn = [
            .region: .success(makeRecord(.region)),
            .window: .success(makeRecord(.window)),
        ]

        _ = try await engine.captureRegion()
        _ = try await engine.captureWindow()
        _ = try await engine.captureRegion()

        #expect(engine.calls == [.region, .window, .region])
    }

    @Test("Defaults to .userCancelled when no record is configured")
    func defaultBehavior() async {
        let engine = FakeCaptureEngine()
        await #expect(throws: CaptureError.self) {
            _ = try await engine.captureFullScreen()
        }
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeCaptureEngineTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `FakeCaptureEngine.swift`**

```swift
import Foundation

/// Test double for `CaptureEngine`. Configurable per-method outcomes,
/// records the order of calls.
public final class FakeCaptureEngine: CaptureEngine, @unchecked Sendable {

    public typealias Outcome = Result<CaptureRecord, CaptureError>

    private let lock = NSLock()
    public var recordsToReturn: [CaptureType: Outcome] = [:]
    public private(set) var calls: [CaptureType] = []

    public init() {}

    public func captureRegion() async throws -> CaptureRecord {
        try await dispatch(.region)
    }

    public func captureWindow() async throws -> CaptureRecord {
        try await dispatch(.window)
    }

    public func captureFullScreen() async throws -> CaptureRecord {
        try await dispatch(.fullScreen)
    }

    public func captureLastRegion() async throws -> CaptureRecord {
        try await dispatch(.lastRegion)
    }

    // MARK: - Helpers

    private func dispatch(_ type: CaptureType) async throws -> CaptureRecord {
        lock.lock()
        calls.append(type)
        let outcome = recordsToReturn[type] ?? .failure(.userCancelled)
        lock.unlock()
        switch outcome {
        case .success(let record): return record
        case .failure(let error):  throw error
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeCaptureEngineTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/FakeCaptureEngine.swift JuiceScreenTests/FakeCaptureEngineTests.swift
git commit -m "feat(capture): FakeCaptureEngine for tests + previews"
```

---

## Task 8: ScreenCaptureKit helpers (`SCShareableContent` async wrapper)

**Files:**
- Create: `JuiceScreen/Capture/Image/ScreenCaptureKitHelpers.swift`

(No automated tests — wraps system APIs that need real screen recording permission.)

- [ ] **Step 1: Implement `ScreenCaptureKitHelpers.swift`**

```swift
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Thin async wrappers around ScreenCaptureKit so the rest of the capture
/// engine can `await` natural-looking calls.
public enum ScreenCaptureKitHelpers {

    /// Returns the current shareable content (displays + windows).
    /// Throws `CaptureError.missingScreenRecordingPermission` if the user has not granted access.
    public static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            // ScreenCaptureKit returns a permission error when TCC is not granted.
            // Map it to our domain error so callers can render a friendly UI.
            throw CaptureError.missingScreenRecordingPermission
        }
    }

    /// Captures a one-shot image of the supplied filter at the supplied configuration.
    public static func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed(underlying: "\(error)")
        }
    }

    /// Builds an `SCStreamConfiguration` sized for the supplied display.
    /// Configures pixel format BGRA, scales for Retina (using `pixelDensity`).
    public static func configuration(for display: SCDisplay, pixelDensity: Int = 2) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        cfg.width = display.width * pixelDensity
        cfg.height = display.height * pixelDensity
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        return cfg
    }

    /// Builds an `SCStreamConfiguration` sized for a region of the supplied display.
    /// `regionInPoints` is in points (scaled up by `pixelDensity` for the output).
    public static func configuration(
        for display: SCDisplay,
        regionInPoints: CGRect,
        pixelDensity: Int = 2
    ) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        cfg.width = Int(regionInPoints.width) * pixelDensity
        cfg.height = Int(regionInPoints.height) * pixelDensity
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.sourceRect = regionInPoints
        return cfg
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
git add JuiceScreen/Capture/Image/ScreenCaptureKitHelpers.swift
git commit -m "feat(capture): SCShareableContent + SCScreenshotManager async wrappers"
```

---

## Task 9: `CaptureEngineLive` skeleton + full-screen single-display capture

**Files:**
- Create: `JuiceScreen/Capture/Image/CaptureEngineLive.swift`

(No automated test — exercises real ScreenCaptureKit. Manual smoke test in Task 19.)

- [ ] **Step 1: Implement `CaptureEngineLive.swift`**

```swift
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Production `CaptureEngine` using ScreenCaptureKit + AppKit overlays for the picker.
/// Region picker, window picker, and multi-display picker land in subsequent tasks.
@MainActor
public final class CaptureEngineLive: CaptureEngine {

    private let writer: CaptureRecordWriter
    private let log = AppLog.logger(category: "CaptureEngineLive")

    public init(writer: CaptureRecordWriter) {
        self.writer = writer
    }

    nonisolated public func captureRegion() async throws -> CaptureRecord {
        // Implemented in Task 15
        throw CaptureError.captureFailed(underlying: "captureRegion not yet implemented")
    }

    nonisolated public func captureWindow() async throws -> CaptureRecord {
        // Implemented in Task 10
        throw CaptureError.captureFailed(underlying: "captureWindow not yet implemented")
    }

    nonisolated public func captureFullScreen() async throws -> CaptureRecord {
        try await captureFullScreenInternal()
    }

    nonisolated public func captureLastRegion() async throws -> CaptureRecord {
        // Implemented in Task 17
        throw CaptureError.captureFailed(underlying: "captureLastRegion not yet implemented")
    }

    // MARK: - Full screen (single display path; multi-display picker added in Task 11)

    private func captureFullScreenInternal() async throws -> CaptureRecord {
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let primary = content.displays.first else {
            throw CaptureError.noDisplaysAvailable
        }

        // Filter excludes our own app's windows so we never capture the menu we may have just dismissed.
        let filter = SCContentFilter(
            display: primary,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: primary)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))

        return try writer.write(
            image: image,
            captureType: .fullScreen,
            capturedAt: Date(),
            sourceApp: nil
        )
    }

    /// Returns this app's `SCRunningApplication`s so we can exclude them from the capture filter.
    nonisolated private func ownApplications() async throws -> [SCRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bks-lab.juicescreen"
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        return content.applications.filter { $0.bundleIdentifier == bundleID }
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
git add JuiceScreen/Capture/Image/CaptureEngineLive.swift
git commit -m "feat(capture): CaptureEngineLive skeleton + single-display full-screen capture"
```

---

## Task 10: `WindowPickerService` + window capture

**Files:**
- Create: `JuiceScreen/Capture/Image/WindowPickerService.swift`
- Modify: `JuiceScreen/Capture/Image/CaptureEngineLive.swift` — replace the window stub with a real implementation

- [ ] **Step 1: Implement `WindowPickerService.swift`**

```swift
import Foundation
import ScreenCaptureKit

/// Wraps `SCContentSharingPicker` (macOS 14+) — the Apple-provided window picker.
/// The picker's user interaction is asynchronous; we bridge it to async/await
/// via `withCheckedContinuation`.
@MainActor
public final class WindowPickerService: NSObject, SCContentSharingPickerObserver {

    private var continuation: CheckedContinuation<SCContentFilter, Error>?
    private var pickerStream: SCStream?

    public override init() {
        super.init()
    }

    /// Presents the window picker and returns the user-selected `SCContentFilter`.
    /// Throws `CaptureError.userCancelled` if the user dismisses without picking.
    public func pickWindow() async throws -> SCContentFilter {
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        defer { picker.remove(self) }

        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.excludedWindowIDs = []
        picker.defaultConfiguration = configuration
        picker.isActive = true

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SCContentFilter, Error>) in
            self.continuation = cont
            picker.present()
        }
    }

    // MARK: - SCContentSharingPickerObserver

    nonisolated public func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            picker.isActive = false
            continuation?.resume(returning: filter)
            continuation = nil
        }
    }

    nonisolated public func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            picker.isActive = false
            continuation?.resume(throwing: CaptureError.userCancelled)
            continuation = nil
        }
    }

    nonisolated public func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in
            continuation?.resume(throwing: CaptureError.captureFailed(underlying: "\(error)"))
            continuation = nil
        }
    }
}
```

- [ ] **Step 2: Modify `CaptureEngineLive.swift` — replace the captureWindow stub**

In `JuiceScreen/Capture/Image/CaptureEngineLive.swift`, replace the body of `captureWindow()` with a call into the new helper, and add the helper plus a stored `WindowPickerService`. The full updated class:

```swift
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
public final class CaptureEngineLive: CaptureEngine {

    private let writer: CaptureRecordWriter
    private let windowPicker: WindowPickerService
    private let log = AppLog.logger(category: "CaptureEngineLive")

    public init(writer: CaptureRecordWriter) {
        self.writer = writer
        self.windowPicker = WindowPickerService()
    }

    nonisolated public func captureRegion() async throws -> CaptureRecord {
        // Implemented in Task 15
        throw CaptureError.captureFailed(underlying: "captureRegion not yet implemented")
    }

    nonisolated public func captureWindow() async throws -> CaptureRecord {
        try await captureWindowInternal()
    }

    nonisolated public func captureFullScreen() async throws -> CaptureRecord {
        try await captureFullScreenInternal()
    }

    nonisolated public func captureLastRegion() async throws -> CaptureRecord {
        // Implemented in Task 17
        throw CaptureError.captureFailed(underlying: "captureLastRegion not yet implemented")
    }

    // MARK: - Full screen

    private func captureFullScreenInternal() async throws -> CaptureRecord {
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let primary = content.displays.first else {
            throw CaptureError.noDisplaysAvailable
        }
        let filter = SCContentFilter(
            display: primary,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: primary)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .fullScreen, sourceApp: nil)
    }

    // MARK: - Window

    private func captureWindowInternal() async throws -> CaptureRecord {
        let filter = try await MainActor.run { try await windowPicker.pickWindow() }
        let cfg = SCStreamConfiguration()
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        // The picker's filter already encodes which window to capture; SC handles sizing.
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .window, sourceApp: nil)
    }

    // MARK: - Helpers

    private func persist(cg: CGImage, captureType: CaptureType, sourceApp: String?) async throws -> CaptureRecord {
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        return try await MainActor.run {
            try writer.write(
                image: image,
                captureType: captureType,
                capturedAt: Date(),
                sourceApp: sourceApp
            )
        }
    }

    nonisolated private func ownApplications() async throws -> [SCRunningApplication] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bks-lab.juicescreen"
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        return content.applications.filter { $0.bundleIdentifier == bundleID }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (Some Swift 6 concurrency warnings on the picker observer protocol bridge are acceptable as long as it compiles.)

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/Capture/Image/WindowPickerService.swift JuiceScreen/Capture/Image/CaptureEngineLive.swift
git commit -m "feat(capture): window capture via SCContentSharingPicker"
```

---

## Task 11: Multi-display picker (`DisplayPickerView` + `DisplayPickerWindow`) + integration

**Files:**
- Create: `JuiceScreen/Capture/Image/DisplayPickerView.swift`
- Create: `JuiceScreen/Capture/Image/DisplayPickerWindow.swift`
- Modify: `JuiceScreen/Capture/Image/CaptureEngineLive.swift` — wrap full-screen in display picker if 2+ displays

- [ ] **Step 1: Implement `DisplayPickerView.swift`**

```swift
import ScreenCaptureKit
import SwiftUI

/// Minimal SwiftUI picker shown when the user has 2+ displays attached.
/// The display rows render their dimensions ("3024 × 1964") and a numeric label.
struct DisplayPickerView: View {

    let displays: [SCDisplay]
    let onPick: (SCDisplay) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a display")
                .font(.title3).fontWeight(.semibold)

            ForEach(Array(displays.enumerated()), id: \.element.displayID) { (idx, display) in
                Button {
                    onPick(display)
                } label: {
                    HStack {
                        Image(systemName: "display")
                        Text("Display \(idx + 1)")
                        Spacer()
                        Text("\(display.width) × \(display.height)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(8)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: Implement `DisplayPickerWindow.swift`**

```swift
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Shows the display picker as a modal NSWindow and bridges its result to async/await.
@MainActor
enum DisplayPickerWindow {

    static func pick(from displays: [SCDisplay]) async throws -> SCDisplay {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SCDisplay, Error>) in
            var window: NSWindow!
            let onPick: (SCDisplay) -> Void = { display in
                window.close()
                cont.resume(returning: display)
            }
            let onCancel: () -> Void = {
                window.close()
                cont.resume(throwing: CaptureError.userCancelled)
            }
            let view = DisplayPickerView(displays: displays, onPick: onPick, onCancel: onCancel)

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "JuiceScreen — Capture Full Screen"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

- [ ] **Step 3: Modify `captureFullScreenInternal` to use the picker for 2+ displays**

In `JuiceScreen/Capture/Image/CaptureEngineLive.swift`, replace `captureFullScreenInternal()` with:

```swift
    private func captureFullScreenInternal() async throws -> CaptureRecord {
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }

        let display: SCDisplay
        if content.displays.count == 1 {
            display = content.displays[0]
        } else {
            display = try await MainActor.run { try await DisplayPickerWindow.pick(from: content.displays) }
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: display)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .fullScreen, sourceApp: nil)
    }
```

- [ ] **Step 4: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/DisplayPickerView.swift JuiceScreen/Capture/Image/DisplayPickerWindow.swift JuiceScreen/Capture/Image/CaptureEngineLive.swift
git commit -m "feat(capture): multi-display picker for full-screen capture (2+ displays only)"
```

---

## Task 12: `RegionSelection` value type + tests

**Files:**
- Create: `JuiceScreen/Capture/Image/RegionSelection.swift`
- Create: `JuiceScreenTests/RegionSelectionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("RegionSelection")
struct RegionSelectionTests {

    @Test("Normalizes drag from top-left to bottom-right")
    func topLeftToBottomRight() {
        let s = RegionSelection(start: CGPoint(x: 10, y: 20), current: CGPoint(x: 110, y: 220))
        #expect(s.normalized == CGRect(x: 10, y: 20, width: 100, height: 200))
    }

    @Test("Normalizes drag from bottom-right to top-left (negative width/height)")
    func bottomRightToTopLeft() {
        let s = RegionSelection(start: CGPoint(x: 110, y: 220), current: CGPoint(x: 10, y: 20))
        #expect(s.normalized == CGRect(x: 10, y: 20, width: 100, height: 200))
    }

    @Test("Zero-area when start == current")
    func zeroArea() {
        let s = RegionSelection(start: CGPoint(x: 50, y: 50), current: CGPoint(x: 50, y: 50))
        #expect(s.normalized == CGRect(x: 50, y: 50, width: 0, height: 0))
    }

    @Test("isUsable false for zero-area selection")
    func zeroNotUsable() {
        let s = RegionSelection(start: .zero, current: .zero)
        #expect(s.isUsable == false)
    }

    @Test("isUsable true for >= 1x1 selection")
    func oneByOneUsable() {
        let s = RegionSelection(start: .zero, current: CGPoint(x: 1, y: 1))
        #expect(s.isUsable == true)
    }

    @Test("Nudging by an offset translates start and current equally")
    func nudge() {
        let s = RegionSelection(start: CGPoint(x: 10, y: 10), current: CGPoint(x: 30, y: 50))
        let n = s.nudged(by: CGSize(width: 5, height: -3))
        #expect(n.normalized == CGRect(x: 15, y: 7, width: 20, height: 40))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/RegionSelectionTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `RegionSelection.swift`**

```swift
import CoreGraphics

/// Pure value type representing an in-progress region selection on the picker overlay.
/// Coordinates are in the overlay window's coordinate space (which spans all displays).
public struct RegionSelection: Equatable, Sendable {

    public var start: CGPoint
    public var current: CGPoint

    public init(start: CGPoint, current: CGPoint) {
        self.start = start
        self.current = current
    }

    public var normalized: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    public var isUsable: Bool {
        normalized.width >= 1 && normalized.height >= 1
    }

    /// Returns a new selection translated by `offset`. Used for arrow-key nudging.
    public func nudged(by offset: CGSize) -> RegionSelection {
        RegionSelection(
            start: CGPoint(x: start.x + offset.width, y: start.y + offset.height),
            current: CGPoint(x: current.x + offset.width, y: current.y + offset.height)
        )
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/RegionSelectionTests 2>&1 | tail -10
```

Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/RegionSelection.swift JuiceScreenTests/RegionSelectionTests.swift
git commit -m "feat(capture): RegionSelection value type for in-progress drag"
```

---

## Task 13: `RegionPickerView` (SwiftUI overlay rendering)

**Files:**
- Create: `JuiceScreen/Capture/Image/RegionPickerView.swift`

(No tests — visual SwiftUI rendering. Manual smoke tested as part of region capture in Task 19.)

- [ ] **Step 1: Implement `RegionPickerView.swift`**

```swift
import SwiftUI

/// Overlay rendering: dim everything by 35% black, punch a clear hole over
/// the current selection, draw a 1pt white stroke around the selection,
/// and show the live pixel dimensions next to the cursor.
struct RegionPickerView: View {

    let canvasSize: CGSize
    let selection: RegionSelection?
    let cursor: CGPoint?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .mask(maskPath)

            if let rect = selection?.normalized {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            if let cursor, let rect = selection?.normalized, rect.width > 0, rect.height > 0 {
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: cursor.x + 16, y: cursor.y + 16)
            }
        }
    }

    /// A mask that darkens everything EXCEPT the selection rectangle.
    /// Implemented as the canvas with an even-odd-filled rectangle removed.
    @ViewBuilder
    private var maskPath: some View {
        if let rect = selection?.normalized, rect.width > 0, rect.height > 0 {
            ZStack {
                Color.white
                Color.black
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            Color.white
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
git add JuiceScreen/Capture/Image/RegionPickerView.swift
git commit -m "feat(capture): RegionPickerView for dim + selection + dimensions overlay"
```

---

## Task 14: `RegionPickerOverlayWindow` + `RegionPickerController`

**Files:**
- Create: `JuiceScreen/Capture/Image/RegionPickerOverlayWindow.swift`
- Create: `JuiceScreen/Capture/Image/RegionPickerController.swift`

(No automated tests — `NSWindow` mouse/keyboard events need a running app.)

- [ ] **Step 1: Implement `RegionPickerOverlayWindow.swift`**

```swift
import AppKit

/// Borderless transparent NSWindow that covers all displays. Captures mouse
/// and keyboard events so the user can drag a selection rectangle.
final class RegionPickerOverlayWindow: NSWindow {

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver       // above normal windows + menu bar
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.hasShadow = false
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

- [ ] **Step 2: Implement `RegionPickerController.swift`**

```swift
import AppKit
import SwiftUI

/// Orchestrates the region picker overlay: shows a transparent NSWindow over
/// every display, lets the user drag a rectangle, returns the selected CGRect
/// (in global screen coordinates) or throws `CaptureError.userCancelled`.
@MainActor
public final class RegionPickerController {

    private var window: RegionPickerOverlayWindow?
    private var localMonitor: Any?
    private var continuation: CheckedContinuation<CGRect, Error>?
    private var selection: RegionSelection?
    private var cursor: CGPoint?

    public init() {}

    /// Returns the selected rectangle in global screen coordinates (origin at lower-left
    /// of the unioned screen frame, matching AppKit's coordinate convention).
    public func pickRegion() async throws -> CGRect {
        // Compute the union frame of all screens — this is our overlay's bounds.
        let union = NSScreen.screens.reduce(NSRect.zero) { acc, scr in acc.union(scr.frame) }
        guard union.width > 0, union.height > 0 else {
            throw CaptureError.noDisplaysAvailable
        }

        let win = RegionPickerOverlayWindow(frame: union)
        self.window = win
        rebuildContentView()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installEventMonitor()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGRect, Error>) in
            self.continuation = cont
        }
    }

    // MARK: - Event monitor

    private func installEventMonitor() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeEventMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        let pointInWindow = window.contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow

        switch event.type {
        case .mouseMoved:
            cursor = pointInWindow
            rebuildContentView()
            return event

        case .leftMouseDown:
            selection = RegionSelection(start: pointInWindow, current: pointInWindow)
            cursor = pointInWindow
            rebuildContentView()
            return nil

        case .leftMouseDragged:
            if var s = selection {
                s.current = pointInWindow
                selection = s
            }
            cursor = pointInWindow
            rebuildContentView()
            return nil

        case .leftMouseUp:
            if let s = selection, s.isUsable {
                let rect = windowRectToScreenRect(s.normalized)
                finish(.success(rect))
            } else {
                finish(.failure(.userCancelled))
            }
            return nil

        case .keyDown:
            switch event.keyCode {
            case 53: // Esc
                finish(.failure(.userCancelled))
                return nil
            case 36, 76: // Return, KP-Enter
                if let s = selection, s.isUsable {
                    finish(.success(windowRectToScreenRect(s.normalized)))
                } else {
                    finish(.failure(.userCancelled))
                }
                return nil
            case 123, 124, 125, 126: // Left, Right, Down, Up
                if var s = selection {
                    let stepped: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                    let dx: CGFloat = event.keyCode == 123 ? -stepped : event.keyCode == 124 ? stepped : 0
                    let dy: CGFloat = event.keyCode == 125 ? -stepped : event.keyCode == 126 ? stepped : 0
                    s = s.nudged(by: CGSize(width: dx, height: dy))
                    selection = s
                    rebuildContentView()
                }
                return nil
            default:
                return event
            }

        default:
            return event
        }
    }

    // MARK: - Coordinate conversion

    /// Converts a rect in the overlay window's local coordinates to global screen coordinates
    /// (the same coordinate space that ScreenCaptureKit's `sourceRect` expects, when scoped to a display).
    private func windowRectToScreenRect(_ windowRect: CGRect) -> CGRect {
        guard let window else { return windowRect }
        let originInScreen = window.convertPoint(toScreen: windowRect.origin)
        return CGRect(origin: originInScreen, size: windowRect.size)
    }

    private func rebuildContentView() {
        guard let window else { return }
        let view = RegionPickerView(
            canvasSize: window.frame.size,
            selection: selection,
            cursor: cursor
        )
        window.contentView = NSHostingView(rootView: view)
    }

    private func finish(_ outcome: Result<CGRect, CaptureError>) {
        removeEventMonitor()
        window?.orderOut(nil)
        window = nil
        selection = nil
        cursor = nil
        switch outcome {
        case .success(let rect): continuation?.resume(returning: rect)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        continuation = nil
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
git add JuiceScreen/Capture/Image/RegionPickerOverlayWindow.swift JuiceScreen/Capture/Image/RegionPickerController.swift
git commit -m "feat(capture): RegionPickerController + transparent overlay window"
```

---

## Task 15: Wire region capture into `CaptureEngineLive`

**Files:**
- Modify: `JuiceScreen/Capture/Image/CaptureEngineLive.swift`

- [ ] **Step 1: Add `regionPicker` property and replace `captureRegion` stub**

In `JuiceScreen/Capture/Image/CaptureEngineLive.swift`:

1. In the property block at the top of the class, add `private let regionPicker: RegionPickerController` (after `windowPicker`).
2. In `init`, add `self.regionPicker = RegionPickerController()` (after `windowPicker`).
3. Replace `captureRegion()` body (currently throws "not yet implemented") with `try await captureRegionInternal()`.
4. Add the implementation method:

```swift
    private func captureRegionInternal() async throws -> CaptureRecord {
        let regionInScreen = try await MainActor.run { try await regionPicker.pickRegion() }

        // Find which display contains the selection's origin (or center).
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let display = displayContaining(point: CGPoint(x: regionInScreen.midX, y: regionInScreen.midY),
                                              in: content) else {
            throw CaptureError.regionOutsideDisplays
        }

        // Convert global-screen coordinates to display-local coordinates for sourceRect.
        let displayFrame = displayGlobalFrame(display)
        let displayLocal = CGRect(
            x: regionInScreen.minX - displayFrame.minX,
            y: regionInScreen.minY - displayFrame.minY,
            width: regionInScreen.width,
            height: regionInScreen.height
        )

        let filter = SCContentFilter(
            display: display,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: display, regionInPoints: displayLocal)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .region, sourceApp: nil)
    }

    /// Returns the SCDisplay whose global frame contains `point`, or nil.
    private func displayContaining(point: CGPoint, in content: SCShareableContent) -> SCDisplay? {
        return content.displays.first { display in
            displayGlobalFrame(display).contains(point)
        }
    }

    /// SCDisplay frames are in display-local coordinates; combine with `frame` from the matching NSScreen
    /// to get global screen coordinates. We match by `displayID` (CGDirectDisplayID).
    private func displayGlobalFrame(_ display: SCDisplay) -> CGRect {
        if let nsScreen = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) {
            return nsScreen.frame
        }
        return CGRect(x: 0, y: 0, width: display.width, height: display.height)
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
git add JuiceScreen/Capture/Image/CaptureEngineLive.swift
git commit -m "feat(capture): wire region picker overlay into CaptureEngineLive.captureRegion"
```

---

## Task 16: `Preferences.lastRegion` field + `PreferencesStore` extension + tests

**Files:**
- Modify: `JuiceScreen/Preferences/Preferences.swift` — add `lastRegion: CGRect?`
- Modify: `JuiceScreen/Preferences/PreferencesStore.swift` — load/save lastRegion
- Modify: `JuiceScreenTests/PreferencesStoreTests.swift` — add round-trip test

- [ ] **Step 1: Add the failing test**

Append to the existing `JuiceScreenTests/PreferencesStoreTests.swift` `@Suite("PreferencesStore")` body:

```swift
    @Test("lastRegion round-trips")
    func lastRegionRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        #expect(prefs.lastRegion == nil)

        prefs.lastRegion = CGRect(x: 100, y: 200, width: 300, height: 400)
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.lastRegion == CGRect(x: 100, y: 200, width: 300, height: 400))
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PreferencesStoreTests 2>&1 | tail -8
```

Expected: compile failure (`Preferences.lastRegion` is undefined).

- [ ] **Step 3: Add `lastRegion` to `Preferences`**

Edit `JuiceScreen/Preferences/Preferences.swift`:

1. In the `Preferences` struct, add `public var lastRegion: CGRect?` after `hotkeysPaused`.
2. In `Preferences.defaults`, add `lastRegion: nil` at the end of the initializer call (matching the parameter order).
3. Update the `init` parameter list to include `lastRegion: CGRect?` after `hotkeysPaused: Bool` and assign it.

The full updated struct:

```swift
public struct Preferences: Equatable, Sendable {

    public var firstRunComplete: Bool
    public var startAtLogin: Bool

    public var saveDirectory: URL
    public var defaultStillFormat: StillImageFormat
    public var jpegQuality: Double

    public var captureRegionHotkey: Hotkey
    public var captureWindowHotkey: Hotkey
    public var captureFullScreenHotkey: Hotkey
    public var captureLastRegionHotkey: Hotkey
    public var recordScreenHotkey: Hotkey
    public var openLibraryHotkey: Hotkey

    public var hotkeysPaused: Bool

    public var lastRegion: CGRect?

    public init(
        firstRunComplete: Bool,
        startAtLogin: Bool,
        saveDirectory: URL,
        defaultStillFormat: StillImageFormat,
        jpegQuality: Double,
        captureRegionHotkey: Hotkey,
        captureWindowHotkey: Hotkey,
        captureFullScreenHotkey: Hotkey,
        captureLastRegionHotkey: Hotkey,
        recordScreenHotkey: Hotkey,
        openLibraryHotkey: Hotkey,
        hotkeysPaused: Bool,
        lastRegion: CGRect? = nil
    ) {
        self.firstRunComplete = firstRunComplete
        self.startAtLogin = startAtLogin
        self.saveDirectory = saveDirectory
        self.defaultStillFormat = defaultStillFormat
        self.jpegQuality = jpegQuality
        self.captureRegionHotkey = captureRegionHotkey
        self.captureWindowHotkey = captureWindowHotkey
        self.captureFullScreenHotkey = captureFullScreenHotkey
        self.captureLastRegionHotkey = captureLastRegionHotkey
        self.recordScreenHotkey = recordScreenHotkey
        self.openLibraryHotkey = openLibraryHotkey
        self.hotkeysPaused = hotkeysPaused
        self.lastRegion = lastRegion
    }

    public static let defaults: Preferences = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        let saveDir = pictures.appendingPathComponent("JuiceScreen", isDirectory: true)

        return Preferences(
            firstRunComplete: false,
            startAtLogin: false,
            saveDirectory: saveDir,
            defaultStillFormat: .png,
            jpegQuality: 0.9,
            captureRegionHotkey:     Hotkey(keyCode: 21, modifiers: [.command, .shift]),
            captureWindowHotkey:     Hotkey(keyCode: 19, modifiers: [.command, .shift]),
            captureFullScreenHotkey: Hotkey(keyCode: 20, modifiers: [.command, .shift]),
            captureLastRegionHotkey: Hotkey(keyCode: 15, modifiers: [.command, .shift]),
            recordScreenHotkey:      Hotkey(keyCode: 23, modifiers: [.command, .shift]),
            openLibraryHotkey:       Hotkey(keyCode: 37, modifiers: [.command, .shift]),
            hotkeysPaused: false,
            lastRegion: nil
        )
    }()
}
```

- [ ] **Step 4: Add `lastRegion` persistence to `PreferencesStore`**

Edit `JuiceScreen/Preferences/PreferencesStore.swift`:

1. Add a `Key.lastRegion = "lastRegion"` constant.
2. In `load()`, add `lastRegion: loadRect(Key.lastRegion)` at the end of the `Preferences(...)` call.
3. In `save(_:)`, add a `saveRect(prefs.lastRegion, key: Key.lastRegion)` call.
4. Add helper functions:

```swift
    private func loadRect(_ key: String) -> CGRect? {
        guard let dict = defaults.dictionary(forKey: key) as? [String: Double] else { return nil }
        guard let x = dict["x"], let y = dict["y"],
              let w = dict["w"], let h = dict["h"] else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func saveRect(_ rect: CGRect?, key: String) {
        guard let rect else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set([
            "x": Double(rect.origin.x),
            "y": Double(rect.origin.y),
            "w": Double(rect.size.width),
            "h": Double(rect.size.height)
        ], forKey: key)
    }
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PreferencesStoreTests 2>&1 | tail -10
```

Expected: 5/5 (the existing 4 + the new `lastRegionRoundTrip` test) all pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Preferences JuiceScreenTests/PreferencesStoreTests.swift
git commit -m "feat(preferences): add lastRegion: CGRect? for re-capture-same-area flow"
```

---

## Task 17: Wire last-region capture into `CaptureEngineLive`

**Files:**
- Modify: `JuiceScreen/Capture/Image/CaptureEngineLive.swift` — replace lastRegion stub
- Also: `captureRegion` should write the selected region to `PreferencesStore` after a successful capture

- [ ] **Step 1: Make `CaptureEngineLive` aware of `PreferencesStore`**

Add a `PreferencesStore` property and an `init` parameter:

In `JuiceScreen/Capture/Image/CaptureEngineLive.swift`:

```swift
    private let preferences: PreferencesStore

    public init(writer: CaptureRecordWriter, preferences: PreferencesStore) {
        self.writer = writer
        self.preferences = preferences
        self.windowPicker = WindowPickerService()
        self.regionPicker = RegionPickerController()
    }
```

(This is a breaking change to the init signature. The only caller is `AppDelegate` — Task 18 will update it.)

- [ ] **Step 2: Persist `lastRegion` after a successful region capture**

In `captureRegionInternal()`, after the `let cg = try await ScreenCaptureKitHelpers.captureImage(...)` line and before the `return try await persist(...)`, add:

```swift
        // Remember this region for "Capture Last Region".
        await MainActor.run {
            var prefs = preferences.load()
            prefs.lastRegion = regionInScreen
            preferences.save(prefs)
        }
```

- [ ] **Step 3: Replace `captureLastRegion` stub**

Replace:

```swift
    nonisolated public func captureLastRegion() async throws -> CaptureRecord {
        throw CaptureError.captureFailed(underlying: "captureLastRegion not yet implemented")
    }
```

with:

```swift
    nonisolated public func captureLastRegion() async throws -> CaptureRecord {
        try await captureLastRegionInternal()
    }

    private func captureLastRegionInternal() async throws -> CaptureRecord {
        let region = await MainActor.run { preferences.load().lastRegion }
        guard let regionInScreen = region else {
            // No prior region — fall back to triggering the picker (same as captureRegion).
            return try await captureRegionInternal()
        }

        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let display = displayContaining(point: CGPoint(x: regionInScreen.midX, y: regionInScreen.midY),
                                              in: content) else {
            throw CaptureError.regionOutsideDisplays
        }
        let displayFrame = displayGlobalFrame(display)
        let displayLocal = CGRect(
            x: regionInScreen.minX - displayFrame.minX,
            y: regionInScreen.minY - displayFrame.minY,
            width: regionInScreen.width,
            height: regionInScreen.height
        )

        let filter = SCContentFilter(
            display: display,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: display, regionInPoints: displayLocal)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return try await persist(cg: cg, captureType: .lastRegion, sourceApp: nil)
    }
```

- [ ] **Step 4: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -8
```

Expected: build fails — `AppDelegate` instantiates `CaptureEngineLive(writer:)` without the new `preferences:` parameter. Note this expected failure; Task 18 fixes it.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/CaptureEngineLive.swift
git commit -m "feat(capture): captureLastRegion + persist lastRegion after captureRegion"
```

(Build is intentionally broken until Task 18 wires `AppDelegate`. The commit captures the engine work cleanly; the integration follows immediately.)

---

## Task 18: Wire `CaptureEngine` into `AppDelegate`

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift` — replace 4 `todoLog` call sites + instantiate engine

- [ ] **Step 1: Replace `AppDelegate.swift` body**

The full updated `AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let log = AppLog.logger(category: "App")

    private let permissions: PermissionsService = PermissionsServiceLive()
    private let preferences = PreferencesStore()
    private let hotkeyService = HotkeyService()

    private lazy var captureEngine: CaptureEngine = {
        let prefs = preferences.load()
        let saveDir = SaveDirectoryProvider(rootDirectory: prefs.saveDirectory)
        let writer = CaptureRecordWriter(saveDirectory: saveDir)
        return CaptureEngineLive(writer: writer, preferences: preferences)
    }()

    private var menuBar: MenuBarController?
    private var firstRun: FirstRunCoordinator?
    private var activationPolicy: ActivationPolicyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("JuiceScreen launching")

        activationPolicy = ActivationPolicyController()

        let actions = MenuBarActions(
            captureRegion:     { [weak self] in self?.fireCapture(.region) },
            captureWindow:     { [weak self] in self?.fireCapture(.window) },
            captureFullScreen: { [weak self] in self?.fireCapture(.fullScreen) },
            captureLastRegion: { [weak self] in self?.fireCapture(.lastRegion) },
            recordScreen:      { [weak self] in self?.todoLog("recordScreen") },
            openLibrary:       { [weak self] in self?.todoLog("openLibrary") },
            openPreferences:   { SettingsWindow.show() },
            quit:              { NSApp.terminate(nil) }
        )
        let prefs = preferences.load()
        menuBar = MenuBarController(prefs: prefs, actions: actions)

        registerHotkeys(prefs: prefs, actions: actions)

        if ProcessInfo.processInfo.environment["JUICESCREEN_UI_TEST_MODE"] == nil {
            let coordinator = FirstRunCoordinator(permissions: permissions, preferences: preferences)
            firstRun = coordinator
            coordinator.start()
            FirstRunWindow.showIfNeeded(coordinator: coordinator)
        }
    }

    private func registerHotkeys(prefs: Preferences, actions: MenuBarActions) {
        hotkeyService.register(prefs.captureRegionHotkey,     for: .captureRegion)     { actions.captureRegion() }
        hotkeyService.register(prefs.captureWindowHotkey,     for: .captureWindow)     { actions.captureWindow() }
        hotkeyService.register(prefs.captureFullScreenHotkey, for: .captureFullScreen) { actions.captureFullScreen() }
        hotkeyService.register(prefs.captureLastRegionHotkey, for: .captureLastRegion) { actions.captureLastRegion() }
        hotkeyService.register(prefs.recordScreenHotkey,      for: .recordScreen)      { actions.recordScreen() }
        hotkeyService.register(prefs.openLibraryHotkey,       for: .openLibrary)       { actions.openLibrary() }
    }

    private func fireCapture(_ type: CaptureType) {
        let engine = captureEngine
        Task { @MainActor in
            do {
                let record: CaptureRecord
                switch type {
                case .region:      record = try await engine.captureRegion()
                case .window:      record = try await engine.captureWindow()
                case .fullScreen:  record = try await engine.captureFullScreen()
                case .lastRegion:  record = try await engine.captureLastRegion()
                }
                log.info("Captured \(String(describing: record.captureType)) → \(record.fileURL.path)")
            } catch CaptureError.userCancelled {
                log.info("Capture cancelled by user")
            } catch CaptureError.missingScreenRecordingPermission {
                log.error("Capture failed: Screen Recording permission missing")
                permissions.openSettings(for: .screenRecording)
            } catch {
                log.error("Capture failed: \(String(describing: error))")
            }
        }
    }

    private func todoLog(_ what: String) {
        log.info("TODO: \(what) action — implemented in a later plan")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: `** BUILD SUCCEEDED **` and all unit tests still pass.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): wire CaptureEngine into AppDelegate (region/window/full/last)"
```

---

## Task 19: Manual smoke test + bump VERSION + tag v0.2.0

**Files:**
- Modify: `VERSION` — bump to `0.2.0`
- Modify: `project.yml` — bump `MARKETING_VERSION` to `0.2.0`

- [ ] **Step 1: Bump version files**

Update `VERSION` to:

```
0.2.0
```

In `project.yml`, change `MARKETING_VERSION: "0.1.0"` to `MARKETING_VERSION: "0.2.0"`.

- [ ] **Step 2: Clean build and run all unit tests**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
rm -rf ~/Library/Developer/Xcode/DerivedData/JuiceScreen-*
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: `** BUILD SUCCEEDED **` and all tests pass. Total test count should be the previous 26 plus the new tests added in Plan 2: CaptureRecord (5) + FilenameGenerator (4) + SaveDirectoryProvider (3) + PNGEncoder (3) + CaptureRecordWriter (3) + FakeCaptureEngine (4) + RegionSelection (6) + lastRegion round-trip (1) = 29 new tests, totaling 55 across 14 suites.

- [ ] **Step 3: Manual smoke test (HUMAN STEP — cannot be automated)**

This step requires human interaction. The agent should print the instructions and wait for the human operator (or report DONE_WITH_CONCERNS noting the manual step is pending).

```bash
# Build and launch
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build >/dev/null 2>&1
APP_PATH="$(xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
open "$APP_PATH"
```

Then verify each capture mode:

| # | Action | Expected outcome |
|---|---|---|
| 1 | Click menu bar icon → "Capture Full Screen" | A PNG appears in `~/Pictures/JuiceScreen/<today>/` named `JuiceScreen_<timestamp>.png`. If 2+ displays attached, a small picker appears first. |
| 2 | Press `⌘⌃3` (or your configured full-screen hotkey) | Same as #1, no menu interaction. |
| 3 | Click menu bar icon → "Capture Region" | Screen dims, drag a rectangle, release → PNG saved with the selected region. Press Esc mid-drag → no file saved. |
| 4 | Click menu bar icon → "Capture Last Region" | Without dragging, captures the same region as the last region capture. If no previous region, falls back to the picker. |
| 5 | Click menu bar icon → "Capture Window" | macOS window picker (Apple's `SCContentSharingPicker`) appears. Choose any visible window → PNG saved. |
| 6 | Open Console.app, filter by subsystem `com.bks-lab.juicescreen` | After each successful capture, see a log line: `Captured region → /Users/.../JuiceScreen_2026-05-05_at_…png` |

Verify in Finder: `open ~/Pictures/JuiceScreen` should show today's date subfolder with the captured PNGs.

If any mode fails: do NOT tag v0.2.0. Open an issue / debug, fix, re-test.

- [ ] **Step 4: Commit version bump**

```bash
git add VERSION project.yml
git commit -m "chore: bump VERSION to 0.2.0"
```

- [ ] **Step 5: Tag v0.2.0**

```bash
git tag -a v0.2.0 -m "Image Capture milestone: region/window/full/last region all working"
git tag -l v0.2.0
```

(Local tag only. Push when ready.)

- [ ] **Step 6: Confirm clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Task 20: Update spec doc with Plan 2 status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Edit the implementation status section**

Find the "Implementation status (updated as plans complete)" section (added in Plan 1's Task 25). Update the Plan 2 line from `⬜ Plan 2: Image capture` to:

```
- ✅ **Plan 2: Image capture** (v0.2.0, 2026-05-05) — Region / window / full-screen / last-region capture all working. Files saved as PNG to `~/Pictures/JuiceScreen/YYYY-MM-DD/`. ScreenCaptureKit-based via `SCScreenshotManager`, `SCContentSharingPicker`, `SCShareableContent`. Custom transparent NSWindow region picker (no loupe / no edge snapping yet — deferred to a polish pass). Multi-display picker for 2+ displays. Last-region persists in UserDefaults. 29 new unit tests; 55 total across 14 suites
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 2 (Image capture) complete in implementation status"
```

---

## Plan completion checklist

After Task 20:

- [ ] `git log --oneline | head -25` shows ~20 new commits since v0.1.0 (one per task plus version bump and spec update)
- [ ] `git tag -l` shows both `v0.1.0` and `v0.2.0`
- [ ] `xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests` is green
- [ ] All 4 capture modes verified manually per Task 19's smoke test
- [ ] `~/Pictures/JuiceScreen/<today>/` contains real PNG files from each smoke-test capture

When everything checks out: ship v0.2.0 alpha. Plan 3 (Annotation editor) is next — it adds an editor window per capture so the user can mark up the screenshots they're now producing.
