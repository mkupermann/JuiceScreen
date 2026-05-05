# PDF Export + Sparkle + Settings Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the v1 spec deferrals — rasterized PDF export from the annotation editor, Sparkle 2.x dependency wired with EdDSA-ready Info.plist, full Settings persistence (RecordingTab/GeneralTab/StorageTab/CaptureTab toggles bound to `Preferences`), Storage tab with usage stats + "Empty trash now", restore-from-trash button in the inspector. End state: v0.9.0.

**Architecture:** PDF export adds a `PDFEncoder` peer to PNG/JPG and a `.pdf` case on `ExportService.Format`. The QuickActions save panel allows `.pdf` and routes by file extension. `Preferences` gains six fields (recording options + capture options + auto-update toggle + last-checked date) and `PreferencesStore` round-trips them via `UserDefaults`. Settings tabs become real forms backed by a single `@State var prefs` loaded from `PreferencesStore` and saved on change. Sparkle 2.x SPM dependency wraps `SPUStandardUpdaterController`; the public key is a placeholder — Plan 10 generates the real key, signs the DMG, and publishes the appcast. Storage tab walks the library DB for usage stats and calls a new `LibraryStore.emptyTrash()` for the bulk delete. `LibraryViewModel.restoreSelected()` + an `InspectorView` Restore button surface the existing `LibraryStore.restore` API.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit `NSSavePanel`, PDFKit (`PDFDocument` + `PDFPage`), Sparkle 2.6.x, GRDB.swift 6.29 (existing), Swift Testing (`@Suite`/`@Test`/`#expect`).

---

## File structure

**New files:**

- `JuiceScreen/Annotation/Export/PDFEncoder.swift` — wraps a flattened `NSImage` in a single-page `PDFKit.PDFDocument` and returns `Data`
- `JuiceScreen/Updates/SparkleUpdater.swift` — thin wrapper around `SPUStandardUpdaterController`; exposes `checkNow()`, `isAutomaticChecksEnabled`, `lastCheckDate`
- `JuiceScreenTests/PDFEncoderTests.swift`
- `JuiceScreenTests/StorageStatsTests.swift` — tests for `StorageStats` model
- `JuiceScreen/MainWindow/Settings/StorageStats.swift` — pure value-type holding `totalBytes`, `captureCount`, `trashedBytes`, `trashedCount`; includes `compute(from rows:)` helper

**Modified files:**

- `project.yml` — add `Sparkle` SPM package + dependency
- `JuiceScreen/Resources/Info.plist` (driven by `project.yml`) — add `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`
- `JuiceScreen/Preferences/Preferences.swift` — add `recordingOptions`, `includeCursorInStills`, `imageScale`, `updateAutoCheckEnabled`, `updateLastCheckedAt`, `defaultExportFormat`
- `JuiceScreen/Preferences/PreferencesStore.swift` — round-trip the new fields
- `JuiceScreen/Annotation/Export/ExportService.swift` — add `.pdf` case
- `JuiceScreen/Annotation/Editor/QuickActions.swift` — `saveAs()` allows `.pdf`; `save()` routes by extension
- `JuiceScreen/MainWindow/Settings/GeneralTab.swift` — real form
- `JuiceScreen/MainWindow/Settings/CaptureTab.swift` — real form
- `JuiceScreen/MainWindow/Settings/RecordingTab.swift` — bind to Preferences
- `JuiceScreen/MainWindow/Settings/StorageTab.swift` — real form
- `JuiceScreen/MainWindow/Settings/AboutTab.swift` — add "Check for Updates" button + auto-check toggle
- `JuiceScreen/Library/Storage/LibraryStore.swift` — add `emptyTrash()` API
- `JuiceScreen/Library/Storage/LibraryStoreLive.swift` — implement `emptyTrash`
- `JuiceScreen/Library/Storage/FakeLibraryStore.swift` — implement `emptyTrash`
- `JuiceScreen/MainWindow/Library/LibraryViewModel.swift` — add `restoreSelected()`
- `JuiceScreen/MainWindow/Library/InspectorView.swift` — Restore button when `row.isDeleted`
- `JuiceScreen/App/AppDelegate.swift` — instantiate `SparkleUpdater`; thread persisted recording options into `recordingSessionManager.start(...)`
- `README.md` — v0.9 paragraph
- `VERSION` — bump to `0.9.0`
- `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — mark Plan 9 complete

---

### Task 1: PDFEncoder + tests

**Files:**
- Create: `JuiceScreen/Annotation/Export/PDFEncoder.swift`
- Create: `JuiceScreenTests/PDFEncoderTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/PDFEncoderTests.swift`:

```swift
import AppKit
import PDFKit
import Testing
@testable import JuiceScreen

@Suite("PDFEncoder")
struct PDFEncoderTests {

    private func makeImage(size: CGSize, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    @Test("Encodes a non-empty PDF that PDFKit can re-open")
    func encodesValidPDF() throws {
        let image = makeImage(size: CGSize(width: 200, height: 100), color: .systemBlue)
        let data = try PDFEncoder.encode(image)
        #expect(data.count > 0)

        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == 1)
    }

    @Test("Page bounds match image pixel size")
    func pageBoundsMatchImage() throws {
        let image = makeImage(size: CGSize(width: 320, height: 240), color: .systemRed)
        let data = try PDFEncoder.encode(image)
        let doc = try #require(PDFDocument(data: data))
        let page = try #require(doc.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(bounds.width == 320)
        #expect(bounds.height == 240)
    }

