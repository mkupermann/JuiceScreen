# JuiceScreen — OCR + Search Implementation Plan (Plan 5 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.5.0` — every still capture from Plan 2 now runs through Apple's Vision framework after disk-write, extracting text and per-region bounding boxes. Concatenated text is written to the `captures_fts` FTS5 virtual table (created empty in Plan 4); per-region observations land in a JSON sidecar at `~/Library/Application Support/JuiceScreen/ocr/<uuid>.json`. The library window's search bar (built but disabled in Plan 4) becomes functional: type `aws error from:safari after:2026-04-15 type:image` and the parser splits free text from filters, FTS5 MATCHes the text terms, and SQL clauses apply the filters. Results rank by FTS5 BM25 with a recency-tiebreaker. The Inspector shows extracted OCR text. On first launch after upgrade, a one-time backfill OCRs every existing capture in the library that has no FTS5 entry yet.

**Architecture:** New `OCR/` module split into `Model/` (pure value types), `Service/` (Vision protocol + Live + Fake), `Pipeline/` (orchestrator that ties OCR → sidecar → FTS5), and `Search/` (query parser, no I/O). `LibraryStore` grows two methods (`upsertOCRText`, `search`); the FTS5 table created in Plan 4 finally gets populated. OCR runs on a background `DispatchQueue` (QoS `.utility`) so it never blocks UI or capture. The pipeline is fire-and-forget from `CaptureLibraryRecorder`'s perspective — failures log but never break capture. Search wiring: `LibraryViewModel.searchText` → debounced (300ms) → `setQuery(_)` → store.search → captures published.

**Tech Stack:** Vision framework (`VNRecognizeTextRequest`, `VNImageRequestHandler`) — already available, no new SPM deps. GRDB FTS5 access (already wired in Plan 4). Existing `LibraryPaths` extended with one new path. SwiftUI `@Observable` debouncing via `Task.sleep`. Swift Testing for unit tests of pure logic; Vision-touching code is verified manually via the smoke test in Task 19.

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — sections "OCR pipeline" and "Search UX".

**Plan 4 prerequisite:** v0.4.0 tagged. The `captures_fts` virtual table exists with columns `(uuid UNINDEXED, ocr_text, source_app, content='', tokenize='porter unicode61')` but no rows. `LibraryStoreLive` queue + `LibraryPaths.appSupportDirectory()` are available. `CaptureLibraryRecorder` actor is the integration point.

**Scope deferred to later plans:**

- **OCR on video frames** — explicitly deferred per spec ("NOT videos — OCR'ing video frames is a v1.1 conversation")
- **Per-region click-to-copy in InspectorView** — InspectorView shows the full text in v0.5; per-region UI with bounding-box highlights is a polish pass
- **Custom OCR language picker in Settings** — `recognitionLanguages` is hard-coded to `["en-US", "de-DE"]` for v0.5; user-configurable list lands when Settings get fully wired in Plan 9
- **"Index out of date" rebuild path** — backfill on launch handles missing FTS5 rows, but full corruption recovery (deleting + rebuilding the whole index) is a Plan 9 settings/storage chore

---

## File Structure

```
JuiceScreen/
├── OCR/
│   ├── Model/
│   │   ├── OCRRegion.swift                NEW — value type: text + normalized boundingBox CGRect
│   │   └── OCRResult.swift                NEW — fullText + [OCRRegion] + extractedAt Date
│   ├── Service/
│   │   ├── OCRService.swift               NEW — protocol + OCRError enum
│   │   ├── OCRServiceLive.swift           NEW — Vision-backed impl
│   │   └── FakeOCRService.swift           NEW — test double
│   ├── Pipeline/
│   │   ├── OCRSidecarStore.swift          NEW — JSON read/write at <appSupport>/ocr/<uuid>.json
│   │   └── OCRPipeline.swift              NEW — actor: process(captureID:fileURL:) → OCR → sidecar + store.upsertOCRText
│   └── Search/
│       ├── SearchQuery.swift              NEW — parsed query value type
│       └── SearchQueryParser.swift        NEW — pure string → SearchQuery
├── Library/
│   ├── Storage/
│   │   ├── LibraryStore.swift             MODIFY — add upsertOCRText + search methods
│   │   ├── LibraryStoreLive.swift         MODIFY — implement upsertOCRText (FTS5 INSERT) + search (FTS5 MATCH + filters + BM25 + recency)
│   │   └── FakeLibraryStore.swift         MODIFY — implement upsertOCRText (in-memory dict) + search (substring match + filters)
│   ├── Storage/
│   │   └── LibraryPaths.swift             MODIFY — add ocrDirectory() + ocrSidecarURL(for:)
│   └── CaptureLibraryRecorder.swift       MODIFY — fire-and-forget OCRPipeline.process after insert
├── MainWindow/
│   └── Library/
│       ├── LibraryViewModel.swift         MODIFY — searchText drives debounced reload + show OCR text on selection
│       ├── LibraryView.swift              MODIFY — enable search bar (remove .disabled)
│       └── InspectorView.swift            MODIFY — read OCR sidecar + display extracted text section
└── App/
    └── AppDelegate.swift                  MODIFY — instantiate OCRService + OCRSidecarStore + OCRPipeline; pass into recorder; run OCR backfill on launch

VERSION                                    MODIFY — bump to 0.5.0 (Task 19)
project.yml                                MODIFY — MARKETING_VERSION 0.5.0 (Task 19)
docs/superpowers/specs/2026-05-04-juicescreen-design.md  MODIFY — implementation status (Task 20)

JuiceScreenTests/
├── OCRRegionTests.swift                   NEW
├── OCRResultTests.swift                   NEW
├── FakeOCRServiceTests.swift              NEW
├── OCRSidecarStoreTests.swift             NEW
├── SearchQueryTests.swift                 NEW
├── SearchQueryParserTests.swift           NEW
├── LibraryStoreLiveSearchTests.swift      NEW
└── (existing test files extended in their own tasks)
```

---

## Task 1: `OCRRegion` + `OCRResult` value types + tests

**Files:**
- Create: `JuiceScreen/OCR/Model/OCRRegion.swift`
- Create: `JuiceScreen/OCR/Model/OCRResult.swift`
- Create: `JuiceScreenTests/OCRResultTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("OCRResult + OCRRegion")
struct OCRResultTests {

    @Test("OCRRegion stores text + normalized bounding box")
    func region() {
        let r = OCRRegion(text: "hello", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05))
        #expect(r.text == "hello")
        #expect(r.boundingBox.width == 0.3)
    }

    @Test("OCRResult fullText is the concatenation of region texts joined by newline")
    func fullText() {
        let regions = [
            OCRRegion(text: "first line", boundingBox: .zero),
            OCRRegion(text: "second line", boundingBox: .zero)
        ]
        let result = OCRResult(regions: regions, extractedAt: Date())
        #expect(result.fullText == "first line\nsecond line")
    }

    @Test("OCRResult fullText for empty regions is empty string")
    func emptyFullText() {
        let result = OCRResult(regions: [], extractedAt: Date())
        #expect(result.fullText == "")
    }

    @Test("OCRResult is Codable round-trip via JSONEncoder")
    func codable() throws {
        let original = OCRResult(
            regions: [
                OCRRegion(text: "alpha", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05)),
                OCRRegion(text: "beta", boundingBox: CGRect(x: 0.5, y: 0.6, width: 0.2, height: 0.04))
            ],
            extractedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OCRResult.self, from: data)
        #expect(decoded == original)
    }

    @Test("Equatable + Hashable")
    func equality() {
        let a = OCRResult(regions: [], extractedAt: Date(timeIntervalSince1970: 1))
        let b = OCRResult(regions: [], extractedAt: Date(timeIntervalSince1970: 1))
        let c = OCRResult(regions: [], extractedAt: Date(timeIntervalSince1970: 2))
        #expect(a == b)
        #expect(a != c)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/OCRResultTests 2>&1 | tail -8
```

Expected: compile failure — `OCRRegion` and `OCRResult` undefined.

- [ ] **Step 3: Implement `OCRRegion.swift`**

```swift
import CoreGraphics
import Foundation

/// One text region returned by Vision. `boundingBox` is in normalized
/// image coordinates (0–1) with the AppKit/Vision convention (origin top-left
/// for AppKit; Vision returns bottom-left, but we normalize to top-left at
/// extraction time in `OCRServiceLive`).
public struct OCRRegion: Equatable, Hashable, Sendable, Codable {
    public var text: String
    public var boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}
```

- [ ] **Step 4: Implement `OCRResult.swift`**

```swift
import Foundation

/// Output of a single OCR run: the per-region observations plus a derived
/// concatenated text and the extraction timestamp. Persisted as JSON
/// sidecar at `<appSupport>/ocr/<uuid>.json`.
public struct OCRResult: Equatable, Hashable, Sendable, Codable {
    public var regions: [OCRRegion]
    public var extractedAt: Date

    public init(regions: [OCRRegion], extractedAt: Date) {
        self.regions = regions
        self.extractedAt = extractedAt
    }

    /// Concatenation of region texts joined by newline. Empty string for empty regions.
    public var fullText: String {
        regions.map { $0.text }.joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/OCRResultTests 2>&1 | tail -10
```

Expected: 5/5 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/OCR/Model/OCRRegion.swift JuiceScreen/OCR/Model/OCRResult.swift JuiceScreenTests/OCRResultTests.swift
git commit -m "feat(ocr): OCRRegion + OCRResult Codable value types"
```

---

## Task 2: `OCRService` protocol + `FakeOCRService` + tests

**Files:**
- Create: `JuiceScreen/OCR/Service/OCRService.swift`
- Create: `JuiceScreen/OCR/Service/FakeOCRService.swift`
- Create: `JuiceScreenTests/FakeOCRServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeOCRService")
struct FakeOCRServiceTests {