    @Test("Throws renderFailed when image has no representations")
    func emptyImageThrows() {
        let empty = NSImage()
        #expect(throws: PDFEncoder.PDFEncoderError.self) {
            try PDFEncoder.encode(empty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation && xcodegen generate && xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/PDFEncoder`

Expected: BUILD FAILURE — `PDFEncoder` not found.

- [ ] **Step 3: Write minimal implementation**

`JuiceScreen/Annotation/Export/PDFEncoder.swift`:

```swift
import AppKit
import PDFKit

public enum PDFEncoder {

    public enum PDFEncoderError: Error, Equatable {
        case noRepresentations
        case pageCreationFailed
    }

    /// Wraps the flattened NSImage as a single-page PDFDocument and returns its data.
    /// Page size in points equals image size in pixels (so a 1× capture renders 1:1).
    public static func encode(_ image: NSImage) throws -> Data {
        guard !image.representations.isEmpty else {
            throw PDFEncoderError.noRepresentations
        }
        let pixelSize: CGSize
        if let rep = image.representations.first as? NSBitmapImageRep {
            pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            pixelSize = image.size
        }
        let sized = NSImage(size: pixelSize)
        sized.addRepresentations(image.representations)
        guard let page = PDFPage(image: sized) else {
            throw PDFEncoderError.pageCreationFailed
        }
        page.setBounds(CGRect(origin: .zero, size: pixelSize), for: .mediaBox)
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        return doc.dataRepresentation() ?? Data()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/PDFEncoder`

Expected: PASS — 3/3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Export/PDFEncoder.swift JuiceScreenTests/PDFEncoderTests.swift project.pbxproj 2>/dev/null; git add JuiceScreen/Annotation/Export/PDFEncoder.swift JuiceScreenTests/PDFEncoderTests.swift
git commit -m "feat(annotation): add PDFEncoder for single-page rasterized PDF export"
```

---

### Task 2: ExportService.Format.pdf

**Files:**
- Modify: `JuiceScreen/Annotation/Export/ExportService.swift`
- Create: `JuiceScreenTests/ExportServicePDFTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/ExportServicePDFTests.swift`:

```swift
import AppKit
import PDFKit
import Testing
@testable import JuiceScreen

@MainActor
@Suite("ExportService.pdf")
struct ExportServicePDFTests {

    private func makeImage() -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 60,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 60).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: CGSize(width: 100, height: 60))
        img.addRepresentation(rep)
        return img
    }

    @Test("Exports a flattened document as PDF")
    func exportsPDF() throws {
        let image = makeImage()
        let doc = AnnotationDocument(baseImage: image, layers: [])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).pdf")

        try ExportService.export(document: doc, format: .pdf, jpegQuality: 0.9, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let pdfDoc = try #require(PDFDocument(data: data))
        #expect(pdfDoc.pageCount == 1)
    }

    @Test("Format.pdf is in CaseIterable.allCases")
    func pdfIsCaseIterable() {
        #expect(ExportService.Format.allCases.contains(.pdf))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/ExportService.pdf`

Expected: BUILD FAILURE — `Format` has no `.pdf` case.

- [ ] **Step 3: Modify ExportService**

`JuiceScreen/Annotation/Export/ExportService.swift`:

```swift
import AppKit
import Foundation

@MainActor
public enum ExportService {

    public enum Format: String, Sendable, CaseIterable {
        case png
        case jpg
        case pdf
    }

    public enum ExportError: Error, Equatable {
        case renderFailed
        case writeFailed(String)
    }

    /// Flattens the document and writes it to `destination`.
    public static func export(document: AnnotationDocument, format: Format, jpegQuality: Double, to destination: URL) throws {
        let flattened = try AnnotationRenderer.render(document)
        let data: Data
        switch format {
        case .png:
            data = try PNGEncoder.encode(flattened)
        case .jpg:
            data = try JPGEncoder.encode(flattened, quality: jpegQuality)
        case .pdf:
            data = try PDFEncoder.encode(flattened)
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ExportError.writeFailed("\(error)")
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/ExportService.pdf -only-testing:JuiceScreenTests/ExportService`

Expected: PASS — 2/2 new tests pass; existing PNG/JPG ExportService tests still pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Export/ExportService.swift JuiceScreenTests/ExportServicePDFTests.swift
git commit -m "feat(annotation): add .pdf case to ExportService.Format"
```

---

### Task 3: QuickActions saveAs allows PDF

**Files:**
- Modify: `JuiceScreen/Annotation/Editor/QuickActions.swift`

- [ ] **Step 1: Write the failing test**

Append to `JuiceScreenTests/ExportServicePDFTests.swift` (or create `QuickActionsFormatTests.swift`):

```swift
@MainActor
@Suite("QuickActions extension routing")
struct QuickActionsFormatRoutingTests {

    @Test("formatForExtension picks .pdf for .pdf URLs")
    func pdfRoutes() {
        #expect(ExportService.formatForExtension("pdf") == .pdf)
    }

    @Test("formatForExtension picks .jpg for jpg/jpeg")
    func jpgRoutes() {
        #expect(ExportService.formatForExtension("jpg") == .jpg)
        #expect(ExportService.formatForExtension("jpeg") == .jpg)
        #expect(ExportService.formatForExtension("JPG") == .jpg)
    }

    @Test("formatForExtension defaults to .png for unknown")
    func defaultsToPNG() {
        #expect(ExportService.formatForExtension("png") == .png)
        #expect(ExportService.formatForExtension("") == .png)
        #expect(ExportService.formatForExtension("tiff") == .png)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/QuickActions extension routing`

Expected: BUILD FAILURE — `formatForExtension` not found.

- [ ] **Step 3: Add helper to ExportService and update QuickActions**

Append to `JuiceScreen/Annotation/Export/ExportService.swift` (inside the enum):

```swift
    /// Maps a file extension (lowercased or not, with or without leading dot) to the matching Format.
    /// Defaults to `.png` if the extension is unknown.
    public static func formatForExtension(_ ext: String) -> Format {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch normalized {
        case "jpg", "jpeg": return .jpg
        case "pdf":         return .pdf
        default:            return .png
        }
    }
```

Modify `JuiceScreen/Annotation/Editor/QuickActions.swift`:

Replace the `save()` body's format derivation:

```swift
    public func save() {
        let url = state.captureRecord.fileURL
        let format = ExportService.formatForExtension(url.pathExtension)
        let quality = preferences.load().jpegQuality
        do {
            try ExportService.export(document: state.document, format: format, jpegQuality: quality, to: url)
            log.info("Saved → \(url.path)")
            state.isEdited = false
        } catch {
            log.error("Save failed: \(String(describing: error))")
            presentSaveError(error)
        }
    }
```

Replace `saveAs()`:

```swift
    public func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.nameFieldStringValue = state.captureRecord.fileURL.deletingPathExtension().lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format = ExportService.formatForExtension(url.pathExtension)
        let quality = preferences.load().jpegQuality
        do {
            try ExportService.export(document: state.document, format: format, jpegQuality: quality, to: url)
            log.info("Save As → \(url.path)")
            state.isEdited = false
        } catch {
            log.error("Save As failed: \(String(describing: error))")
            presentSaveError(error)
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests`

Expected: PASS — all tests including new format-routing tests pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Export/ExportService.swift JuiceScreen/Annotation/Editor/QuickActions.swift JuiceScreenTests/ExportServicePDFTests.swift
git commit -m "feat(annotation): allow PDF in Save As panel + extension-based format routing"
```

---

### Task 4: Preferences gains recording + capture + update fields

**Files:**
- Modify: `JuiceScreen/Preferences/Preferences.swift`
- Modify: `JuiceScreenTests/PreferencesStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `JuiceScreenTests/PreferencesStoreTests.swift` (inside the `@Suite` struct):

```swift
    @Test("Defaults expose new v0.9 fields")
    func newFieldDefaults() {
        let (store, _) = makeEphemeralStore()
        let prefs = store.load()
        #expect(prefs.recordingOptions == VideoRecordingOptions.defaults)
        #expect(prefs.includeCursorInStills == false)
        #expect(prefs.imageScale == .retina)
        #expect(prefs.updateAutoCheckEnabled == true)
        #expect(prefs.updateLastCheckedAt == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/PreferencesStore/newFieldDefaults`

Expected: BUILD FAILURE — fields don't exist.

- [ ] **Step 3: Modify Preferences**

`JuiceScreen/Preferences/Preferences.swift` — replace whole file:

```swift
import Foundation

public enum StillImageFormat: String, Sendable, CaseIterable {
    case png
    case jpg
}

public enum ImageScale: String, Sendable, CaseIterable {
    case retina      // native scale (2× on Retina displays)
    case oneToOne    // force 1× even on Retina
}

/// All user preferences for JuiceScreen. Pure value type — no I/O.
/// Persisted via `PreferencesStore`.
public struct Preferences: Equatable, Sendable {

    public var firstRunComplete: Bool
    public var startAtLogin: Bool

    public var saveDirectory: URL
    public var defaultStillFormat: StillImageFormat
    public var jpegQuality: Double          // 0.0 – 1.0

    public var captureRegionHotkey: Hotkey
    public var captureWindowHotkey: Hotkey
    public var captureFullScreenHotkey: Hotkey
    public var captureLastRegionHotkey: Hotkey
    public var recordScreenHotkey: Hotkey
    public var openLibraryHotkey: Hotkey
    public var captureScrollHotkey: Hotkey

    public var hotkeysPaused: Bool
    public var lastRegion: CGRect?

    // v0.9 additions
    public var recordingOptions: VideoRecordingOptions
    public var includeCursorInStills: Bool
    public var imageScale: ImageScale
    public var updateAutoCheckEnabled: Bool
    public var updateLastCheckedAt: Date?

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
            // virtual keycodes per Carbon: 21=4, 19=2, 20=3, 15=R, 23=5, 37=L, 22=6
            captureRegionHotkey:     Hotkey(keyCode: 21, modifiers: [.command, .shift]),
            captureWindowHotkey:     Hotkey(keyCode: 19, modifiers: [.command, .shift]),
            captureFullScreenHotkey: Hotkey(keyCode: 20, modifiers: [.command, .shift]),
            captureLastRegionHotkey: Hotkey(keyCode: 15, modifiers: [.command, .shift]),
            recordScreenHotkey:      Hotkey(keyCode: 23, modifiers: [.command, .shift]),
            openLibraryHotkey:       Hotkey(keyCode: 37, modifiers: [.command, .shift]),
            captureScrollHotkey:     Hotkey(keyCode: 22, modifiers: [.command, .shift]),
            hotkeysPaused: false,
            lastRegion: nil,
            recordingOptions: .defaults,
            includeCursorInStills: false,
            imageScale: .retina,
            updateAutoCheckEnabled: true,
            updateLastCheckedAt: nil
        )
    }()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/PreferencesStore`

Expected: PASS — `newFieldDefaults` passes; existing PreferencesStore tests still pass (`load()` still returns valid defaults because the older fields haven't changed).

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Preferences/Preferences.swift JuiceScreenTests/PreferencesStoreTests.swift
git commit -m "feat(preferences): add recording/capture/update fields for v0.9 settings"
```

---

### Task 5: PreferencesStore round-trips new fields

**Files:**
- Modify: `JuiceScreen/Preferences/PreferencesStore.swift`
- Modify: `JuiceScreenTests/PreferencesStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Append three tests to `JuiceScreenTests/PreferencesStoreTests.swift`:

```swift
    @Test("Recording options round-trip")
    func recordingOptionsRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.recordingOptions = VideoRecordingOptions(
            targetFps: 30,
            captureSystemAudio: false,
            captureMicrophone: true,
            showCursorHighlight: false,
            showClickPulse: true,
            showKeystrokes: true
        )
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.recordingOptions.targetFps == 30)
        #expect(reloaded.recordingOptions.captureSystemAudio == false)
        #expect(reloaded.recordingOptions.captureMicrophone == true)
        #expect(reloaded.recordingOptions.showCursorHighlight == false)
        #expect(reloaded.recordingOptions.showClickPulse == true)
        #expect(reloaded.recordingOptions.showKeystrokes == true)
    }

    @Test("Capture and update fields round-trip")
    func captureAndUpdateRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.includeCursorInStills = true
        prefs.imageScale = .oneToOne
        prefs.updateAutoCheckEnabled = false
        prefs.updateLastCheckedAt = Date(timeIntervalSince1970: 1_715_000_000)
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.includeCursorInStills == true)
        #expect(reloaded.imageScale == .oneToOne)
        #expect(reloaded.updateAutoCheckEnabled == false)
        #expect(reloaded.updateLastCheckedAt == Date(timeIntervalSince1970: 1_715_000_000))
    }

    @Test("updateLastCheckedAt removed when set to nil")
    func updateLastCheckedAtClears() {
        let (store, defaults) = makeEphemeralStore()
        var prefs = store.load()
        prefs.updateLastCheckedAt = Date(timeIntervalSince1970: 1_715_000_000)
        store.save(prefs)
        #expect(defaults.object(forKey: "updateLastCheckedAt") != nil)

        prefs.updateLastCheckedAt = nil
        store.save(prefs)
        #expect(defaults.object(forKey: "updateLastCheckedAt") == nil)
        #expect(store.load().updateLastCheckedAt == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/PreferencesStore/recordingOptionsRoundTrip`

Expected: FAIL — store doesn't persist new fields.

- [ ] **Step 3: Modify PreferencesStore**

`JuiceScreen/Preferences/PreferencesStore.swift` — replace the file:

```swift
import Foundation

/// Reads/writes `Preferences` via `UserDefaults`. Single source of truth at runtime.
public final class PreferencesStore: @unchecked Sendable {

    private enum Key {
        static let firstRunComplete = "firstRunComplete"
        static let startAtLogin = "startAtLogin"
        static let saveDirectory = "saveDirectory"
        static let defaultStillFormat = "defaultStillFormat"
        static let jpegQuality = "jpegQuality"
        static let captureRegionHotkey = "captureRegionHotkey"
        static let captureWindowHotkey = "captureWindowHotkey"
        static let captureFullScreenHotkey = "captureFullScreenHotkey"
        static let captureLastRegionHotkey = "captureLastRegionHotkey"
        static let recordScreenHotkey = "recordScreenHotkey"
        static let openLibraryHotkey = "openLibraryHotkey"
        static let captureScrollHotkey = "captureScrollHotkey"
        static let hotkeysPaused = "hotkeysPaused"
        static let lastRegion = "lastRegion"

        // v0.9
        static let recTargetFps = "recordingTargetFps"
        static let recSystemAudio = "recordingSystemAudio"
        static let recMicrophone = "recordingMicrophone"
        static let recCursorHighlight = "recordingCursorHighlight"
        static let recClickPulse = "recordingClickPulse"
        static let recKeystrokes = "recordingKeystrokes"
        static let includeCursorInStills = "includeCursorInStills"
        static let imageScale = "imageScale"
        static let updateAutoCheckEnabled = "updateAutoCheckEnabled"
        static let updateLastCheckedAt = "updateLastCheckedAt"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Preferences {
        let d = Preferences.defaults
        let opts = VideoRecordingOptions(
            targetFps:           defaults.object(forKey: Key.recTargetFps) as? Int ?? d.recordingOptions.targetFps,
            captureSystemAudio:  defaults.object(forKey: Key.recSystemAudio) as? Bool ?? d.recordingOptions.captureSystemAudio,
            captureMicrophone:   defaults.object(forKey: Key.recMicrophone) as? Bool ?? d.recordingOptions.captureMicrophone,
            showCursorHighlight: defaults.object(forKey: Key.recCursorHighlight) as? Bool ?? d.recordingOptions.showCursorHighlight,
            showClickPulse:      defaults.object(forKey: Key.recClickPulse) as? Bool ?? d.recordingOptions.showClickPulse,
            showKeystrokes:      defaults.object(forKey: Key.recKeystrokes) as? Bool ?? d.recordingOptions.showKeystrokes
        )
        let imageScale: ImageScale = (defaults.string(forKey: Key.imageScale).flatMap(ImageScale.init(rawValue:))) ?? d.imageScale
        let lastCheckedSeconds = defaults.object(forKey: Key.updateLastCheckedAt) as? Double
        return Preferences(
            firstRunComplete:        defaults.object(forKey: Key.firstRunComplete) as? Bool ?? d.firstRunComplete,
            startAtLogin:            defaults.object(forKey: Key.startAtLogin) as? Bool ?? d.startAtLogin,
            saveDirectory:           loadURL(Key.saveDirectory) ?? d.saveDirectory,
            defaultStillFormat:      loadEnum(Key.defaultStillFormat) ?? d.defaultStillFormat,
            jpegQuality:             defaults.object(forKey: Key.jpegQuality) as? Double ?? d.jpegQuality,
            captureRegionHotkey:     loadHotkey(Key.captureRegionHotkey)     ?? d.captureRegionHotkey,
            captureWindowHotkey:     loadHotkey(Key.captureWindowHotkey)     ?? d.captureWindowHotkey,
            captureFullScreenHotkey: loadHotkey(Key.captureFullScreenHotkey) ?? d.captureFullScreenHotkey,
            captureLastRegionHotkey: loadHotkey(Key.captureLastRegionHotkey) ?? d.captureLastRegionHotkey,
            recordScreenHotkey:      loadHotkey(Key.recordScreenHotkey)      ?? d.recordScreenHotkey,
            openLibraryHotkey:       loadHotkey(Key.openLibraryHotkey)       ?? d.openLibraryHotkey,
            captureScrollHotkey:     loadHotkey(Key.captureScrollHotkey)     ?? d.captureScrollHotkey,
            hotkeysPaused:           defaults.object(forKey: Key.hotkeysPaused) as? Bool ?? d.hotkeysPaused,
            lastRegion:              loadRect(Key.lastRegion),
            recordingOptions:        opts,
            includeCursorInStills:   defaults.object(forKey: Key.includeCursorInStills) as? Bool ?? d.includeCursorInStills,
            imageScale:              imageScale,
            updateAutoCheckEnabled:  defaults.object(forKey: Key.updateAutoCheckEnabled) as? Bool ?? d.updateAutoCheckEnabled,
            updateLastCheckedAt:     lastCheckedSeconds.map { Date(timeIntervalSince1970: $0) }
        )
    }

    public func save(_ prefs: Preferences) {
        defaults.set(prefs.firstRunComplete, forKey: Key.firstRunComplete)
        defaults.set(prefs.startAtLogin, forKey: Key.startAtLogin)
        saveURL(prefs.saveDirectory, key: Key.saveDirectory)
        defaults.set(prefs.defaultStillFormat.rawValue, forKey: Key.defaultStillFormat)
        defaults.set(prefs.jpegQuality, forKey: Key.jpegQuality)
        saveHotkey(prefs.captureRegionHotkey,     key: Key.captureRegionHotkey)
        saveHotkey(prefs.captureWindowHotkey,     key: Key.captureWindowHotkey)
        saveHotkey(prefs.captureFullScreenHotkey, key: Key.captureFullScreenHotkey)
        saveHotkey(prefs.captureLastRegionHotkey, key: Key.captureLastRegionHotkey)
        saveHotkey(prefs.recordScreenHotkey,      key: Key.recordScreenHotkey)
        saveHotkey(prefs.openLibraryHotkey,       key: Key.openLibraryHotkey)
        saveHotkey(prefs.captureScrollHotkey,     key: Key.captureScrollHotkey)
        defaults.set(prefs.hotkeysPaused, forKey: Key.hotkeysPaused)
        saveRect(prefs.lastRegion, key: Key.lastRegion)

        defaults.set(prefs.recordingOptions.targetFps, forKey: Key.recTargetFps)
        defaults.set(prefs.recordingOptions.captureSystemAudio, forKey: Key.recSystemAudio)
        defaults.set(prefs.recordingOptions.captureMicrophone, forKey: Key.recMicrophone)
        defaults.set(prefs.recordingOptions.showCursorHighlight, forKey: Key.recCursorHighlight)
        defaults.set(prefs.recordingOptions.showClickPulse, forKey: Key.recClickPulse)
        defaults.set(prefs.recordingOptions.showKeystrokes, forKey: Key.recKeystrokes)
        defaults.set(prefs.includeCursorInStills, forKey: Key.includeCursorInStills)
        defaults.set(prefs.imageScale.rawValue, forKey: Key.imageScale)
        defaults.set(prefs.updateAutoCheckEnabled, forKey: Key.updateAutoCheckEnabled)
        if let date = prefs.updateLastCheckedAt {
            defaults.set(date.timeIntervalSince1970, forKey: Key.updateLastCheckedAt)
        } else {
            defaults.removeObject(forKey: Key.updateLastCheckedAt)
        }
    }

    // MARK: - Helpers

    private func loadHotkey(_ key: String) -> Hotkey? {
        guard let dict = defaults.dictionary(forKey: key) as? [String: UInt32] else { return nil }
        return Hotkey(dictionary: dict)
    }

    private func saveHotkey(_ hotkey: Hotkey, key: String) {
        defaults.set(hotkey.asDictionary, forKey: key)
    }

    private func loadURL(_ key: String) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func saveURL(_ url: URL, key: String) {
        defaults.set(url.path, forKey: key)
    }

    private func loadEnum(_ key: String) -> StillImageFormat? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return StillImageFormat(rawValue: raw)
    }

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
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/PreferencesStore`

Expected: PASS — all PreferencesStore tests including the three new ones pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Preferences/PreferencesStore.swift JuiceScreenTests/PreferencesStoreTests.swift
git commit -m "feat(preferences): persist recording/capture/update fields via UserDefaults"
```

---

### Task 6: RecordingTab binds to Preferences

**Files:**
- Modify: `JuiceScreen/MainWindow/Settings/RecordingTab.swift`

- [ ] **Step 1: Replace the file**

The current `RecordingTab` keeps toggles in `@State` only — they reset when the window closes. Bind them to a `PreferencesStore` and persist on every change.

`JuiceScreen/MainWindow/Settings/RecordingTab.swift`:

```swift
import SwiftUI

struct RecordingTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                Picker("Target frame rate", selection: Binding(
                    get: { prefs.recordingOptions.targetFps },
                    set: { newValue in prefs.recordingOptions.targetFps = newValue; save() }
                )) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                .help("60 fps gives smoother motion at the cost of larger files. 30 fps is fine for most demos.")
            } header: { Text("Quality") }

            Section {
                Toggle("Capture system audio", isOn: Binding(
                    get: { prefs.recordingOptions.captureSystemAudio },
                    set: { newValue in prefs.recordingOptions.captureSystemAudio = newValue; save() }
                ))
                .help("Mix system audio (anything macOS routes through speakers/headphones) into the recording.")
                Toggle("Capture microphone", isOn: Binding(
                    get: { prefs.recordingOptions.captureMicrophone },
                    set: { newValue in prefs.recordingOptions.captureMicrophone = newValue; save() }
                ))
                .help("Adds a separate microphone track. macOS will prompt for Microphone permission the first time you record with this enabled.")
            } header: { Text("Audio") }

            Section {
                Toggle("Cursor highlight ring", isOn: Binding(
                    get: { prefs.recordingOptions.showCursorHighlight },
                    set: { newValue in prefs.recordingOptions.showCursorHighlight = newValue; save() }
                ))
                .help("Yellow ring around the cursor in the output video. No extra permissions required.")
                Toggle("Click pulse", isOn: Binding(
                    get: { prefs.recordingOptions.showClickPulse },
                    set: { newValue in prefs.recordingOptions.showClickPulse = newValue; save() }
                ))
                .help("Animated pulse at every click. Requires macOS Input Monitoring permission — will prompt the first time you enable.")
                Toggle("Show keystrokes", isOn: Binding(
                    get: { prefs.recordingOptions.showKeystrokes },
                    set: { newValue in prefs.recordingOptions.showKeystrokes = newValue; save() }
                ))
                .help("Last 3 keys typed appear in the bottom-right corner. Requires Input Monitoring.")
            } header: { Text("Overlays") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        preferences.save(prefs)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests`

Expected: PASS — no regressions.

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/MainWindow/Settings/RecordingTab.swift
git commit -m "feat(settings): RecordingTab persists toggles via PreferencesStore"
```

---

### Task 7: GeneralTab — start at login, save folder, default format, JPG quality

**Files:**
- Modify: `JuiceScreen/MainWindow/Settings/GeneralTab.swift`

- [ ] **Step 1: Replace the file**

`JuiceScreen/MainWindow/Settings/GeneralTab.swift`:

```swift
import AppKit
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: Binding(
                    get: { prefs.startAtLogin },
                    set: { newValue in prefs.startAtLogin = newValue; applyStartAtLogin(newValue); save() }
                ))
                .help("Adds JuiceScreen to login items so it launches when you sign in.")
            } header: { Text("Launch") }

            Section {
                HStack {
                    Text("Save folder")
                    Spacer()
                    Text(prefs.saveDirectory.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseSaveDirectory() }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([prefs.saveDirectory])
                }
            } header: { Text("Save location") }

            Section {
                Picker("Default format", selection: Binding(
                    get: { prefs.defaultStillFormat },
                    set: { newValue in prefs.defaultStillFormat = newValue; save() }
                )) {
                    Text("PNG (lossless)").tag(StillImageFormat.png)
                    Text("JPG (smaller)").tag(StillImageFormat.jpg)
                }
                .pickerStyle(.segmented)
                if prefs.defaultStillFormat == .jpg {
                    HStack {
                        Text("JPG quality")
                        Slider(value: Binding(
                            get: { prefs.jpegQuality },
                            set: { newValue in prefs.jpegQuality = newValue; save() }
                        ), in: 0.5 ... 1.0, step: 0.05)
                        Text(String(format: "%.0f%%", prefs.jpegQuality * 100))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            } header: { Text("Default still format") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = prefs.saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.saveDirectory = url
            save()
        }
    }

    private func applyStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLog.logger(category: "Settings").error("Login item toggle failed: \(String(describing: error))")
        }
    }

    private func save() {
        preferences.save(prefs)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED. (`ServiceManagement` is part of the macOS SDK; no project.yml change needed.)

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests`

Expected: PASS — no regressions.

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/MainWindow/Settings/GeneralTab.swift
git commit -m "feat(settings): GeneralTab — start at login, save folder, format + JPG quality"
```

---

### Task 8: CaptureTab — image scale + include cursor

**Files:**
- Modify: `JuiceScreen/MainWindow/Settings/CaptureTab.swift`

- [ ] **Step 1: Replace the file**

`JuiceScreen/MainWindow/Settings/CaptureTab.swift`:

```swift
import SwiftUI

struct CaptureTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                Picker("Image scale", selection: Binding(
                    get: { prefs.imageScale },
                    set: { newValue in prefs.imageScale = newValue; save() }
                )) {
                    Text("Native (Retina)").tag(ImageScale.retina)
                    Text("1× (smaller files)").tag(ImageScale.oneToOne)
                }
                .pickerStyle(.segmented)
                .help("Native preserves Retina resolution (typically 2× pixels). 1× downsamples to logical points.")
            } header: { Text("Resolution") }

            Section {
                Toggle("Include cursor in still captures", isOn: Binding(
                    get: { prefs.includeCursorInStills },
                    set: { newValue in prefs.includeCursorInStills = newValue; save() }
                ))
                .help("When on, the macOS cursor appears in PNG/JPG/PDF captures at the location it was when you triggered the capture. Off by default since cursors clutter screenshots.")
            } header: { Text("Cursor") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        preferences.save(prefs)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MainWindow/Settings/CaptureTab.swift
git commit -m "feat(settings): CaptureTab — image scale + include cursor toggle"
```

---

### Task 9: AppDelegate threads persisted recording options into RecordingSession

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Modify AppDelegate.startRecording**

In `JuiceScreen/App/AppDelegate.swift`, replace the `startRecording()` method:

```swift
    private func startRecording() {
        Task { @MainActor in
            let mode: VideoRecordingMode = .fullScreen
            let prefs = preferences.load()
            let date = Date()
            let saveDir = SaveDirectoryProvider(rootDirectory: prefs.saveDirectory)
            let outputURL: URL
            do {
                let folder = try saveDir.directory(for: date)
                let filename = FilenameGenerator().filename(for: date, extension: "mp4")
                outputURL = folder.appendingPathComponent(filename)
            } catch {
                AppLog.logger(category: "App").error("Could not prepare output URL: \(String(describing: error))")
                return
            }
            do {
                menuBar?.setRecordingIndicator(true)
                try await recordingSessionManager.start(mode: mode, options: prefs.recordingOptions, outputURL: outputURL)
            } catch {
                AppLog.logger(category: "App").error("Recording failed to start: \(String(describing: error))")
                menuBar?.setRecordingIndicator(false)
            }
        }
    }
```

(The only change vs. v0.8 is `options: prefs.recordingOptions` instead of `options: .defaults`.)

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests`

Expected: PASS — no regressions (RecordingSession tests all use the parameterised `options` arg already).

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): startRecording reads recordingOptions from Preferences"
```

---

### Task 10: Add Sparkle SPM dependency + Info.plist keys

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Edit project.yml**

Add Sparkle to the `packages:` block and to the JuiceScreen target's dependencies, and append the three Sparkle Info.plist keys.

`project.yml`:

```yaml
name: JuiceScreen
options:
  bundleIdPrefix: com.bks-lab
  deploymentTarget:
    macOS: "14.0"
  developmentLanguage: en
  createIntermediateGroups: true
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "5.10"
    SWIFT_STRICT_CONCURRENCY: complete
    MARKETING_VERSION: "0.8.0"
    CURRENT_PROJECT_VERSION: "1"
    DEAD_CODE_STRIPPING: YES
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    GCC_TREAT_WARNINGS_AS_ERRORS: NO
    SWIFT_TREAT_WARNINGS_AS_ERRORS: NO
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift.git
    from: "6.29.0"
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle.git
    from: "2.6.0"

targets:
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
      path: JuiceScreen/Resources/Info.plist
      properties:
        CFBundleName: JuiceScreen
        CFBundleDisplayName: JuiceScreen
        CFBundleIdentifier: com.bks-lab.juicescreen
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSUIElement: true
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        NSHumanReadableCopyright: "© 2026 Michael Kupermann. MIT licensed."
        NSCameraUsageDescription: "JuiceScreen does not use the camera."
        NSMicrophoneUsageDescription: "JuiceScreen needs microphone access only when you enable mic recording during a screen recording. It is never accessed otherwise."
        SUFeedURL: "https://mkupermann.github.io/JuiceScreen/appcast.xml"
        SUPublicEDKey: "PLACEHOLDER_GENERATE_IN_PLAN_10"
        SUEnableAutomaticChecks: true
    entitlements:
      path: JuiceScreen/Resources/JuiceScreen.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.device.audio-input: true
        com.apple.security.device.camera: false
    dependencies:
      - package: GRDB
      - package: Sparkle
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.bks-lab.juicescreen
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
        DEVELOPMENT_TEAM: ""
    scheme:
      testTargets:
        - JuiceScreenTests
        - JuiceScreenUITests
      gatherCoverageData: true

  JuiceScreenTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: JuiceScreenTests
    dependencies:
      - target: JuiceScreen
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/JuiceScreen.app/Contents/MacOS/JuiceScreen
        PRODUCT_BUNDLE_IDENTIFIER: com.bks-lab.juicescreen.tests

  JuiceScreenUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - path: JuiceScreenUITests
    dependencies:
      - target: JuiceScreen
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        TEST_TARGET_NAME: JuiceScreen
        PRODUCT_BUNDLE_IDENTIFIER: com.bks-lab.juicescreen.uitests
```

- [ ] **Step 2: Regenerate the project**

Run: `cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation && xcodegen generate`

Expected: `Generated project successfully` (Sparkle resolves on first build).

- [ ] **Step 3: Build to resolve Sparkle**

Run: `xcodebuild -scheme JuiceScreen -destination 'platform=macOS' -resolvePackageDependencies`

Expected: Sparkle 2.6.x resolved without error.

Then: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED. The app builds without using Sparkle yet (no `import Sparkle` in code) — the dependency just exists and the Info.plist keys are bundled.

- [ ] **Step 4: Commit**

```bash
git add project.yml
git commit -m "build: add Sparkle 2.6 SPM dependency + Info.plist update keys"
```

---

### Task 11: SparkleUpdater wrapper service

**Files:**
- Create: `JuiceScreen/Updates/SparkleUpdater.swift`

- [ ] **Step 1: Create the wrapper**

`JuiceScreen/Updates/SparkleUpdater.swift`:

```swift
import Foundation
import Sparkle

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of the app does not import Sparkle.
@MainActor
public final class SparkleUpdater {

    private let controller: SPUStandardUpdaterController
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "SparkleUpdater")

    public init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        // startingUpdater: true → Sparkle starts its scheduler immediately based on Info.plist + UserDefaults.
        // Delegates: nil → use Sparkle's standard UI driver and default behavior.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Mirror our own preference into Sparkle's runtime flag at launch.
        let prefs = preferences.load()
        self.controller.updater.automaticallyChecksForUpdates = prefs.updateAutoCheckEnabled
    }

    /// Triggers the standard "Check for Updates…" UI flow.
    public func checkNow() {
        log.info("User-initiated update check")
        controller.checkForUpdates(nil)
        // Persist the timestamp Sparkle will set (it updates lastUpdateCheckDate after the request).
        // We re-read on the next opening of the About tab, so writing here is best-effort.
        var prefs = preferences.load()
        prefs.updateLastCheckedAt = Date()
        preferences.save(prefs)
    }

    public var isAutomaticChecksEnabled: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            var prefs = preferences.load()
            prefs.updateAutoCheckEnabled = newValue
            preferences.save(prefs)
        }
    }

    public var lastCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED. Sparkle import resolves; wrapper compiles.

- [ ] **Step 3: Wire into AppDelegate**

In `JuiceScreen/App/AppDelegate.swift`, add a stored property near the top of the class (next to `hotkeyService`):

```swift
    private lazy var sparkleUpdater: SparkleUpdater = SparkleUpdater(preferences: preferences)
```

Then in `applicationDidFinishLaunching(_:)`, after `activationPolicy = ActivationPolicyController()` and before the `Task.detached { ... TrashGC ... }` block, add:

```swift
        _ = sparkleUpdater   // initializes Sparkle's scheduler
```

- [ ] **Step 4: Build + run all tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests`

Expected: PASS — no regressions.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Updates/SparkleUpdater.swift JuiceScreen/App/AppDelegate.swift
git commit -m "feat(updates): SparkleUpdater wrapper wired into AppDelegate"
```

---

### Task 12: AboutTab — version + Sparkle controls

**Files:**
- Modify: `JuiceScreen/MainWindow/Settings/AboutTab.swift`

- [ ] **Step 1: Replace the file**

`JuiceScreen/MainWindow/Settings/AboutTab.swift`:

```swift
import SwiftUI

struct AboutTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences
    @State private var lastCheckedDisplay: String

    private let updater: SparkleUpdater

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        let initial = preferences.load()
        _prefs = State(initialValue: initial)
        _lastCheckedDisplay = State(initialValue: Self.format(initial.updateLastCheckedAt))
        self.updater = SparkleUpdater(preferences: preferences)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("JuiceScreen")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)

            Text("Open-source, 100% local screen capture for macOS.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/mkupermann/JuiceScreen")!)
                Link("MIT License", destination: URL(string: "https://github.com/mkupermann/JuiceScreen/blob/main/LICENSE")!)
            }
            .padding(.top, 8)

            Divider().padding(.vertical, 8)

            VStack(spacing: 8) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { prefs.updateAutoCheckEnabled },
                    set: { newValue in
                        prefs.updateAutoCheckEnabled = newValue
                        preferences.save(prefs)
                        updater.isAutomaticChecksEnabled = newValue
                    }
                ))
                .toggleStyle(.switch)

                Button("Check for Updates Now") {
                    updater.checkNow()
                    // Refresh display after Sparkle's UI dismisses.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        prefs = preferences.load()
                        lastCheckedDisplay = Self.format(prefs.updateLastCheckedAt)
                    }
                }
                .controlSize(.large)

                Text("Last checked: \(lastCheckedDisplay)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 360)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MainWindow/Settings/AboutTab.swift
git commit -m "feat(settings): AboutTab — Sparkle Check for Updates + auto-check toggle"
```

---

### Task 13: LibraryStore.emptyTrash() + tests

**Files:**
- Modify: `JuiceScreen/Library/Storage/LibraryStore.swift`
- Modify: `JuiceScreen/Library/Storage/FakeLibraryStore.swift`
- Modify: `JuiceScreen/Library/Storage/LibraryStoreLive.swift`
- Modify: `JuiceScreenTests/LibraryStoreLiveTests.swift`
- Modify: `JuiceScreenTests/FakeLibraryStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `JuiceScreenTests/FakeLibraryStoreTests.swift`:

```swift
    @Test("emptyTrash removes all soft-deleted rows and returns the count")
    func emptyTrashRemovesDeleted() async throws {
        let store = FakeLibraryStore()
        let live = sampleRow(uuid: UUID(), deleted: false)
        let trashedA = sampleRow(uuid: UUID(), deleted: true)
        let trashedB = sampleRow(uuid: UUID(), deleted: true)
        try await store.insert(live)
        try await store.insert(trashedA)
        try await store.insert(trashedB)

        let removed = try await store.emptyTrash()
        #expect(removed == 2)

        let remaining = try await store.list(filter: .all)
        #expect(remaining.count == 1)
        #expect(remaining.first?.uuid == live.uuid)
    }
```

(`sampleRow(uuid:deleted:)` already exists in `FakeLibraryStoreTests.swift`. If not, create it: a helper that returns a fully-populated `CaptureRow` with `deletedAt: deleted ? Date() : nil`. Look near the top of `FakeLibraryStoreTests.swift` for the existing pattern.)

Append to `JuiceScreenTests/LibraryStoreLiveTests.swift`:

```swift
    @Test("emptyTrash hard-deletes all soft-deleted rows from the live store")
    func emptyTrashLive() async throws {
        let (store, _) = try makeLiveStore()
        let live = sampleRow(uuid: UUID(), deleted: false)
        let trashedA = sampleRow(uuid: UUID(), deleted: true)
        let trashedB = sampleRow(uuid: UUID(), deleted: true)
        try await store.insert(live)
        try await store.insert(trashedA)
        try await store.insert(trashedB)

        let removed = try await store.emptyTrash()
        #expect(removed == 2)

        // Trash filter is empty
        let trashRows = try await store.list(filter: .trash)
        #expect(trashRows.isEmpty)

        // Live filter has 1
        let allRows = try await store.list(filter: .all)
        #expect(allRows.count == 1)
        #expect(allRows.first?.uuid == live.uuid)
    }
```

(`makeLiveStore()` and `sampleRow(uuid:deleted:)` already exist in `LibraryStoreLiveTests.swift`. If `sampleRow` lacks a `deleted:` parameter, extend it analogously: `func sampleRow(uuid: UUID, deleted: Bool = false) -> CaptureRow` that sets `deletedAt: deleted ? Date(timeIntervalSince1970: 1_715_000_000) : nil`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FakeLibraryStore/emptyTrashRemovesDeleted -only-testing:JuiceScreenTests/LibraryStoreLive/emptyTrashLive`

Expected: BUILD FAILURE — `emptyTrash` not declared on protocol.

- [ ] **Step 3: Add to protocol**

In `JuiceScreen/Library/Storage/LibraryStore.swift`, add a method to the `LibraryStore` protocol (alongside the existing trash methods):

```swift
    /// Permanently deletes every row that has been soft-deleted (deletedAt != nil).
    /// Returns the count of rows removed. Does NOT delete the underlying files —
    /// callers must handle file deletion via TrashService.
    func emptyTrash() async throws -> Int
```

- [ ] **Step 4: Implement in FakeLibraryStore**

In `JuiceScreen/Library/Storage/FakeLibraryStore.swift`, add:

```swift
    public func emptyTrash() async throws -> Int {
        let toRemove = rows.filter { $0.isDeleted }
        rows.removeAll { $0.isDeleted }
        return toRemove.count
    }
```

- [ ] **Step 5: Implement in LibraryStoreLive**

In `JuiceScreen/Library/Storage/LibraryStoreLive.swift`, add (after `permanentlyDelete`):

```swift
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
```

- [ ] **Step 6: Run the new tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FakeLibraryStore/emptyTrashRemovesDeleted -only-testing:JuiceScreenTests/LibraryStoreLive/emptyTrashLive`

Expected: PASS — both tests pass.

- [ ] **Step 7: Run full library test suite**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/LibraryStoreLive -only-testing:JuiceScreenTests/FakeLibraryStore -only-testing:JuiceScreenTests/LibraryStoreLiveSearch`

Expected: PASS — no regressions.

- [ ] **Step 8: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStore.swift JuiceScreen/Library/Storage/FakeLibraryStore.swift JuiceScreen/Library/Storage/LibraryStoreLive.swift JuiceScreenTests/FakeLibraryStoreTests.swift JuiceScreenTests/LibraryStoreLiveTests.swift
git commit -m "feat(library): LibraryStore.emptyTrash() — hard-deletes all soft-deleted rows"
```

---

### Task 14: StorageStats value type + tests

**Files:**
- Create: `JuiceScreen/MainWindow/Settings/StorageStats.swift`
- Create: `JuiceScreenTests/StorageStatsTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/StorageStatsTests.swift`:

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("StorageStats")
struct StorageStatsTests {

    private func row(deleted: Bool, bytes: Int64) -> CaptureRow {
        CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/test",
            thumbnailPath: "/tmp/thumb",
            mediaType: .image,
            captureType: "region",
            capturedAt: Date(timeIntervalSince1970: 1_715_000_000),
            pixelWidth: 100,
            pixelHeight: 100,
            durationMs: nil,
            annotationPath: nil,
            fileSizeBytes: bytes,
            sourceApp: nil,
            deletedAt: deleted ? Date() : nil
        )
    }

    @Test("Empty list returns all-zero stats")
    func empty() {
        let stats = StorageStats.compute(from: [])
        #expect(stats.captureCount == 0)
        #expect(stats.totalBytes == 0)
        #expect(stats.trashedCount == 0)
        #expect(stats.trashedBytes == 0)
    }

    @Test("Live + trashed rows split correctly")
    func splitsByDeletedFlag() {
        let rows = [
            row(deleted: false, bytes: 1_000),
            row(deleted: false, bytes: 2_000),
            row(deleted: true,  bytes: 5_000),
            row(deleted: true,  bytes: 7_000)
        ]
        let stats = StorageStats.compute(from: rows)
        #expect(stats.captureCount == 2)
        #expect(stats.totalBytes == 3_000)
        #expect(stats.trashedCount == 2)
        #expect(stats.trashedBytes == 12_000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/StorageStats`

Expected: BUILD FAILURE — `StorageStats` not found.

- [ ] **Step 3: Create the value type**

`JuiceScreen/MainWindow/Settings/StorageStats.swift`:

```swift
import Foundation

public struct StorageStats: Equatable, Sendable {

    public let captureCount: Int
    public let totalBytes: Int64
    public let trashedCount: Int
    public let trashedBytes: Int64

    public static let empty = StorageStats(
        captureCount: 0, totalBytes: 0, trashedCount: 0, trashedBytes: 0
    )

    public static func compute(from rows: [CaptureRow]) -> StorageStats {
        var liveCount = 0
        var liveBytes: Int64 = 0
        var trashCount = 0
        var trashBytes: Int64 = 0
        for row in rows {
            if row.isDeleted {
                trashCount += 1
                trashBytes += row.fileSizeBytes
            } else {
                liveCount += 1
                liveBytes += row.fileSizeBytes
            }
        }
        return StorageStats(
            captureCount: liveCount,
            totalBytes: liveBytes,
            trashedCount: trashCount,
            trashedBytes: trashBytes
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/StorageStats`

Expected: PASS — 2/2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/MainWindow/Settings/StorageStats.swift JuiceScreenTests/StorageStatsTests.swift
git commit -m "feat(settings): add StorageStats value type for storage tab"
```

---

### Task 15: StorageTab — usage stats + Open save folder + Empty trash

**Files:**
- Modify: `JuiceScreen/MainWindow/Settings/StorageTab.swift`

- [ ] **Step 1: Replace the file**

`JuiceScreen/MainWindow/Settings/StorageTab.swift`:

```swift
import AppKit
import GRDB
import SwiftUI

struct StorageTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences
    @State private var stats: StorageStats = .empty
    @State private var isEmptyingTrash = false
    @State private var showEmptyTrashConfirm = false

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                statsRow("Captures", value: "\(stats.captureCount)")
                statsRow("Disk usage", value: ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file))
                statsRow("Trashed", value: "\(stats.trashedCount) (\(ByteCountFormatter.string(fromByteCount: stats.trashedBytes, countStyle: .file)))")
            } header: { Text("Library") }

            Section {
                Button("Open save folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([prefs.saveDirectory])
                }
                Button(isEmptyingTrash ? "Emptying…" : "Empty trash now") {
                    showEmptyTrashConfirm = true
                }
                .disabled(isEmptyingTrash || stats.trashedCount == 0)
                .confirmationDialog(
                    "Permanently delete \(stats.trashedCount) trashed item(s)?",
                    isPresented: $showEmptyTrashConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Empty Trash", role: .destructive) {
                        Task { await emptyTrash() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This frees \(ByteCountFormatter.string(fromByteCount: stats.trashedBytes, countStyle: .file)) but cannot be undone.")
                }
            } header: { Text("Actions") }

            Section {
                Text("OCR languages: en-US, de-DE")
                    .foregroundStyle(.secondary)
                Text("Custom language selection lands in v1.1.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } header: { Text("OCR") }
        }
        .formStyle(.grouped)
        .padding()
        .task { await reloadStats() }
    }

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func reloadStats() async {
        do {
            let paths = LibraryPaths()
            let dbURL = try paths.databaseURL()
            let queue = try DatabaseQueue(path: dbURL.path)
            try LibrarySchema.migrator().migrate(queue)
            let store = LibraryStoreLive(databaseQueue: queue)
            let live = try await store.list(filter: .all)
            let trashed = try await store.list(filter: .trash)
            stats = StorageStats.compute(from: live + trashed)
        } catch {
            stats = .empty
            AppLog.logger(category: "Settings").error("StorageTab stats failed: \(String(describing: error))")
        }
    }

    private func emptyTrash() async {
        isEmptyingTrash = true
        defer { isEmptyingTrash = false }
        do {
            let paths = LibraryPaths()
            let dbURL = try paths.databaseURL()
            let queue = try DatabaseQueue(path: dbURL.path)
            try LibrarySchema.migrator().migrate(queue)
            let store = LibraryStoreLive(databaseQueue: queue)

            let trashed = try await store.list(filter: .trash)
            let trashService = TrashService(captureRoot: prefs.saveDirectory)
            for row in trashed {
                let url = URL(fileURLWithPath: row.filePath)
                try? trashService.permanentlyDelete(trashedFile: url)
            }
            _ = try await store.emptyTrash()
            await reloadStats()
        } catch {
            AppLog.logger(category: "Settings").error("emptyTrash failed: \(String(describing: error))")
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MainWindow/Settings/StorageTab.swift
git commit -m "feat(settings): StorageTab — usage stats + Open save folder + Empty trash"
```

---

### Task 16: LibraryViewModel.restoreSelected() + InspectorView Restore button

**Files:**
- Modify: `JuiceScreen/MainWindow/Library/LibraryViewModel.swift`
- Modify: `JuiceScreen/MainWindow/Library/InspectorView.swift`
- Modify: `JuiceScreenTests/LibraryViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `JuiceScreenTests/LibraryViewModelTests.swift`:

```swift
    @Test("restoreSelected calls store.restore and reloads with the restored row visible")
    @MainActor
    func restoreSelectedRestoresRow() async throws {
        let store = FakeLibraryStore()
        let rowID = UUID()
        let trashed = sampleRow(uuid: rowID, deleted: true)
        try await store.insert(trashed)

        let thumbs = ThumbnailStore(paths: LibraryPaths())
        let vm = LibraryViewModel(store: store, thumbnailStore: thumbs)
        await vm.setFilter(.trash)
        vm.selectedID = rowID

        await vm.restoreSelected()

        // After restore, the row should no longer be in trash filter
        await vm.setFilter(.trash)
        #expect(vm.captures.isEmpty)

        await vm.setFilter(.all)
        #expect(vm.captures.contains { $0.uuid == rowID })
    }
```

(`sampleRow(uuid:deleted:)` already used in the FakeLibraryStore tests above. If `LibraryViewModelTests` doesn't have it, copy the helper or create a small inline one — match the existing pattern.)

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/LibraryViewModel/restoreSelectedRestoresRow`

Expected: BUILD FAILURE — `restoreSelected` not declared.

- [ ] **Step 3: Add restoreSelected to LibraryViewModel**

In `JuiceScreen/MainWindow/Library/LibraryViewModel.swift`, after `moveSelectedToTrash()`:

```swift
    public func restoreSelected() async {
        guard let id = selectedID else { return }
        do {
            try await store.restore(id: id)
            selectedID = nil
            await reload()
        } catch {
            log.error("restore failed: \(String(describing: error))")
        }
    }
```

- [ ] **Step 4: Add Restore button to InspectorView**

In `JuiceScreen/MainWindow/Library/InspectorView.swift`, replace the action-buttons block (the `VStack` containing `Open in Editor`, `Reveal in Finder`, etc.) with:

```swift
            // Action buttons
            VStack(alignment: .leading, spacing: 6) {
                if !row.isDeleted {
                    Button { onOpen(row) } label: {
                        Label("Open in Editor", systemImage: "pencil.tip.crop.circle")
                    }
                }
                Button { vm.revealSelectedInFinder() } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                Button { vm.copySelectedFile() } label: {
                    Label("Copy File", systemImage: "doc.on.doc")
                }
                if row.isDeleted {
                    Button {
                        Task { await vm.restoreSelected() }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button(role: .destructive) {
                        Task { await vm.moveSelectedToTrash() }
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                }
            }
            .buttonStyle(.bordered)
```

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/LibraryViewModel`

Expected: PASS — including the new restore test.

- [ ] **Step 6: Build the app**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS'`

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add JuiceScreen/MainWindow/Library/LibraryViewModel.swift JuiceScreen/MainWindow/Library/InspectorView.swift JuiceScreenTests/LibraryViewModelTests.swift
git commit -m "feat(library): restore-from-trash via inspector button"
```

---

### Task 17: README v0.9 paragraph + bump VERSION + tag + spec status

**Files:**
- Modify: `README.md`
- Modify: `VERSION`
- Modify: `project.yml` (`MARKETING_VERSION`)
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Add v0.9 paragraph to README**

In `README.md`, after the `**v0.8 update — scroll capture …**` paragraph (around line 22), insert:

```markdown
**v0.9 update — settings, PDF export, Sparkle wired.** The Settings panel is now real: General (start at login, save folder, default format, JPG quality), Capture (image scale, include cursor in stills), Recording (every toggle persists — fps, audio, cursor highlight, click pulse, keystrokes), Storage (usage stats, Open save folder, Empty trash now). The annotation editor's Save As dialog now offers PDF (rasterized — true vector PDF still v1.1). Sparkle 2.x is wired with `SUFeedURL` and an Info.plist `SUPublicEDKey` placeholder; the real EdDSA key, signed DMG, and the appcast at `https://mkupermann.github.io/JuiceScreen/appcast.xml` arrive in v1.0 (Plan 10). Until then the "Check for Updates Now" button will fail to find a feed — that is expected.
```

Update the Roadmap section line "settings + Sparkle (Plan 9)" → "settings + Sparkle + PDF (Plan 9, ✅ v0.9.0)".

- [ ] **Step 2: Bump VERSION**

`VERSION`:

```
0.9.0
```

- [ ] **Step 3: Bump MARKETING_VERSION in project.yml**

In `project.yml`, change:

```yaml
    MARKETING_VERSION: "0.8.0"
```

to:

```yaml
    MARKETING_VERSION: "0.9.0"
```

Then run `xcodegen generate`.

- [ ] **Step 4: Run full test suite**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests`

Expected: PASS — full test suite passes.

- [ ] **Step 5: Build app and smoke-launch**

Run: `xcodebuild -scheme JuiceScreen -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED.

Optional manual launch:

```bash
open "$(xcodebuild -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
```

Click menu bar → Settings → click through every tab. Toggle a Recording setting, close + reopen Settings, verify it persisted. Click About → "Check for Updates Now" → should bring up a Sparkle dialog (will report failure since no real appcast — that's expected).

- [ ] **Step 6: Update spec doc with Plan 9 status**

In `docs/superpowers/specs/2026-05-04-juicescreen-design.md`, find the `⬜ Plan 9: …` line in the implementation status section and replace it with:

```markdown
- ✅ **Plan 9: Settings + Sparkle + PDF** (v0.9.0, 2026-05-05) — All four Settings tabs are real forms backed by PreferencesStore; toggles persist across app launches. RecordingTab fully wired (fps, system audio, microphone, cursor highlight, click pulse, keystrokes). GeneralTab adds start-at-login (SMAppService), save folder picker, default format + JPG quality. CaptureTab offers image scale (Retina/1×) + include cursor in stills. StorageTab shows live capture count + bytes + trash size; "Open save folder" and "Empty trash now" (confirmation dialog → bulk delete via new LibraryStore.emptyTrash() + TrashService.permanentlyDelete). About tab adds "Check for Updates Now" button + auto-check toggle backed by Sparkle 2.6 (SPUStandardUpdaterController wrapped in SparkleUpdater). PDF export added via PDFEncoder + ExportService.Format.pdf; Save As panel allows .pdf. EdDSA public key is a placeholder — real key generation, DMG signing, and appcast publishing land in Plan 10. Inspector shows Restore button for trashed rows. ~245 unit tests across ~60 suites.
```

- [ ] **Step 7: Commit, tag, push**

```bash
git add README.md VERSION project.yml docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "chore: bump VERSION to 0.9.0 + README v0.9 + spec status"
git tag v0.9.0
```

---

## Self-review notes

- **Spec coverage:** Export pipeline → PDF (Tasks 1-3 ✓). Settings panel: General/Capture/Recording/Storage all real forms (Tasks 6-8, 15 ✓). About → Check for updates (Tasks 11-12 ✓). Sparkle setup (Tasks 10-12 ✓). Soft-delete completion: Empty trash + Restore (Tasks 13, 15, 16 ✓). Hotkeys tab record-to-set: deferred per ARGUMENTS — note the existing HotkeysTab is read-only; that stays.
- **Placeholder scan:** No "TBD" or hand-wave. Every code block is the actual file content. The one named placeholder — `SUPublicEDKey: "PLACEHOLDER_GENERATE_IN_PLAN_10"` — is a deliberate, documented stub that Plan 10 replaces.
- **Type consistency:** `emptyTrash()` returns `Int` everywhere (protocol, fake, live, tests). `StorageStats` field names match across compute(), tab display, and tests. `SparkleUpdater` API (`checkNow`, `isAutomaticChecksEnabled`, `lastCheckDate`) consistent across wrapper + AboutTab.
- **Known caveat:** Task 15's `StorageTab.reloadStats` opens a fresh `DatabaseQueue` per Settings open. Acceptable for v0.9 — the database file is small. If users complain about open delay we can pass the AppDelegate's existing `LibraryStore` via environment in v0.9.x.