    private func tempPNG() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OCRTest-\(UUID().uuidString).png")
        try Data("not a real png".utf8).write(to: url)
        return url
    }

    @Test("Returns the configured result for any URL")
    func returnsConfigured() async throws {
        let svc = FakeOCRService()
        let result = OCRResult(
            regions: [OCRRegion(text: "hello", boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))],
            extractedAt: Date()
        )
        svc.nextResult = .success(result)

        let url = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        let returned = try await svc.recognize(imageAt: url)
        #expect(returned == result)
    }

    @Test("Throws the configured error")
    func throwsConfigured() async throws {
        let svc = FakeOCRService()
        svc.nextResult = .failure(.imageLoadFailed)

        let url = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: OCRError.self) {
            _ = try await svc.recognize(imageAt: url)
        }
    }

    @Test("Records each call so tests can assert order")
    func recordsCalls() async throws {
        let svc = FakeOCRService()
        svc.nextResult = .success(OCRResult(regions: [], extractedAt: Date()))

        let url1 = try tempPNG()
        let url2 = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url1) }
        defer { try? FileManager.default.removeItem(at: url2) }

        _ = try await svc.recognize(imageAt: url1)
        _ = try await svc.recognize(imageAt: url2)

        #expect(svc.calls == [url1, url2])
    }

    @Test("Default unconfigured behaviour returns empty result")
    func defaultEmpty() async throws {
        let svc = FakeOCRService()
        let url = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await svc.recognize(imageAt: url)
        #expect(result.regions.isEmpty)
        #expect(result.fullText == "")
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeOCRServiceTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `OCRService.swift`**

```swift
import Foundation

public enum OCRError: Error, Equatable {
    case imageLoadFailed
    case recognitionFailed(String)
}

public protocol OCRService: Sendable {
    /// Runs OCR on the image at `url` and returns the result. Implementations
    /// MUST be safe to call from any context — the `Live` impl dispatches Vision
    /// onto a background queue internally.
    func recognize(imageAt url: URL) async throws -> OCRResult
}
```

- [ ] **Step 4: Implement `FakeOCRService.swift`**

```swift
import Foundation

public final class FakeOCRService: OCRService, @unchecked Sendable {

    public typealias Outcome = Result<OCRResult, OCRError>

    private let lock = NSLock()
    public var nextResult: Outcome?
    public private(set) var calls: [URL] = []

    public init() {}

    public func recognize(imageAt url: URL) async throws -> OCRResult {
        lock.lock()
        calls.append(url)
        let outcome = nextResult
        lock.unlock()

        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        case nil:
            return OCRResult(regions: [], extractedAt: Date())
        }
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeOCRServiceTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/OCR/Service/OCRService.swift JuiceScreen/OCR/Service/FakeOCRService.swift JuiceScreenTests/FakeOCRServiceTests.swift
git commit -m "feat(ocr): OCRService protocol + FakeOCRService test double"
```

---

## Task 3: `OCRServiceLive` (Vision-backed)

**Files:**
- Create: `JuiceScreen/OCR/Service/OCRServiceLive.swift`

(No automated test — wraps Vision framework which needs a real CGImage. Manual smoke test verifies it via the integration in Task 19.)

- [ ] **Step 1: Implement `OCRServiceLive.swift`**

```swift
import AppKit
import Foundation
import Vision

/// Production OCR service backed by Vision's `VNRecognizeTextRequest`.
/// Runs on a private dispatch queue at `.utility` QoS so capture/UI is never blocked.
public final class OCRServiceLive: OCRService {

    private let log = AppLog.logger(category: "OCRServiceLive")
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.ocr", qos: .utility)
    private let recognitionLanguages: [String]

    public init(recognitionLanguages: [String] = ["en-US", "de-DE"]) {
        self.recognitionLanguages = recognitionLanguages
    }

    public func recognize(imageAt url: URL) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<OCRResult, Error>) in
            queue.async {
                do {
                    let result = try Self.runVision(at: url, languages: self.recognitionLanguages)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Vision plumbing

    /// Synchronous Vision execution. Called on the OCR queue.
    private static func runVision(at url: URL, languages: [String]) throws -> OCRResult {
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.imageLoadFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        if #available(macOS 14, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.recognitionFailed("\(error)")
        }

        let observations = (request.results ?? [])
        let imgWidth = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)

        var regions: [OCRRegion] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            // Vision boundingBox is normalized (0–1) with origin BOTTOM-LEFT.
            // Convert to top-left convention (matches CGImage / our InspectorView).
            let bb = obs.boundingBox
            let topLeftBox = CGRect(
                x: bb.minX,
                y: 1.0 - bb.maxY,
                width: bb.width,
                height: bb.height
            )
            regions.append(OCRRegion(text: candidate.string, boundingBox: topLeftBox))

            // The pixel-space rect would be:
            //   CGRect(x: bb.minX*imgWidth, y: (1-bb.maxY)*imgHeight, ...)
            // We keep normalized so the InspectorView scales correctly with thumbnails.
            _ = imgWidth; _ = imgHeight
        }

        return OCRResult(regions: regions, extractedAt: Date())
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. (Compiler warnings about unused `imgWidth/imgHeight` are acceptable — they document the conversion path.)

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/OCR/Service/OCRServiceLive.swift
git commit -m "feat(ocr): OCRServiceLive — Vision VNRecognizeTextRequest with .accurate + en-US/de-DE"
```

---

## Task 4: `LibraryPaths` extension — OCR sidecar paths

**Files:**
- Modify: `JuiceScreen/Library/Storage/LibraryPaths.swift`
- Modify: `JuiceScreenTests/LibraryPathsTests.swift`

- [ ] **Step 1: Add the failing test**

Append to the existing `JuiceScreenTests/LibraryPathsTests.swift` `@Suite("LibraryPaths")` body:

```swift
    @Test("ocrDirectory is ocr/ under appSupportDirectory and is created on access")
    func ocrPath() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let paths = LibraryPaths(rootDirectory: tempRoot)
        let dir = try paths.ocrDirectory()
        #expect(dir.lastPathComponent == "ocr")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("ocrSidecarURL(for:) returns <ocr>/<uuid>.json")
    func ocrSidecarURL() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let paths = LibraryPaths(rootDirectory: tempRoot)
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let url = try paths.ocrSidecarURL(for: id)
        #expect(url.lastPathComponent == "11111111-2222-3333-4444-555555555555.json")
        #expect(url.path.contains("/ocr/"))
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryPathsTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Add methods to `LibraryPaths.swift`**

Add these two methods inside the `LibraryPaths` struct (before the closing brace):

```swift
    public func ocrDirectory() throws -> URL {
        let dir = try appSupportDirectory().appendingPathComponent("ocr", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func ocrSidecarURL(for id: UUID) throws -> URL {
        try ocrDirectory()
            .appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryPathsTests 2>&1 | tail -10
```

Expected: 6/6 pass (4 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryPaths.swift JuiceScreenTests/LibraryPathsTests.swift
git commit -m "feat(library): LibraryPaths.ocrDirectory + ocrSidecarURL"
```

---

## Task 5: `OCRSidecarStore` + tests

**Files:**
- Create: `JuiceScreen/OCR/Pipeline/OCRSidecarStore.swift`
- Create: `JuiceScreenTests/OCRSidecarStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("OCRSidecarStore")
struct OCRSidecarStoreTests {

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    @Test("write + read round-trip preserves the OCRResult")
    func roundTrip() throws {
        let paths = makeTempPaths()
        let store = OCRSidecarStore(paths: paths)
        let id = UUID()
        let original = OCRResult(
            regions: [
                OCRRegion(text: "alpha", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.04)),
                OCRRegion(text: "beta", boundingBox: CGRect(x: 0.5, y: 0.6, width: 0.2, height: 0.04))
            ],
            extractedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )

        try store.write(original, for: id)
        let loaded = try #require(try store.read(for: id))
        #expect(loaded == original)
    }

    @Test("read returns nil if sidecar does not exist")
    func readMissing() throws {
        let paths = makeTempPaths()
        let store = OCRSidecarStore(paths: paths)
        let result = try store.read(for: UUID())
        #expect(result == nil)
    }

    @Test("delete removes the sidecar; second delete is a no-op")
    func deleteSidecar() throws {
        let paths = makeTempPaths()
        let store = OCRSidecarStore(paths: paths)
        let id = UUID()
        try store.write(OCRResult(regions: [], extractedAt: Date()), for: id)
        try store.delete(for: id)
        try store.delete(for: id)
        #expect(try store.read(for: id) == nil)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/OCRSidecarStoreTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `OCRSidecarStore.swift`**

```swift
import Foundation

public struct OCRSidecarStore: Sendable {

    private let paths: LibraryPaths
    private let fileManager: FileManager

    public init(paths: LibraryPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func write(_ result: OCRResult, for id: UUID) throws {
        let url = try paths.ocrSidecarURL(for: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(result)
        try data.write(to: url, options: .atomic)
    }

    public func read(for id: UUID) throws -> OCRResult? {
        let url = try paths.ocrSidecarURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(OCRResult.self, from: data)
    }

    public func delete(for id: UUID) throws {
        let url = try paths.ocrSidecarURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/OCRSidecarStoreTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/OCR/Pipeline/OCRSidecarStore.swift JuiceScreenTests/OCRSidecarStoreTests.swift
git commit -m "feat(ocr): OCRSidecarStore JSON write/read/delete at <appSupport>/ocr/<uuid>.json"
```

---

## Task 6: `SearchQuery` + tests

**Files:**
- Create: `JuiceScreen/OCR/Search/SearchQuery.swift`
- Create: `JuiceScreenTests/SearchQueryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("SearchQuery")
struct SearchQueryTests {

    @Test("Empty query: no terms, no filters")
    func empty() {
        let q = SearchQuery()
        #expect(q.text == "")
        #expect(q.sourceApp == nil)
        #expect(q.before == nil)
        #expect(q.after == nil)
        #expect(q.mediaType == nil)
        #expect(q.isEmpty)
    }

    @Test("isEmpty false if any field set")
    func notEmpty() {
        var q = SearchQuery()
        q.text = "hello"
        #expect(q.isEmpty == false)

        q = SearchQuery()
        q.sourceApp = "Safari"
        #expect(q.isEmpty == false)

        q = SearchQuery()
        q.mediaType = .image
        #expect(q.isEmpty == false)
    }

    @Test("Equality is value-based")
    func equality() {
        var a = SearchQuery()
        a.text = "aws error"
        a.sourceApp = "Safari"
        var b = SearchQuery()
        b.text = "aws error"
        b.sourceApp = "Safari"
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SearchQueryTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `SearchQuery.swift`**

```swift
import Foundation

public struct SearchQuery: Equatable, Sendable {
    /// Free-text search terms (will become an FTS5 MATCH expression).
    public var text: String = ""

    /// Filter on `source_app` column. Case-insensitive equality match.
    public var sourceApp: String?

    /// Inclusive upper bound on `captured_at`.
    public var before: Date?

    /// Inclusive lower bound on `captured_at`.
    public var after: Date?

    /// Filter on media type column.
    public var mediaType: MediaType?

    public init() {}

    public var isEmpty: Bool {
        text.isEmpty && sourceApp == nil && before == nil && after == nil && mediaType == nil
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SearchQueryTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/OCR/Search/SearchQuery.swift JuiceScreenTests/SearchQueryTests.swift
git commit -m "feat(search): SearchQuery value type (text + sourceApp + before/after + mediaType)"
```

---

## Task 7: `SearchQueryParser` + tests

**Files:**
- Create: `JuiceScreen/OCR/Search/SearchQueryParser.swift`
- Create: `JuiceScreenTests/SearchQueryParserTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("SearchQueryParser")
struct SearchQueryParserTests {

    private func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    @Test("Empty input → empty query")
    func empty() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("")
        #expect(q.isEmpty)
    }

    @Test("Bare words become free text")
    func freeText() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("aws error")
        #expect(q.text == "aws error")
        #expect(q.sourceApp == nil)
    }

    @Test("from:safari → sourceApp")
    func fromFilter() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("from:Safari")
        #expect(q.text == "")
        #expect(q.sourceApp == "Safari")
    }

    @Test("before:2026-04-01 + after:2026-04-15 → date range")
    func dateRange() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("after:2026-04-15 before:2026-05-01")
        #expect(q.after == ymd(2026, 4, 15))
        #expect(q.before == ymd(2026, 5, 1))
    }

    @Test("type:image / type:video → mediaType")
    func typeFilter() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        #expect(parser.parse("type:image").mediaType == .image)
        #expect(parser.parse("type:video").mediaType == .video)
        #expect(parser.parse("type:bogus").mediaType == nil)   // unknown values ignored
    }

    @Test("Combined: free text + filters parses everything")
    func combined() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("aws error from:Safari after:2026-04-15 type:image")
        #expect(q.text == "aws error")
        #expect(q.sourceApp == "Safari")
        #expect(q.after == ymd(2026, 4, 15))
        #expect(q.mediaType == .image)
    }

    @Test("Filter tokens preserved in original casing for sourceApp; type/before/after lowercased")
    func casing() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("FROM:Safari TYPE:IMAGE")
        #expect(q.sourceApp == "Safari")
        #expect(q.mediaType == .image)
    }

    @Test("Malformed date strings are silently dropped")
    func malformedDate() {
        var parser = SearchQueryParser()
        parser.calendar = utcCalendar()
        let q = parser.parse("before:not-a-date")
        #expect(q.before == nil)
    }

    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SearchQueryParserTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `SearchQueryParser.swift`**

```swift
import Foundation

public struct SearchQueryParser {

    public var calendar: Calendar = .current

    public init() {}

    public func parse(_ input: String) -> SearchQuery {
        var query = SearchQuery()
        var freeTextTokens: [String] = []

        let tokens = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for raw in tokens {
            // Normalize key:value tokens by lowercasing the key only.
            if let colonIndex = raw.firstIndex(of: ":") {
                let key = raw[..<colonIndex].lowercased()
                let value = String(raw[raw.index(after: colonIndex)...])
                if applyFilter(key: key, value: value, into: &query) {
                    continue
                }
            }
            freeTextTokens.append(raw)
        }

        query.text = freeTextTokens.joined(separator: " ")
        return query
    }

    /// Returns true if the token matched a known filter (and was applied).
    private func applyFilter(key: String, value: String, into query: inout SearchQuery) -> Bool {
        switch key {
        case "from":
            guard !value.isEmpty else { return false }
            query.sourceApp = value
            return true
        case "type":
            if let mt = MediaType(rawValue: value.lowercased()) {
                query.mediaType = mt
            }
            return true
        case "before":
            if let date = parseDate(value) {
                query.before = date
            }
            return true
        case "after":
            if let date = parseDate(value) {
                query.after = date
            }
            return true
        default:
            return false
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return calendar.date(from: c)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/SearchQueryParserTests 2>&1 | tail -10
```

Expected: 8/8 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/OCR/Search/SearchQueryParser.swift JuiceScreenTests/SearchQueryParserTests.swift
git commit -m "feat(search): SearchQueryParser handles free text + from:/type:/before:/after:"
```

---

## Task 8: `LibraryStore` + `FakeLibraryStore` — add `upsertOCRText` + `search`

**Files:**
- Modify: `JuiceScreen/Library/Storage/LibraryStore.swift`
- Modify: `JuiceScreen/Library/Storage/FakeLibraryStore.swift`
- Modify: `JuiceScreenTests/FakeLibraryStoreTests.swift`

- [ ] **Step 1: Add the failing test cases**

Append to `JuiceScreenTests/FakeLibraryStoreTests.swift` `@Suite("FakeLibraryStore")` body:

```swift
    @Test("upsertOCRText stores text per id; search returns rows whose ocr text matches")
    func upsertAndSearch() async throws {
        let store = FakeLibraryStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "Hello AWS error log")

        var q = SearchQuery()
        q.text = "AWS"
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == row.uuid)
    }

    @Test("search filters: from + after + type combine")
    func combinedSearch() async throws {
        let store = FakeLibraryStore()
        let cal = Calendar(identifier: .gregorian)

        let safariImage = makeRow(daysAgo: 1, mediaType: .image)
        try await store.insert(CaptureRow(
            uuid: safariImage.uuid, filePath: safariImage.filePath, annotationPath: nil,
            thumbnailPath: safariImage.thumbnailPath, mediaType: .image,
            capturedAt: safariImage.capturedAt, pixelWidth: 100, pixelHeight: 100,
            durationMs: nil, fileSizeBytes: 100, sourceApp: "Safari", deletedAt: nil))

        let chromeImage = makeRow(daysAgo: 1)
        try await store.insert(CaptureRow(
            uuid: chromeImage.uuid, filePath: chromeImage.filePath, annotationPath: nil,
            thumbnailPath: chromeImage.thumbnailPath, mediaType: .image,
            capturedAt: chromeImage.capturedAt, pixelWidth: 100, pixelHeight: 100,
            durationMs: nil, fileSizeBytes: 100, sourceApp: "Chrome", deletedAt: nil))

        var q = SearchQuery()
        q.sourceApp = "Safari"
        q.after = cal.date(byAdding: .day, value: -2, to: Date())
        q.mediaType = .image

        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == safariImage.uuid)
    }

    @Test("Empty query returns all live captures (newest first)")
    func emptyQueryReturnsAll() async throws {
        let store = FakeLibraryStore()
        let oldest = makeRow(daysAgo: 5)
        let newest = makeRow(daysAgo: 0)
        try await store.insert(oldest)
        try await store.insert(newest)

        let hits = try await store.search(query: SearchQuery())
        #expect(hits.map { $0.uuid } == [newest.uuid, oldest.uuid])
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeLibraryStoreTests 2>&1 | tail -8
```

Expected: compile failure (`upsertOCRText` and `search` undefined).

- [ ] **Step 3: Add to `LibraryStore.swift` protocol**

Add these two methods inside the `LibraryStore` protocol (before the closing brace):

```swift
    /// Writes the concatenated OCR text for a capture into the FTS5 index.
    /// Idempotent — replaces any existing entry for the same id.
    func upsertOCRText(id: UUID, text: String) async throws

    /// Returns live (non-deleted) captures matching the parsed query.
    /// Empty query returns all live captures ordered by `captured_at` descending.
    func search(query: SearchQuery) async throws -> [CaptureRow]
```

- [ ] **Step 4: Implement in `FakeLibraryStore.swift`**

Add these two stored properties (alongside `rows`) — replace the `rows` declaration:

```swift
    private var rows: [UUID: CaptureRow] = [:]
    private var ocrText: [UUID: String] = [:]
```

Add the two methods inside the class (before the closing brace, after the existing helpers):

```swift
    public func upsertOCRText(id: UUID, text: String) async throws {
        lock.lock(); defer { lock.unlock() }
        ocrText[id] = text
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
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeLibraryStoreTests 2>&1 | tail -10
```

Expected: 12/12 pass (9 prior + 3 new).

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStore.swift JuiceScreen/Library/Storage/FakeLibraryStore.swift JuiceScreenTests/FakeLibraryStoreTests.swift
git commit -m "feat(library): LibraryStore.upsertOCRText + search; FakeLibraryStore impl"
```

---

## Task 9: `LibraryStoreLive` — implement `upsertOCRText` + `search` (FTS5) + tests

**Files:**
- Modify: `JuiceScreen/Library/Storage/LibraryStoreLive.swift`
- Create: `JuiceScreenTests/LibraryStoreLiveSearchTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibraryStoreLive — search + OCR")
struct LibraryStoreLiveSearchTests {

    private func makeStore() throws -> LibraryStoreLive {
        let queue = try DatabaseQueue()
        try LibrarySchema.migrator().migrate(queue)
        return LibraryStoreLive(databaseQueue: queue)
    }

    private func makeRow(daysAgo: Int = 0, mediaType: MediaType = .image, sourceApp: String? = nil) -> CaptureRow {
        // Truncate to whole seconds so SQLite int round-trip preserves equality
        let secs = floor(Date().timeIntervalSince1970)
            - Double(daysAgo) * 86400
        return CaptureRow(
            uuid: UUID(),
            filePath: "/tmp/\(UUID().uuidString).png",
            annotationPath: nil,
            thumbnailPath: "/tmp/thumb-\(UUID().uuidString).jpg",
            mediaType: mediaType,
            capturedAt: Date(timeIntervalSince1970: secs),
            pixelWidth: 100, pixelHeight: 100,
            durationMs: nil, fileSizeBytes: 100,
            sourceApp: sourceApp, deletedAt: nil
        )
    }

    @Test("upsertOCRText then search by free text returns the row")
    func upsertAndSearch() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "AWS error message at 12:34")

        var q = SearchQuery()
        q.text = "AWS"
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == row.uuid)
    }

    @Test("upsertOCRText is idempotent")
    func upsertReplaces() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "first")
        try await store.upsertOCRText(id: row.uuid, text: "second")

        var q = SearchQuery()
        q.text = "second"
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)

        q.text = "first"
        let stale = try await store.search(query: q)
        #expect(stale.isEmpty)
    }

    @Test("Empty query returns all live captures, ordered by captured_at desc")
    func emptyQueryAll() async throws {
        let store = try makeStore()
        let oldest = makeRow(daysAgo: 5)
        let newest = makeRow(daysAgo: 0)
        try await store.insert(oldest)
        try await store.insert(newest)

        let hits = try await store.search(query: SearchQuery())
        #expect(hits.map { $0.uuid } == [newest.uuid, oldest.uuid])
    }

    @Test("from:Safari + type:image filters apply alongside FTS5 MATCH")
    func combinedFilters() async throws {
        let store = try makeStore()
        let safari = makeRow(sourceApp: "Safari")
        let chrome = makeRow(sourceApp: "Chrome")
        try await store.insert(safari)
        try await store.insert(chrome)
        try await store.upsertOCRText(id: safari.uuid, text: "Hello AWS")
        try await store.upsertOCRText(id: chrome.uuid, text: "Hello AWS")

        var q = SearchQuery()
        q.text = "AWS"
        q.sourceApp = "Safari"
        q.mediaType = .image
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == safari.uuid)
    }

    @Test("after + before filters bound captured_at range")
    func dateRange() async throws {
        let store = try makeStore()
        let cal = Calendar.current
        let dayOld = makeRow(daysAgo: 1)
        let weekOld = makeRow(daysAgo: 7)
        try await store.insert(dayOld)
        try await store.insert(weekOld)

        var q = SearchQuery()
        q.after = cal.date(byAdding: .day, value: -3, to: Date())
        let hits = try await store.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == dayOld.uuid)
    }

    @Test("Soft-deleted rows are excluded from search")
    func excludeDeleted() async throws {
        let store = try makeStore()
        let row = makeRow()
        try await store.insert(row)
        try await store.upsertOCRText(id: row.uuid, text: "find me")
        try await store.softDelete(id: row.uuid)

        var q = SearchQuery()
        q.text = "find me"
        let hits = try await store.search(query: q)
        #expect(hits.isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryStoreLiveSearchTests 2>&1 | tail -8
```

Expected: compile failure (`upsertOCRText` and `search` not implemented in `LibraryStoreLive`).

- [ ] **Step 3: Add `upsertOCRText` + `search` to `LibraryStoreLive.swift`**

Add these two public methods inside the `LibraryStoreLive` class (before the `// MARK: - Mapping` section):

```swift
    public func upsertOCRText(id: UUID, text: String) async throws {
        try await databaseQueue.write { db in
            // FTS5 with `content=''` (external content) — we just delete + insert.
            try db.execute(
                sql: "DELETE FROM captures_fts WHERE uuid = ?",
                arguments: [id.uuidString]
            )
            try db.execute(
                sql: "INSERT INTO captures_fts (uuid, ocr_text, source_app) VALUES (?, ?, ?)",
                arguments: [id.uuidString, text, ""]
            )
        }
    }

    public func search(query: SearchQuery) async throws -> [CaptureRow] {
        try await databaseQueue.read { db in
            var conditions: [String] = ["captures.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible?] = []

            // Filters that always apply at the captures-row level
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
                    JOIN captures_fts ON captures_fts.uuid = captures.uuid
                    WHERE \(conditions.joined(separator: " AND "))
                    ORDER BY rank, captures.captured_at DESC
                """
            }

            let rows = try Row.fetchAll(db, sql: sql,
                                        arguments: StatementArguments(args))
            return rows.map(Self.makeRow(from:))
        }
    }

    /// Wraps each whitespace-delimited token in double quotes so FTS5 treats it
    /// as a literal phrase (no operator interpretation) and adds prefix `*`
    /// for partial-word matches. `aws error` → `"aws"* "error"*`.
    private static func toFTS5MatchExpression(_ text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true)
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryStoreLiveSearchTests 2>&1 | tail -10
```

Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStoreLive.swift JuiceScreenTests/LibraryStoreLiveSearchTests.swift
git commit -m "feat(library): LibraryStoreLive search via FTS5 MATCH + filters + recency tiebreaker"
```

---

## Task 10: `OCRPipeline` actor + tests

**Files:**
- Create: `JuiceScreen/OCR/Pipeline/OCRPipeline.swift`
- Create: `JuiceScreenTests/OCRPipelineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("OCRPipeline")
struct OCRPipelineTests {

    private func makeTempPaths() -> LibraryPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JuiceScreenTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryPaths(rootDirectory: root)
    }

    private func tempPNG() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OCRPipelineTest-\(UUID().uuidString).png")
        try Data("not a real png".utf8).write(to: url)
        return url
    }

    @Test("process(captureID:fileURL:) writes sidecar + upserts FTS5 text")
    func process() async throws {
        let paths = makeTempPaths()
        let sidecarStore = OCRSidecarStore(paths: paths)
        let libraryStore = FakeLibraryStore()
        let ocr = FakeOCRService()
        ocr.nextResult = .success(OCRResult(
            regions: [
                OCRRegion(text: "Hello", boundingBox: .zero),
                OCRRegion(text: "World", boundingBox: .zero)
            ],
            extractedAt: Date(timeIntervalSince1970: 1)
        ))

        // Insert a row first so search() can see it
        let row = CaptureRow(
            uuid: UUID(), filePath: "/tmp/x.png", annotationPath: nil, thumbnailPath: "/t",
            mediaType: .image, capturedAt: Date(),
            pixelWidth: 1, pixelHeight: 1, durationMs: nil,
            fileSizeBytes: 0, sourceApp: nil, deletedAt: nil
        )
        try await libraryStore.insert(row)

        let pipeline = OCRPipeline(
            ocrService: ocr,
            sidecarStore: sidecarStore,
            libraryStore: libraryStore
        )

        let url = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        try await pipeline.process(captureID: row.uuid, fileURL: url)

        // Sidecar exists with the result
        let loaded = try sidecarStore.read(for: row.uuid)
        #expect(loaded?.regions.count == 2)

        // FTS5 has the concatenated text
        var q = SearchQuery()
        q.text = "Hello"
        let hits = try await libraryStore.search(query: q)
        #expect(hits.count == 1)
        #expect(hits.first!.uuid == row.uuid)
    }

    @Test("OCR failure: pipeline logs but does not propagate the error")
    func failureSwallowed() async throws {
        let paths = makeTempPaths()
        let sidecarStore = OCRSidecarStore(paths: paths)
        let libraryStore = FakeLibraryStore()
        let ocr = FakeOCRService()
        ocr.nextResult = .failure(.imageLoadFailed)

        let pipeline = OCRPipeline(
            ocrService: ocr,
            sidecarStore: sidecarStore,
            libraryStore: libraryStore
        )

        let url = try tempPNG()
        defer { try? FileManager.default.removeItem(at: url) }
        // Should not throw — pipeline catches OCRError and logs
        try await pipeline.process(captureID: UUID(), fileURL: url)

        // No sidecar written
        let loaded = try sidecarStore.read(for: UUID())
        #expect(loaded == nil)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/OCRPipelineTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `OCRPipeline.swift`**

```swift
import Foundation

/// Orchestrator that runs OCR on a capture's image file and persists the result.
/// Fire-and-forget from `CaptureLibraryRecorder`'s perspective: errors log but
/// never bubble up to disrupt the capture flow.
public actor OCRPipeline {

    private let ocrService: OCRService
    private let sidecarStore: OCRSidecarStore
    private let libraryStore: LibraryStore
    private let log = AppLog.logger(category: "OCRPipeline")

    public init(ocrService: OCRService, sidecarStore: OCRSidecarStore, libraryStore: LibraryStore) {
        self.ocrService = ocrService
        self.sidecarStore = sidecarStore
        self.libraryStore = libraryStore
    }

    public func process(captureID: UUID, fileURL: URL) async throws {
        do {
            let result = try await ocrService.recognize(imageAt: fileURL)
            try sidecarStore.write(result, for: captureID)
            try await libraryStore.upsertOCRText(id: captureID, text: result.fullText)
            log.info("OCR succeeded for \(captureID): \(result.regions.count) regions")
        } catch let error as OCRError {
            log.error("OCR failed for \(captureID): \(String(describing: error))")
            // swallow — capture still works without OCR
        } catch {
            log.error("OCR pipeline error for \(captureID): \(String(describing: error))")
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/OCRPipelineTests 2>&1 | tail -10
```

Expected: 2/2 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/OCR/Pipeline/OCRPipeline.swift JuiceScreenTests/OCRPipelineTests.swift
git commit -m "feat(ocr): OCRPipeline actor — OCR → sidecar + FTS5 upsert (fire-and-forget)"
```

---

## Task 11: `CaptureLibraryRecorder` — fire OCR pipeline after insert

**Files:**
- Modify: `JuiceScreen/Library/CaptureLibraryRecorder.swift`

- [ ] **Step 1: Add an optional OCRPipeline dependency**

Replace the existing class definition. Updated content:

```swift
import AppKit
import Foundation

/// Glue service: after a successful capture, generates a thumbnail and inserts a
/// `CaptureRow` into the `LibraryStore`. Optionally fires an OCR pipeline that
/// extracts text and indexes it in FTS5 (Plan 5).
public actor CaptureLibraryRecorder {

    private let store: LibraryStore
    private let thumbnailStore: ThumbnailStore
    private let ocrPipeline: OCRPipeline?
    private let log = AppLog.logger(category: "CaptureLibraryRecorder")

    public init(store: LibraryStore, thumbnailStore: ThumbnailStore, ocrPipeline: OCRPipeline? = nil) {
        self.store = store
        self.thumbnailStore = thumbnailStore
        self.ocrPipeline = ocrPipeline
    }

    public func record(_ record: CaptureRecord) async throws {
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

        // Fire-and-forget OCR. Failures are caught by the pipeline; we don't await it
        // because we don't want to gate the editor's open or the menu's responsiveness on Vision.
        if let pipeline = ocrPipeline {
            Task.detached { [pipeline, captureID = record.id, fileURL = record.fileURL] in
                try? await pipeline.process(captureID: captureID, fileURL: fileURL)
            }
        }
    }
}
```

- [ ] **Step 2: Verify the existing `CaptureLibraryRecorderTests` still pass**

The previous tests don't pass an `ocrPipeline` (default nil), so they should still work.

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureLibraryRecorderTests 2>&1 | tail -10
```

Expected: 1/1 pass.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Library/CaptureLibraryRecorder.swift
git commit -m "feat(library): CaptureLibraryRecorder fires OCRPipeline after row insert"
```

---

## Task 12: `LibraryViewModel` — debounced search drives reload

**Files:**
- Modify: `JuiceScreen/MainWindow/Library/LibraryViewModel.swift`
- Modify: `JuiceScreenTests/LibraryViewModelTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `JuiceScreenTests/LibraryViewModelTests.swift`:

```swift
    @Test("Setting searchText to a parsed query causes reload to use store.search")
    func searchTextDrivesSearch() async throws {
        let store = FakeLibraryStore()
        let safari = makeRow()
        try await store.insert(CaptureRow(
            uuid: safari.uuid, filePath: safari.filePath, annotationPath: nil,
            thumbnailPath: safari.thumbnailPath, mediaType: .image,
            capturedAt: safari.capturedAt, pixelWidth: 100, pixelHeight: 100,
            durationMs: nil, fileSizeBytes: 100, sourceApp: "Safari", deletedAt: nil))

        let chrome = makeRow()
        try await store.insert(CaptureRow(
            uuid: chrome.uuid, filePath: chrome.filePath, annotationPath: nil,
            thumbnailPath: chrome.thumbnailPath, mediaType: .image,
            capturedAt: chrome.capturedAt, pixelWidth: 100, pixelHeight: 100,
            durationMs: nil, fileSizeBytes: 100, sourceApp: "Chrome", deletedAt: nil))

        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        vm.searchText = "from:Safari"
        await vm.runSearchNow()   // bypasses debounce for testing

        #expect(vm.captures.count == 1)
        #expect(vm.captures.first!.uuid == safari.uuid)
    }

    @Test("Empty searchText falls back to filter-based reload")
    func emptySearchUsesFilter() async throws {
        let store = FakeLibraryStore()
        try await store.insert(makeRow())
        let vm = LibraryViewModel(store: store, thumbnailStore: ThumbnailStore(paths: LibraryPaths()))
        vm.searchText = ""
        await vm.runSearchNow()
        #expect(vm.captures.count == 1)
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryViewModelTests 2>&1 | tail -8
```

Expected: compile failure (`runSearchNow` undefined).

- [ ] **Step 3: Add search wiring to `LibraryViewModel.swift`**

In `JuiceScreen/MainWindow/Library/LibraryViewModel.swift`, add a `parser` instance + `searchDebounceTask`, and replace the `searchText` declaration with one that triggers debounced search. Also expose `runSearchNow()` for tests.

Updated additions inside the class (place the new fields + methods in the correct positions):

```swift
    /// Replaces the existing `searchText` declaration: triggers a debounced search on change.
    public var searchText: String = "" {
        didSet { scheduleDebouncedSearch() }
    }

    private let parser = SearchQueryParser()
    private var searchDebounceTask: Task<Void, Never>?
    private static let debounceMillis: UInt64 = 300

    private func scheduleDebouncedSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceMillis * 1_000_000)
            guard let self, !Task.isCancelled else { return }
            await runSearchNow()
        }
    }

    /// Test-friendly entry point that skips the debounce.
    public func runSearchNow() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await reload()
            return
        }
        let q = parser.parse(trimmed)
        do {
            captures = try await store.search(query: q)
        } catch {
            log.error("Search failed: \(String(describing: error))")
            captures = []
        }
    }
```

(NOTE: there is currently a stored property `public var searchText: String = ""` in `LibraryViewModel`. The replacement above changes it to a property with `didSet`. Keep all other properties unchanged.)

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/LibraryViewModelTests 2>&1 | tail -10
```

Expected: 6/6 pass (4 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/MainWindow/Library/LibraryViewModel.swift JuiceScreenTests/LibraryViewModelTests.swift
git commit -m "feat(library): LibraryViewModel searchText triggers debounced (300ms) FTS5 search"
```

---

## Task 13: `LibraryView` — enable search bar

**Files:**
- Modify: `JuiceScreen/MainWindow/Library/LibraryView.swift`

- [ ] **Step 1: Remove `.disabled(true)` and update placeholder**

In `JuiceScreen/MainWindow/Library/LibraryView.swift`, find the existing `searchBar` computed property:

```swift
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
```

Replace with the enabled version:

```swift
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search OCR text (e.g. \"aws error from:Safari after:2026-04-15\")", text: $vm.searchText)
                .textFieldStyle(.plain)
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
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
git commit -m "feat(library): enable search bar with clear button + parser hint placeholder"
```

---

## Task 14: `InspectorView` — show OCR text from sidecar

**Files:**
- Modify: `JuiceScreen/MainWindow/Library/InspectorView.swift`

- [ ] **Step 1: Read OCR sidecar on selection change + display extracted text**

Replace the OCR placeholder block in `InspectorView.swift`:

```swift
            // OCR placeholder (Plan 5)
            VStack(alignment: .leading, spacing: 4) {
                Text("OCR Text").font(.caption).foregroundStyle(.secondary)
                Text("Extracted text will appear here in v0.5 (Plan 5).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
```

with a state-backed loader that reads the OCR sidecar:

```swift
            VStack(alignment: .leading, spacing: 4) {
                Text("OCR Text")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let text = ocrText, !text.isEmpty {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 160)

                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    } label: {
                        Label("Copy text", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                } else if ocrText == nil {
                    Text("OCR pending…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .italic()
                } else {
                    Text("No text recognised.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
            .task(id: row.uuid) {
                await loadOCR()
            }
```

Add the supporting state + loader at the top of the struct (after the existing properties):

```swift
    @State private var ocrText: String? = nil

    private func loadOCR() async {
        let paths = LibraryPaths()
        let store = OCRSidecarStore(paths: paths)
        do {
            if let result = try store.read(for: row.uuid) {
                ocrText = result.fullText
            } else {
                ocrText = nil
            }
        } catch {
            ocrText = nil
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
git commit -m "feat(library): InspectorView reads OCR sidecar and shows extracted text"
```

---

## Task 15: `AppDelegate` — instantiate OCR pipeline + wire into recorder

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Add OCR services + pass into recorder**

In `JuiceScreen/App/AppDelegate.swift`, add new lazy properties after `thumbnailStore`:

```swift
    private lazy var ocrService: OCRService = OCRServiceLive()

    private lazy var ocrSidecarStore: OCRSidecarStore = OCRSidecarStore(paths: libraryPaths)

    private lazy var ocrPipeline: OCRPipeline = {
        OCRPipeline(
            ocrService: ocrService,
            sidecarStore: ocrSidecarStore,
            libraryStore: libraryStore
        )
    }()
```

Replace the existing `captureLibraryRecorder` lazy property to pass the OCR pipeline:

```swift
    private lazy var captureLibraryRecorder: CaptureLibraryRecorder = {
        CaptureLibraryRecorder(
            store: libraryStore,
            thumbnailStore: thumbnailStore,
            ocrPipeline: ocrPipeline
        )
    }()
```

- [ ] **Step 2: Verify build + tests**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: build succeeds and all unit tests still pass (~175 across many suites).

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): instantiate OCRPipeline + wire into CaptureLibraryRecorder"
```

---

## Task 16: OCR backfill on first launch after upgrade

**Files:**
- Create: `JuiceScreen/OCR/Pipeline/OCRBackfill.swift`
- Modify: `JuiceScreen/App/AppDelegate.swift`
- Modify: `JuiceScreen/Library/Storage/LibraryStore.swift`
- Modify: `JuiceScreen/Library/Storage/LibraryStoreLive.swift`
- Modify: `JuiceScreen/Library/Storage/FakeLibraryStore.swift`

- [ ] **Step 1: Add `LibraryStore.captureIDsWithoutOCR` method to the protocol**

In `JuiceScreen/Library/Storage/LibraryStore.swift`, add:

```swift
    /// Returns UUIDs of live captures that have no entry in `captures_fts`.
    /// Used by the launch-time OCR backfill to find captures captured before Plan 5.
    func captureIDsWithoutOCR() async throws -> [(id: UUID, filePath: String)]
```

- [ ] **Step 2: Implement in `LibraryStoreLive.swift`**

Add inside the class:

```swift
    public func captureIDsWithoutOCR() async throws -> [(id: UUID, filePath: String)] {
        try await databaseQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT captures.uuid, captures.file_path
                FROM captures
                LEFT JOIN captures_fts ON captures_fts.uuid = captures.uuid
                WHERE captures.deleted_at IS NULL
                  AND captures.media_type = 'image'
                  AND captures_fts.uuid IS NULL
                ORDER BY captures.captured_at DESC
            """)
            return rows.compactMap { row -> (UUID, String)? in
                guard let id = UUID(uuidString: row["uuid"]) else { return nil }
                return (id, row["file_path"])
            }
        }
    }
```

- [ ] **Step 3: Implement in `FakeLibraryStore.swift`**

Add inside the class:

```swift
    public func captureIDsWithoutOCR() async throws -> [(id: UUID, filePath: String)] {
        lock.lock(); defer { lock.unlock() }
        return rows.values
            .filter { !$0.isDeleted && $0.mediaType == .image && ocrText[$0.uuid] == nil }
            .sorted { $0.capturedAt > $1.capturedAt }
            .map { ($0.uuid, $0.filePath) }
    }
```

- [ ] **Step 4: Implement `OCRBackfill.swift`**

```swift
import Foundation

/// One-shot launch-time service: finds image captures without an FTS5 entry
/// and runs them through the OCR pipeline. Caps the burst rate so a large
/// existing library doesn't peg the OCR queue immediately on launch.
public actor OCRBackfill {

    private let store: LibraryStore
    private let pipeline: OCRPipeline
    private let log = AppLog.logger(category: "OCRBackfill")

    public init(store: LibraryStore, pipeline: OCRPipeline) {
        self.store = store
        self.pipeline = pipeline
    }

    public func run(maxConcurrency: Int = 2) async {
        let pending: [(id: UUID, filePath: String)]
        do {
            pending = try await store.captureIDsWithoutOCR()
        } catch {
            log.error("Backfill query failed: \(String(describing: error))")
            return
        }
        guard !pending.isEmpty else {
            log.info("OCR backfill: nothing to do")
            return
        }
        log.info("OCR backfill: \(pending.count) captures pending")

        await withTaskGroup(of: Void.self) { group in
            var inflight = 0
            var iterator = pending.makeIterator()

            func enqueueNext() {
                guard let next = iterator.next() else { return }
                inflight += 1
                let pipeline = self.pipeline
                group.addTask {
                    let url = URL(fileURLWithPath: next.filePath)
                    try? await pipeline.process(captureID: next.id, fileURL: url)
                }
            }

            // Prime the pump
            for _ in 0..<min(maxConcurrency, pending.count) { enqueueNext() }

            for await _ in group {
                inflight -= 1
                enqueueNext()
            }
        }
        log.info("OCR backfill: complete")
    }
}
```

- [ ] **Step 5: Wire into `AppDelegate.applicationDidFinishLaunching`**

In `JuiceScreen/App/AppDelegate.swift`, in `applicationDidFinishLaunching`, after the existing `Task.detached { ... TrashGC ... }` block, add:

```swift
        // Background: OCR backfill for captures that have no FTS5 entry yet
        Task.detached { [libraryStore, ocrPipeline] in
            let backfill = OCRBackfill(store: libraryStore, pipeline: ocrPipeline)
            await backfill.run()
        }
```

- [ ] **Step 6: Verify build + all tests**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: build + all tests pass.

- [ ] **Step 7: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStore.swift JuiceScreen/Library/Storage/LibraryStoreLive.swift JuiceScreen/Library/Storage/FakeLibraryStore.swift JuiceScreen/OCR/Pipeline/OCRBackfill.swift JuiceScreen/App/AppDelegate.swift
git commit -m "feat(ocr): launch-time OCRBackfill for captures missing an FTS5 entry"
```

---

## Task 17: README — document OCR + search

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append OCR section after the "Why" bullet list**

In `README.md`, find the "## Why" section and after the existing 4 bullets, add a paragraph block:

```markdown
**v0.5 update — local OCR + search.** Every screenshot now runs through Apple's Vision framework on a background queue: extracted text and per-region bounding boxes land in a JSON sidecar at `~/Library/Application Support/JuiceScreen/ocr/<uuid>.json`, and the concatenated text is indexed in an FTS5 SQLite table. The library window's search bar accepts free text plus filters: `aws error from:Safari after:2026-04-15 type:image`. Vision runs entirely on-device — no text ever leaves the machine.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README — note v0.5 OCR + search (local Vision, FTS5 SQLite)"
```

---

## Task 18: Bump VERSION to 0.5.0 + tag

**Files:**
- Modify: `VERSION` — `0.5.0`
- Modify: `project.yml` — `MARKETING_VERSION: "0.5.0"`

- [ ] **Step 1: Update VERSION + project.yml**

Replace `VERSION` contents with:

```
0.5.0
```

In `project.yml`, change `MARKETING_VERSION: "0.4.0"` to `MARKETING_VERSION: "0.5.0"`.

- [ ] **Step 2: Clean build + full test**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
rm -rf ~/Library/Developer/Xcode/DerivedData/JuiceScreen-*
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
```

Expected: build + tests succeed (~180 tests).

- [ ] **Step 3: Manual smoke test (HUMAN STEP)**

Run the app and verify:

| # | Action | Expected |
|---|---|---|
| 1 | Launch app, take a screenshot of a webpage with visible text (e.g. Wikipedia) | Editor window opens; in Console.app filter for `com.bks-lab.juicescreen` and look for `OCR succeeded for <uuid>: N regions` log line within ~3s of capture |
| 2 | Press ⌘⇧L → click the new tile | Inspector slide-in shows "OCR Text" section with the page's text content |
| 3 | Click "Copy text" in inspector | Clipboard contains the OCR text (verify by ⌘V into a text editor) |
| 4 | In search bar, type a word visible on the screenshot | Grid filters to that capture (debounce ~300ms, then results appear) |
| 5 | Type `from:Safari` (or whatever sourceApp) | Filters by source app (note: `sourceApp` is currently nil for most captures since spec § "Window" capture is the only one that sets it; this filter mostly proves the parser works) |
| 6 | Type `type:image` | All image captures appear |
| 7 | Type `before:2026-05-01` | Captures from before that date |
| 8 | Type `aws error from:Safari type:image` (combined) | All filters apply together |
| 9 | Clear search via the X button | Grid returns to filter-based listing |
| 10 | Restart the app | OCR backfill log line appears in Console.app: `OCR backfill: N captures pending` (should be 0 if all your captures already have OCR) |

If any step fails, do not tag.

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION project.yml
git commit -m "chore: bump VERSION to 0.5.0"
git tag -a v0.5.0 -m "OCR + Search milestone: local Vision OCR + FTS5 search bar"
git tag -l v0.5.0
```

- [ ] **Step 5: Verify clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Task 19: Update spec doc with Plan 5 status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Update Plan 5 line**

Replace `⬜ Plan 5: OCR + search` with:

```
- ✅ **Plan 5: OCR + search** (v0.5.0, 2026-05-05) — Vision framework (`VNRecognizeTextRequest`, `.accurate`, en-US/de-DE, automatic language detection on macOS 14+) wrapped in `OCRService` + Live + Fake. `OCRPipeline` actor runs after every still capture: writes per-region JSON sidecar at `~/Library/Application Support/JuiceScreen/ocr/<uuid>.json` and upserts concatenated text into `captures_fts` FTS5 table. `SearchQueryParser` handles `text from:app before:date after:date type:image|video`. `LibraryStoreLive.search` joins captures with `captures_fts` via `MATCH` + filters + `ORDER BY rank, captured_at DESC` (FTS5 BM25 + recency tiebreaker). `LibraryViewModel` debounces searchText changes by 300ms then drives reload. `LibraryView` search bar enabled with parser-hint placeholder + clear button. `InspectorView` reads sidecar and shows extracted text with Copy button. `OCRBackfill` actor runs on launch with concurrency 2 to OCR pre-existing captures. ~180 unit tests passing. OCR on video frames + custom-language picker deferred to v1.1
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 5 (OCR + search) complete in implementation status"
```

---

## Plan completion checklist

- [ ] `git tag -l` shows v0.1.0 → v0.5.0
- [ ] `xcodebuild test -only-testing:JuiceScreenTests` is green (~180 tests)
- [ ] All 10 manual smoke-test items pass
- [ ] `~/Library/Application Support/JuiceScreen/ocr/` contains JSON sidecars, one per OCR'd capture
- [ ] Searching `from:Safari after:2026-04-15` in the library window narrows the grid

When everything checks out: ship v0.5.0 alpha. Plan 6 is next — video recording with `SCStream` + `AVAssetWriter` + cursor highlight composition.
