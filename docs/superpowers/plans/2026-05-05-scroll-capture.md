# JuiceScreen — Scroll Capture Implementation Plan (Plan 8 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.8.0` — press `⌘⇧6` (or "Capture Scrolling" from the menu bar) to start a scroll capture. The user drags a rectangle over a scrollable area, a prompt explains "Scroll slowly. Press Esc or click Stop when done." A floating control bar shows the live captured-frame count. While the user scrolls, JuiceScreen's `SCStream` captures frames at ~10fps; a `FrameStitcher` runs brute-force sum-of-squared-differences over a horizontal mid-strip between consecutive frames to find the vertical scroll offset, and stitches new bottom slices onto a growing tall image. On stop, the result saves as a tall PNG at `~/Pictures/JuiceScreen/<date>/JuiceScreen_<timestamp>.png`, the library inserts a row, and the editor opens with the result. Per spec, this works cleanly on ~70% of real-world cases (most native macOS apps, simple web pages); ~30% (sticky headers, parallax, lazy-load) fail visibly with ghosting or torn images. The README documents this honestly — we don't paper over it.

**Architecture:** New `Scroll/` module split into `Model/` (pure value types: `ScrollCaptureState`, `StitchOffset`), `Stitcher/` (pure pixel math — `FrameStitcher` finds the best vertical offset, `StitchedImageBuilder` accumulates frames into a growing CGContext), `Capture/` (`ScrollCaptureService` protocol + `Live` impl wrapping `SCStream` at 10fps + `Fake` for tests), `UI/` (prompt + control bar + window), and `Session/` (`ScrollCaptureSession` coordinator). Honest scope: the stitcher is the entire risk surface; failure modes are documented inline (in code comments AND the README's known-limitations list) rather than papered over.

**Tech Stack:** ScreenCaptureKit (`SCStream`, `SCStreamConfiguration` at 10fps target), Core Graphics (`CGContext`, `CGImage`, raw bytes via `CFData` for pixel-level SSD), AppKit (`NSWindow`, `NSEvent` for Esc keypress), SwiftUI for the prompt + control bar. No new SPM dependencies. Existing modules from Plans 1–7 (`RegionPickerController`, `CaptureRecord`, `CaptureLibraryRecorder`, `EditorWindowManager`, `MenuBarController`).

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — section "Scroll capture (highest-risk module)".

**Plan 7 prerequisite:** v0.7.0 tagged. The `RegionPickerController` from Plan 2 returns a CGRect in screen coordinates. `CaptureType` enum has cases region/window/fullScreen/lastRegion — Plan 8 adds `.scroll` as a fifth case (additive, no breaking change). `MenuBarMenuBuilder` from Plan 1 is rebuilt on every `MenuBarController.update(prefs:)` — adding a new menu item requires a builder change plus a new `MenuBarActions` field.

**Scope deferred to later plans:**

- **User-marked sticky region masks** — sticky headers/footers can be excluded from the stitcher's search if the user paints a mask. This is a real polish that helps the failing 30%; v0.8 ships without it
- **Adaptive scroll-speed detection** — v0.8 captures at fixed 10fps; if the user scrolls fast, frames may have too-large offsets and SSD fails. Adaptive frame rate is a v1.1 polish
- **Direct horizontal scroll capture** — v0.8 only handles vertical scroll. Horizontal is uncommon enough to defer
- **Scroll capture in `lastRegion` mode** — v0.8 always shows the region picker; "scroll-capture last region" is a YAGNI cut
- **Pause/resume during scroll** — out of scope; Stop is the only end signal
- **Quality presets / output sizing knobs** — uses sensible hard-coded defaults; user-configurable settings land in Plan 9

---

## File Structure

```
JuiceScreen/
├── Scroll/
│   ├── Model/
│   │   ├── ScrollCaptureState.swift       NEW — enum: idle / collecting / stitching / done(URL) / failed(error)
│   │   ├── StitchOffset.swift             NEW — value type: pixelsScrolled + ssdScore (confidence)
│   │   └── ScrollCaptureError.swift       NEW — Error enum
│   ├── Stitcher/
│   │   ├── PixelGrid.swift                NEW — extracts grayscale rows from CGImage for SSD
│   │   ├── FrameStitcher.swift            NEW — pure: detect vertical offset between two frames via brute-force SSD on a mid-strip
│   │   └── StitchedImageBuilder.swift     NEW — manages growing CGContext, appends new bottom slices
│   ├── Capture/
│   │   ├── ScrollCaptureService.swift     NEW — protocol + state callbacks
│   │   ├── ScrollCaptureServiceLive.swift NEW — SCStream at 10fps
│   │   └── FakeScrollCaptureService.swift NEW — test double that emits canned frame sequence
│   ├── UI/
│   │   ├── ScrollPromptView.swift         NEW — modal: "Scroll slowly, Esc to finish"
│   │   ├── ScrollControlBarView.swift     NEW — floating: frame count + Stop button
│   │   ├── ScrollControlWindow.swift      NEW — borderless floating NSWindow
│   │   └── ScrollPromptWindow.swift       NEW — modal NSWindow for the start prompt
│   └── Session/
│       ├── ScrollCaptureSession.swift     NEW — coordinator: wire RegionPicker → service → stitcher → save → editor
│       └── ScrollCaptureSessionManager.swift NEW — singleton
├── Shared/
│   └── CaptureType.swift                  MODIFY — add .scroll case
├── MenuBar/
│   ├── HotkeyService.swift                MODIFY — add HotkeyAction.captureScroll = 8
│   └── MenuBarMenuBuilder.swift           MODIFY — add "Capture Scrolling" entry + MenuBarActions field
├── Preferences/
│   ├── Preferences.swift                  MODIFY — add captureScrollHotkey: Hotkey
│   └── PreferencesStore.swift             MODIFY — load/save captureScrollHotkey
├── App/
│   └── AppDelegate.swift                  MODIFY — instantiate session manager + register hotkey + wire menu action
├── README.md                              MODIFY — add v0.8 paragraph + honest known-limitations section
VERSION                                    MODIFY — bump to 0.8.0 (Task 18)
project.yml                                MODIFY — MARKETING_VERSION 0.8.0 (Task 18)
docs/superpowers/specs/2026-05-04-juicescreen-design.md  MODIFY — implementation status (Task 19)

JuiceScreenTests/
├── ScrollCaptureStateTests.swift          NEW
├── StitchOffsetTests.swift                NEW
├── PixelGridTests.swift                   NEW
├── FrameStitcherTests.swift               NEW
├── StitchedImageBuilderTests.swift        NEW
└── FakeScrollCaptureServiceTests.swift    NEW
```

---

## Task 1: Add `.scroll` case to `CaptureType` + update existing tests

**Files:**
- Modify: `JuiceScreen/Shared/CaptureType.swift`
- Modify: `JuiceScreenTests/CaptureRecordTests.swift`

- [ ] **Step 1: Update the existing failing-test for allCases**

In `JuiceScreenTests/CaptureRecordTests.swift`, find the `captureTypeAllCases` test and update the expected set to include `.scroll`:

```swift
    @Test("CaptureType is exhaustively case-iterable")
    func captureTypeAllCases() {
        let all = Set(CaptureType.allCases)
        #expect(all == [.region, .window, .fullScreen, .lastRegion, .scroll])
    }
```

- [ ] **Step 2: Run, verify it fails**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRecordTests 2>&1 | tail -8
```

Expected: 1 failing case (`captureTypeAllCases`), others still pass.

- [ ] **Step 3: Add `.scroll` to `CaptureType.swift`**

```swift
import Foundation

public enum CaptureType: String, CaseIterable, Sendable, Hashable {
    case region
    case window
    case fullScreen
    case lastRegion
    case scroll
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureRecordTests 2>&1 | tail -10
```

Expected: 5/5 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Shared/CaptureType.swift JuiceScreenTests/CaptureRecordTests.swift
git commit -m "feat(capture): CaptureType.scroll case + test update"
```

---

## Task 2: `StitchOffset` + tests

**Files:**
- Create: `JuiceScreen/Scroll/Model/StitchOffset.swift`
- Create: `JuiceScreenTests/StitchOffsetTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("StitchOffset")
struct StitchOffsetTests {

    @Test("Stores pixels + score")
    func storage() {
        let offset = StitchOffset(pixelsScrolled: 42, ssdScore: 1234.5)
        #expect(offset.pixelsScrolled == 42)
        #expect(offset.ssdScore == 1234.5)
    }

    @Test("isUsable: only positive offsets and score below threshold are accepted")
    func usable() {
        let good = StitchOffset(pixelsScrolled: 50, ssdScore: 100)
        let zero = StitchOffset(pixelsScrolled: 0, ssdScore: 0)
        let negative = StitchOffset(pixelsScrolled: -5, ssdScore: 10)
        let highSSD = StitchOffset(pixelsScrolled: 50, ssdScore: 1_000_000)

        #expect(good.isUsable)
        #expect(!zero.isUsable)
        #expect(!negative.isUsable)
        #expect(!highSSD.isUsable)
    }

    @Test("Equatable")
    func equatable() {
        let a = StitchOffset(pixelsScrolled: 20, ssdScore: 50)
        let b = StitchOffset(pixelsScrolled: 20, ssdScore: 50)
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/StitchOffsetTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `StitchOffset.swift`**

```swift
import Foundation

/// Result of one stitcher detection: how many pixels the user scrolled between two frames,
/// and the SSD score (lower = better match). The `isUsable` threshold rejects very high
/// SSDs that would indicate "no good match" (e.g. unrelated frames, sticky-header masking
/// most of the strip, or content that changed mid-scroll).
public struct StitchOffset: Equatable, Sendable {

    /// Threshold above which a match is considered unreliable.
    /// Tuned against the known failure modes — lazy-load + parallax both produce SSDs >> 500_000
    /// when the strip's pixel content is fundamentally different.
    public static let maxAcceptableSSD: Double = 500_000

    public let pixelsScrolled: Int
    public let ssdScore: Double

    public init(pixelsScrolled: Int, ssdScore: Double) {
        self.pixelsScrolled = pixelsScrolled
        self.ssdScore = ssdScore
    }

    public var isUsable: Bool {
        pixelsScrolled > 0 && ssdScore <= StitchOffset.maxAcceptableSSD
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/StitchOffsetTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Scroll/Model/StitchOffset.swift JuiceScreenTests/StitchOffsetTests.swift
git commit -m "feat(scroll): StitchOffset value type with usability threshold"
```

---

## Task 3: `ScrollCaptureState` + `ScrollCaptureError` + tests

**Files:**
- Create: `JuiceScreen/Scroll/Model/ScrollCaptureState.swift`
- Create: `JuiceScreen/Scroll/Model/ScrollCaptureError.swift`
- Create: `JuiceScreenTests/ScrollCaptureStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("ScrollCaptureState")
struct ScrollCaptureStateTests {

    @Test("Equatable across all cases")
    func equatable() {
        #expect(ScrollCaptureState.idle == .idle)
        #expect(ScrollCaptureState.collecting(framesCaptured: 5) == .collecting(framesCaptured: 5))
        #expect(ScrollCaptureState.collecting(framesCaptured: 5) != .collecting(framesCaptured: 6))
        #expect(ScrollCaptureState.stitching == .stitching)
        let url = URL(fileURLWithPath: "/tmp/x.png")
        #expect(ScrollCaptureState.done(fileURL: url) == .done(fileURL: url))
        #expect(ScrollCaptureState.failed(.userCancelled) == .failed(.userCancelled))
    }

    @Test("isActive true while collecting OR stitching")
    func isActive() {
        #expect(!ScrollCaptureState.idle.isActive)
        #expect(ScrollCaptureState.collecting(framesCaptured: 0).isActive)
        #expect(ScrollCaptureState.stitching.isActive)
        #expect(!ScrollCaptureState.done(fileURL: URL(fileURLWithPath: "/x")).isActive)
        #expect(!ScrollCaptureState.failed(.userCancelled).isActive)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ScrollCaptureStateTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `ScrollCaptureError.swift`**

```swift
import Foundation

public enum ScrollCaptureError: Error, Equatable {
    case missingScreenRecordingPermission
    case userCancelled
    case noFramesCaptured
    case stitchingFailed(String)
    case writeFailed(String)
    case streamConfigurationFailed(String)
}
```

- [ ] **Step 4: Implement `ScrollCaptureState.swift`**

```swift
import Foundation

public enum ScrollCaptureState: Equatable, Sendable {
    case idle
    case collecting(framesCaptured: Int)
    case stitching
    case done(fileURL: URL)
    case failed(ScrollCaptureError)

    public var isActive: Bool {
        switch self {
        case .collecting, .stitching: return true
        case .idle, .done, .failed:   return false
        }
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ScrollCaptureStateTests 2>&1 | tail -10
```

Expected: 2/2 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Scroll/Model/ScrollCaptureState.swift JuiceScreen/Scroll/Model/ScrollCaptureError.swift JuiceScreenTests/ScrollCaptureStateTests.swift
git commit -m "feat(scroll): ScrollCaptureState state machine + ScrollCaptureError"
```

---

## Task 4: `PixelGrid` + tests (extract grayscale rows from CGImage)

**Files:**
- Create: `JuiceScreen/Scroll/Stitcher/PixelGrid.swift`
- Create: `JuiceScreenTests/PixelGridTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("PixelGrid")
struct PixelGridTests {

    /// Builds a deterministic grayscale CGImage with a horizontal gradient (0 at top → 255 at bottom).
    private func makeGradient(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { fatalError("ctx") }
        for y in 0..<height {
            let v = UInt8((Double(y) / Double(height - 1)) * 255)
            ctx.setFillColor(NSColor(white: Double(v) / 255, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return ctx.makeImage()!
    }

    @Test("PixelGrid extracts the right number of rows + columns")
    func dimensions() {
        let img = makeGradient(width: 100, height: 80)
        let grid = PixelGrid(cgImage: img)!
        #expect(grid.width == 100)
        #expect(grid.height == 80)
    }

    @Test("Returns 0..255 row values for gradient image")
    func gradientRow() {
        let img = makeGradient(width: 50, height: 100)
        let grid = PixelGrid(cgImage: img)!
        let topRow = grid.row(y: 0)
        let bottomRow = grid.row(y: 99)
        // Top row should be near 0; bottom near 255
        #expect(topRow.allSatisfy { $0 < 30 })
        #expect(bottomRow.allSatisfy { $0 > 220 })
    }

    @Test("Init returns nil for zero-sized image")
    func zeroSize() {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let img = ctx.makeImage()!
        // 1x1 should still init OK; only 0-dim images are rejected
        let grid = PixelGrid(cgImage: img)
        #expect(grid != nil)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PixelGridTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `PixelGrid.swift`**

```swift
import CoreGraphics
import Foundation

/// Reads a CGImage (any color space) into a flat grayscale byte buffer for SSD computation.
/// Conversion uses standard luminance weights (0.30 R + 0.59 G + 0.11 B).
public struct PixelGrid: Sendable {

    public let width: Int
    public let height: Int
    private let bytes: [UInt8]   // length = width * height, row-major, top-left origin

    public init?(cgImage: CGImage) {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }

        let w = cgImage.width
        let h = cgImage.height
        var buffer = [UInt8](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()

        let ctx = buffer.withUnsafeMutableBytes { ptr -> CGContext? in
            CGContext(
                data: ptr.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        }
        guard let ctx else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        self.width = w
        self.height = h
        self.bytes = buffer
    }

    /// Returns the byte values for row `y` (0 == top).
    public func row(y: Int) -> [UInt8] {
        guard y >= 0, y < height else { return [] }
        let start = y * width
        return Array(bytes[start..<(start + width)])
    }

    /// Sum-of-squared-differences between row `y1` of self and row `y2` of `other`.
    /// Both grids must have the same width; returns `.infinity` if they don't.
    public func rowSSD(y1: Int, other: PixelGrid, y2: Int) -> Double {
        guard width == other.width,
              y1 >= 0, y1 < height,
              y2 >= 0, y2 < other.height else {
            return .infinity
        }
        var ssd: Double = 0
        let off1 = y1 * width
        let off2 = y2 * other.width
        for x in 0..<width {
            let d = Double(bytes[off1 + x]) - Double(other.bytes[off2 + x])
            ssd += d * d
        }
        return ssd
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PixelGridTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Scroll/Stitcher/PixelGrid.swift JuiceScreenTests/PixelGridTests.swift
git commit -m "feat(scroll): PixelGrid grayscale conversion + per-row SSD"
```

---

## Task 5: `FrameStitcher` (offset detection) + tests

**Files:**
- Create: `JuiceScreen/Scroll/Stitcher/FrameStitcher.swift`
- Create: `JuiceScreenTests/FrameStitcherTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FrameStitcher")
struct FrameStitcherTests {

    /// Builds a CGImage of `height` rows, each row a different gray value derived from `seedRow + y`.
    /// Lets us simulate "scrolling" by producing two images where image B is image A shifted up by N rows.
    private func makeRowSeededImage(width: Int, height: Int, seedRow: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        for y in 0..<height {
            let v = UInt8((seedRow + y) % 200 + 30)   // unique-ish row values, avoid clipping
            ctx.setFillColor(NSColor(white: Double(v) / 255, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return ctx.makeImage()!
    }

    @Test("Detects a clear scroll offset of N pixels between two synthetic frames")
    func detectScroll() {
        // Frame A starts at seed=0 (rows 0..99 have values derived from 0..99)
        // Frame B starts at seed=20 (rows 0..99 have values derived from 20..119)
        // Interpretation: user scrolled down by 20 pixels — what was at row 20 of A is now at row 0 of B.
        let frameA = makeRowSeededImage(width: 100, height: 100, seedRow: 0)
        let frameB = makeRowSeededImage(width: 100, height: 100, seedRow: 20)

        let stitcher = FrameStitcher()
        let offset = stitcher.detectOffset(previous: frameA, current: frameB)
        let resolved = #require(offset)
        #expect(resolved.pixelsScrolled == 20)
        #expect(resolved.isUsable)
    }

    @Test("Returns nil for unrelated frames")
    func unrelatedFrames() {
        // Two random-pattern images that share no content — SSD should be very high at every offset.
        let a = makeRowSeededImage(width: 100, height: 100, seedRow: 0)
        let bSize = 100
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: bSize, height: bSize,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        // Fill with a checker-like pattern wildly different from A
        for y in 0..<bSize {
            for x in 0..<bSize {
                let v: UInt8 = ((x + y) % 2 == 0) ? 255 : 0
                ctx.setFillColor(NSColor(white: Double(v) / 255, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let b = ctx.makeImage()!
        let stitcher = FrameStitcher()
        let offset = stitcher.detectOffset(previous: a, current: b)
        if let result = offset {
            // If we did detect an offset, it should be marked unusable
            #expect(!result.isUsable)
        }
    }

    @Test("Returns nil for identical frames (no scroll happened)")
    func identicalFrames() {
        let img = makeRowSeededImage(width: 100, height: 100, seedRow: 50)
        let stitcher = FrameStitcher()
        let offset = stitcher.detectOffset(previous: img, current: img)
        if let result = offset {
            #expect(!result.isUsable)   // pixelsScrolled would be 0 → not usable
        }
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FrameStitcherTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `FrameStitcher.swift`**

```swift
import CoreGraphics
import Foundation

/// Pure pixel math: given two consecutive frames from a scroll capture, find the
/// vertical offset (how many pixels the user scrolled) by brute-force SSD over a
/// horizontal mid-strip.
///
/// Algorithm:
/// 1. Convert both frames to grayscale `PixelGrid`s.
/// 2. Pick a single horizontal "anchor" row from the middle of `previous`.
/// 3. For each candidate offset y in [minOffset, maxOffset], compute SSD between
///    that anchor row and the corresponding row in `current` (shifted up by y).
/// 4. The offset with minimum SSD is the detected scroll amount.
///
/// Known failure modes (documented honestly per spec):
/// - Sticky headers/footers: the anchor row may be inside the header strip, which
///   doesn't move when the user scrolls — SSD reports offset = 0 (rejected).
/// - Lazy-loaded content: the row at the new position may have changed pixels
///   (e.g. an image just loaded), inflating SSD past the threshold — returns nil.
/// - Parallax: similar — SSD will be high.
public struct FrameStitcher: Sendable {

    /// Smallest scroll amount we'll consider. Below this, we treat as no-scroll.
    public static let minOffset: Int = 5

    /// Largest scroll amount we'll consider. Beyond this, the user scrolled too fast
    /// for our 10fps capture rate.
    public static let maxOffset: Int = 600

    public init() {}

    public func detectOffset(previous: CGImage, current: CGImage) -> StitchOffset? {
        guard let prev = PixelGrid(cgImage: previous),
              let curr = PixelGrid(cgImage: current) else {
            return nil
        }
        guard prev.width == curr.width, prev.height == curr.height,
              prev.height > Self.minOffset + 2 else {
            return nil
        }

        // Anchor row: middle of `previous`. We assume the user scrolled DOWN
        // (content moved up in the viewport), so what was at anchorY in previous
        // is now at (anchorY - offset) in current.
        let anchorY = prev.height / 2
        let maxOff = min(Self.maxOffset, anchorY - 1)

        var bestSSD = Double.infinity
        var bestOffset = 0

        for offset in Self.minOffset...maxOff {
            let candidateY = anchorY - offset
            guard candidateY >= 0, candidateY < curr.height else { continue }
            let ssd = prev.rowSSD(y1: anchorY, other: curr, y2: candidateY)
            if ssd < bestSSD {
                bestSSD = ssd
                bestOffset = offset
            }
        }

        guard bestOffset > 0 else { return nil }
        return StitchOffset(pixelsScrolled: bestOffset, ssdScore: bestSSD)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FrameStitcherTests 2>&1 | tail -10
```

Expected: 3/3 pass. (The unrelated-frames + identical-frames tests assert that any returned offset is `!isUsable`; the synthetic-scroll test asserts the exact pixel offset is detected.)

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Scroll/Stitcher/FrameStitcher.swift JuiceScreenTests/FrameStitcherTests.swift
git commit -m "feat(scroll): FrameStitcher (brute-force SSD on mid-row anchor for vertical offset)"
```

---

## Task 6: `StitchedImageBuilder` (growing CGContext) + tests

**Files:**
- Create: `JuiceScreen/Scroll/Stitcher/StitchedImageBuilder.swift`
- Create: `JuiceScreenTests/StitchedImageBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("StitchedImageBuilder")
struct StitchedImageBuilderTests {

    private func makeSolidImage(width: Int, height: Int, brightness: Double) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.setFillColor(NSColor(white: brightness, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    @Test("Initial finalImage is the first frame, unchanged")
    func initialIsFirstFrame() {
        let first = makeSolidImage(width: 100, height: 200, brightness: 0.5)
        let builder = StitchedImageBuilder(firstFrame: first)
        let final = #require(builder.finalImage)
        #expect(final.width == 100)
        #expect(final.height == 200)
    }

    @Test("Appending an offset slice grows the image height by exactly that many pixels")
    func appendGrowsHeight() {
        let first = makeSolidImage(width: 100, height: 200, brightness: 0.3)
        let next = makeSolidImage(width: 100, height: 200, brightness: 0.8)
        let builder = StitchedImageBuilder(firstFrame: first)
        builder.append(frame: next, offset: StitchOffset(pixelsScrolled: 50, ssdScore: 100))

        let final = #require(builder.finalImage)
        #expect(final.width == 100)
        #expect(final.height == 250)   // 200 + 50
    }

    @Test("Multiple appends accumulate")
    func multipleAppends() {
        let first = makeSolidImage(width: 100, height: 200, brightness: 0.3)
        let f2 = makeSolidImage(width: 100, height: 200, brightness: 0.5)
        let f3 = makeSolidImage(width: 100, height: 200, brightness: 0.7)
        let builder = StitchedImageBuilder(firstFrame: first)
        builder.append(frame: f2, offset: StitchOffset(pixelsScrolled: 30, ssdScore: 50))
        builder.append(frame: f3, offset: StitchOffset(pixelsScrolled: 40, ssdScore: 50))
        let final = #require(builder.finalImage)
        #expect(final.height == 270)   // 200 + 30 + 40
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/StitchedImageBuilderTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `StitchedImageBuilder.swift`**

```swift
import CoreGraphics
import Foundation

/// Accumulates frames into a growing tall image. Each `append` adds the bottom
/// `offset.pixelsScrolled` rows of the new frame to the bottom of the running image.
///
/// Implementation: stores a list of (CGImage, sliceOffset) and reconstructs the
/// final image in `finalImage` by drawing into a fresh `CGContext` of the
/// accumulated height. Called once at end-of-session, so the cost of rebuilding is
/// amortized — keeps the per-frame append O(1).
public final class StitchedImageBuilder: @unchecked Sendable {

    private struct Slice {
        let image: CGImage
        /// How many bottom rows of `image` to take. Equal to `offset.pixelsScrolled`
        /// for non-first slices; equal to full height for the first frame.
        let bottomRows: Int
    }

    private let lock = NSLock()
    private var slices: [Slice] = []
    private let frameWidth: Int

    public init(firstFrame: CGImage) {
        self.frameWidth = firstFrame.width
        slices.append(Slice(image: firstFrame, bottomRows: firstFrame.height))
    }

    public func append(frame: CGImage, offset: StitchOffset) {
        guard frame.width == frameWidth, offset.pixelsScrolled > 0 else { return }
        let rows = min(offset.pixelsScrolled, frame.height)
        lock.lock()
        slices.append(Slice(image: frame, bottomRows: rows))
        lock.unlock()
    }

    /// Total height the final image would have, given the slices accumulated so far.
    public var totalHeight: Int {
        lock.lock(); defer { lock.unlock() }
        return slices.reduce(0) { $0 + $1.bottomRows }
    }

    public var frameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return slices.count
    }

    public var finalImage: CGImage? {
        lock.lock()
        let snapshot = slices
        lock.unlock()

        let totalH = snapshot.reduce(0) { $0 + $1.bottomRows }
        guard totalH > 0, frameWidth > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: frameWidth,
            height: totalH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // CGContext origin is bottom-left. We want the first slice at the TOP of
        // the final image. So we draw slices from index 0 → N at decreasing y.
        var yCursor = totalH

        for slice in snapshot {
            let h = slice.bottomRows
            yCursor -= h
            // Take the BOTTOM `bottomRows` rows of slice.image and draw at (0, yCursor).
            // CGImage.cropping uses top-left convention; we crop the bottom strip.
            let cropY = slice.image.height - h
            let cropRect = CGRect(x: 0, y: cropY, width: frameWidth, height: h)
            guard let cropped = slice.image.cropping(to: cropRect) else { continue }
            ctx.draw(cropped, in: CGRect(x: 0, y: yCursor, width: frameWidth, height: h))
        }

        return ctx.makeImage()
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/StitchedImageBuilderTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Scroll/Stitcher/StitchedImageBuilder.swift JuiceScreenTests/StitchedImageBuilderTests.swift
git commit -m "feat(scroll): StitchedImageBuilder accumulates slices into growing tall CGImage"
```

---

## Task 7: `ScrollCaptureService` protocol + `FakeScrollCaptureService` + tests

**Files:**
- Create: `JuiceScreen/Scroll/Capture/ScrollCaptureService.swift`
- Create: `JuiceScreen/Scroll/Capture/FakeScrollCaptureService.swift`
- Create: `JuiceScreenTests/FakeScrollCaptureServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeScrollCaptureService")
@MainActor
struct FakeScrollCaptureServiceTests {

    private func solidImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        return ctx.makeImage()!
    }

    @Test("start emits queued frames to handler in order, completes on stop()")
    func emitsFrames() async throws {
        let svc = FakeScrollCaptureService()
        svc.queuedFrames = [solidImage(width: 100, height: 100), solidImage(width: 100, height: 100)]

        var received: [CGImage] = []
        try await svc.start(region: CGRect(x: 0, y: 0, width: 100, height: 100)) { frame in
            received.append(frame)
        }

        // Synchronously drain the queue
        await svc.emitAllQueuedNow()

        try await svc.stop()
        #expect(received.count == 2)
    }

    @Test("stop returns even if no frames captured")
    func stopWithoutFrames() async throws {
        let svc = FakeScrollCaptureService()
        try await svc.start(region: CGRect(x: 0, y: 0, width: 50, height: 50)) { _ in }
        try await svc.stop()
        #expect(svc.isRunning == false)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeScrollCaptureServiceTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `ScrollCaptureService.swift`**

```swift
import CoreGraphics
import Foundation

@MainActor
public protocol ScrollCaptureService: AnyObject {

    typealias FrameHandler = @MainActor (CGImage) -> Void

    var isRunning: Bool { get }

    /// Begins capturing frames at ~10fps from the supplied screen `region`.
    /// Calls `handler` for each new frame on the main actor.
    func start(region: CGRect, handler: @escaping FrameHandler) async throws

    /// Stops capturing. Idempotent.
    func stop() async throws
}
```

- [ ] **Step 4: Implement `FakeScrollCaptureService.swift`**

```swift
import CoreGraphics
import Foundation

@MainActor
public final class FakeScrollCaptureService: ScrollCaptureService {

    public var queuedFrames: [CGImage] = []
    public private(set) var isRunning: Bool = false

    private var handler: FrameHandler?

    public init() {}

    public func start(region: CGRect, handler: @escaping FrameHandler) async throws {
        self.handler = handler
        self.isRunning = true
    }

    public func stop() async throws {
        isRunning = false
        handler = nil
    }

    /// Test-only: drain all queued frames into the handler.
    public func emitAllQueuedNow() async {
        guard let handler else { return }
        for frame in queuedFrames {
            handler(frame)
            // Yield so MainActor can process between frames if test cares
            await Task.yield()
        }
        queuedFrames.removeAll()
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeScrollCaptureServiceTests 2>&1 | tail -10
```

Expected: 2/2 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Scroll/Capture/ScrollCaptureService.swift JuiceScreen/Scroll/Capture/FakeScrollCaptureService.swift JuiceScreenTests/FakeScrollCaptureServiceTests.swift
git commit -m "feat(scroll): ScrollCaptureService protocol + FakeScrollCaptureService"
```

---

## Task 8: `ScrollCaptureServiceLive` (SCStream at 10fps)

**Files:**
- Create: `JuiceScreen/Scroll/Capture/ScrollCaptureServiceLive.swift`

(No automated tests — wraps `SCStream`, requires real screen recording permission and a running app.)

- [ ] **Step 1: Implement `ScrollCaptureServiceLive.swift`**

```swift
import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
public final class ScrollCaptureServiceLive: NSObject, ScrollCaptureService {

    public private(set) var isRunning: Bool = false

    private var stream: SCStream?
    private var output: StreamOutput?
    private let log = AppLog.logger(category: "ScrollCaptureServiceLive")

    public override init() { super.init() }

    public func start(region: CGRect, handler: @escaping FrameHandler) async throws {
        guard !isRunning else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw ScrollCaptureError.streamConfigurationFailed("No displays available")
        }

        let pixelDensity = 2
        let cfg = SCStreamConfiguration()
        cfg.width = Int(region.width) * pixelDensity
        cfg.height = Int(region.height) * pixelDensity
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 10)   // 10fps target
        cfg.queueDepth = 4
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.sourceRect = region

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let output = StreamOutput(handler: handler)
        self.output = output
        let stream = SCStream(filter: filter, configuration: cfg, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)

        try await stream.startCapture()
        self.stream = stream
        isRunning = true
        log.info("Scroll capture started — \(cfg.width)x\(cfg.height) @ 10fps")
    }

    public func stop() async throws {
        guard isRunning, let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
        self.output = nil
        isRunning = false
        log.info("Scroll capture stopped")
    }
}

private final class StreamOutput: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {

    let queue = DispatchQueue(label: "com.bks-lab.juicescreen.scroll-output")
    let handler: ScrollCaptureService.FrameHandler

    init(handler: @escaping ScrollCaptureService.FrameHandler) {
        self.handler = handler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        // Snapshot the pixel buffer to a CGImage for safe handoff to the main actor.
        guard let cgImage = makeCGImage(from: pixelBuffer) else { return }
        Task { @MainActor in
            handler(cgImage)
        }
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: base,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }
        return ctx.makeImage()
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Some Swift 6 concurrency warnings about the @MainActor handler dispatch are acceptable.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Scroll/Capture/ScrollCaptureServiceLive.swift
git commit -m "feat(scroll): ScrollCaptureServiceLive — SCStream at 10fps with CGImage snapshot per frame"
```

---

## Task 9: `ScrollPromptView` + `ScrollPromptWindow`

**Files:**
- Create: `JuiceScreen/Scroll/UI/ScrollPromptView.swift`
- Create: `JuiceScreen/Scroll/UI/ScrollPromptWindow.swift`

- [ ] **Step 1: Implement `ScrollPromptView.swift`**

```swift
import SwiftUI

struct ScrollPromptView: View {

    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scroll Capture")
                        .font(.title3).fontWeight(.semibold)
                    Text("Captures a tall image while you scroll.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                bullet("Click Start, then scroll the chosen area slowly.")
                bullet("JuiceScreen captures frames at 10fps and stitches them.")
                bullet("Press Esc or click Stop on the floating bar when done.")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Honest limits")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Sticky headers/footers, lazy-loaded content, and pages with parallax effects can produce ghosting or torn images. Native macOS apps and simple web pages stitch cleanly.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start") { onStart() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.tertiary)
            Text(text).font(.system(size: 12))
        }
    }
}
```

- [ ] **Step 2: Implement `ScrollPromptWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class ScrollPromptWindow {

    private var window: NSWindow?

    init() {}

    func show(onStart: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let view = ScrollPromptView(
            onStart: { [weak self] in self?.close(); onStart() },
            onCancel: { [weak self] in self?.close(); onCancel() }
        )
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Scroll Capture"
        win.contentView = NSHostingView(rootView: view)
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func close() {
        window?.close()
        window = nil
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
git add JuiceScreen/Scroll/UI/ScrollPromptView.swift JuiceScreen/Scroll/UI/ScrollPromptWindow.swift
git commit -m "feat(scroll): ScrollPromptView + Window (start prompt with honest-limits note)"
```

---

## Task 10: `ScrollControlBarView` + `ScrollControlWindow`

**Files:**
- Create: `JuiceScreen/Scroll/UI/ScrollControlBarView.swift`
- Create: `JuiceScreen/Scroll/UI/ScrollControlWindow.swift`

- [ ] **Step 1: Implement `ScrollControlBarView.swift`**

```swift
import SwiftUI

struct ScrollControlBarView: View {

    let frameCount: Int
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
            .help("Stop scroll capture")

            VStack(alignment: .leading, spacing: 0) {
                Text("Scroll Capture")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(frameCount) frame\(frameCount == 1 ? "" : "s") captured")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 24)

            Text("Esc to stop")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }
}
```

- [ ] **Step 2: Implement `ScrollControlWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class ScrollControlWindow {

    let window: NSWindow
    private var hostingView: NSHostingView<ScrollControlBarView>?
    private var localKeyMonitor: Any?

    init(onStop: @escaping () -> Void) {
        let frame = NSRect(x: 0, y: 0, width: 240, height: 56)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.hasShadow = true
        win.isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let s = screen.visibleFrame
            win.setFrameOrigin(NSPoint(x: s.midX - frame.width / 2, y: s.minY + 64))
        }

        self.window = win

        let view = ScrollControlBarView(frameCount: 0, onStop: onStop)
        let host = NSHostingView(rootView: view)
        win.contentView = host
        self.hostingView = host

        // Esc anywhere → stop. Local monitor (when window is key OR app foreground).
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {   // Esc
                onStop()
                return nil
            }
            return event
        }
        self.localKeyMonitor = monitor
    }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }

    func update(frameCount: Int, onStop: @escaping () -> Void) {
        hostingView?.rootView = ScrollControlBarView(frameCount: frameCount, onStop: onStop)
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
git add JuiceScreen/Scroll/UI/ScrollControlBarView.swift JuiceScreen/Scroll/UI/ScrollControlWindow.swift
git commit -m "feat(scroll): ScrollControlBarView + Window (floating with Esc-to-stop)"
```

---

## Task 11: `ScrollCaptureSession` (coordinator)

**Files:**
- Create: `JuiceScreen/Scroll/Session/ScrollCaptureSession.swift`

(No automated tests — orchestrator wires together UI + service + stitcher; smoke-tested in Task 14.)

- [ ] **Step 1: Implement `ScrollCaptureSession.swift`**

```swift
import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class ScrollCaptureSession {

    private let service: ScrollCaptureService
    private let stitcher: FrameStitcher
    private let saveDirectory: SaveDirectoryProvider
    private let filenameGenerator: FilenameGenerator
    private let onComplete: (CaptureRecord) -> Void
    private let onError: (ScrollCaptureError) -> Void

    private var promptWindow: ScrollPromptWindow?
    private var controlWindow: ScrollControlWindow?
    private var regionPicker: RegionPickerController?
    private var builder: StitchedImageBuilder?
    private var lastFrame: CGImage?
    private var region: CGRect = .zero
    private var startedAt: Date = .distantPast

    private let log = AppLog.logger(category: "ScrollCaptureSession")

    public init(
        service: ScrollCaptureService,
        stitcher: FrameStitcher = FrameStitcher(),
        saveDirectory: SaveDirectoryProvider,
        filenameGenerator: FilenameGenerator = FilenameGenerator(),
        onComplete: @escaping (CaptureRecord) -> Void,
        onError: @escaping (ScrollCaptureError) -> Void
    ) {
        self.service = service
        self.stitcher = stitcher
        self.saveDirectory = saveDirectory
        self.filenameGenerator = filenameGenerator
        self.onComplete = onComplete
        self.onError = onError
    }

    public func begin() {
        let prompt = ScrollPromptWindow()
        promptWindow = prompt
        prompt.show(
            onStart: { [weak self] in
                Task { @MainActor in await self?.pickRegionThenStart() }
            },
            onCancel: { [weak self] in
                self?.onError(.userCancelled)
            }
        )
    }

    private func pickRegionThenStart() async {
        let picker = RegionPickerController()
        regionPicker = picker
        do {
            let chosen = try await picker.pickRegion()
            self.region = chosen
            try await startCollecting()
        } catch {
            onError(.userCancelled)
        }
    }

    private func startCollecting() async throws {
        let win = ScrollControlWindow(onStop: { [weak self] in
            Task { @MainActor in await self?.stopAndStitch() }
        })
        controlWindow = win
        win.show()
        startedAt = Date()

        try await service.start(region: region) { [weak self] frame in
            self?.handleFrame(frame)
        }
    }

    private func handleFrame(_ frame: CGImage) {
        if builder == nil {
            builder = StitchedImageBuilder(firstFrame: frame)
            lastFrame = frame
            controlWindow?.update(frameCount: 1, onStop: { [weak self] in
                Task { @MainActor in await self?.stopAndStitch() }
            })
            return
        }

        guard let last = lastFrame, let builder else { return }

        if let offset = stitcher.detectOffset(previous: last, current: frame), offset.isUsable {
            builder.append(frame: frame, offset: offset)
            lastFrame = frame
        }
        // Else: this frame is a no-scroll or unreliable match; we keep `lastFrame`
        // unchanged so the next frame is compared against the same anchor. This
        // makes us robust to tiny user pauses without inserting bad slices.

        controlWindow?.update(frameCount: builder.frameCount, onStop: { [weak self] in
            Task { @MainActor in await self?.stopAndStitch() }
        })
    }

    private func stopAndStitch() async {
        do { try await service.stop() } catch {
            log.error("Service stop failed: \(String(describing: error))")
        }
        controlWindow?.close()
        controlWindow = nil

        guard let builder, builder.frameCount > 0,
              let final = builder.finalImage else {
            onError(.noFramesCaptured)
            return
        }

        // Save PNG
        do {
            let date = Date()
            let folder = try saveDirectory.directory(for: date)
            let filename = filenameGenerator.filename(for: date, extension: "png")
            let url = folder.appendingPathComponent(filename)
            try writePNG(final, to: url)

            let record = CaptureRecord(
                id: UUID(),
                fileURL: url,
                captureType: .scroll,
                capturedAt: date,
                pixelWidth: final.width,
                pixelHeight: final.height,
                sourceApp: nil
            )
            onComplete(record)
        } catch {
            onError(.writeFailed("\(error)"))
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let data = try PNGEncoder.encode(nsImage)
        try data.write(to: url, options: .atomic)
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
git add JuiceScreen/Scroll/Session/ScrollCaptureSession.swift
git commit -m "feat(scroll): ScrollCaptureSession coordinator (prompt → region → SCStream → stitch → save)"
```

---

## Task 12: `ScrollCaptureSessionManager` (singleton)

**Files:**
- Create: `JuiceScreen/Scroll/Session/ScrollCaptureSessionManager.swift`

- [ ] **Step 1: Implement `ScrollCaptureSessionManager.swift`**

```swift
import Foundation

@MainActor
public final class ScrollCaptureSessionManager {

    private let serviceFactory: () -> ScrollCaptureService
    private let saveDirectory: SaveDirectoryProvider
    private let onComplete: (CaptureRecord) -> Void
    private let onError: (ScrollCaptureError) -> Void
    private var session: ScrollCaptureSession?

    public init(
        serviceFactory: @escaping () -> ScrollCaptureService,
        saveDirectory: SaveDirectoryProvider,
        onComplete: @escaping (CaptureRecord) -> Void,
        onError: @escaping (ScrollCaptureError) -> Void
    ) {
        self.serviceFactory = serviceFactory
        self.saveDirectory = saveDirectory
        self.onComplete = onComplete
        self.onError = onError
    }

    public var isActive: Bool { session != nil }

    public func begin() {
        if isActive { return }
        let session = ScrollCaptureSession(
            service: serviceFactory(),
            saveDirectory: saveDirectory,
            onComplete: { [weak self] record in
                self?.session = nil
                self?.onComplete(record)
            },
            onError: { [weak self] error in
                self?.session = nil
                self?.onError(error)
            }
        )
        self.session = session
        session.begin()
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
git add JuiceScreen/Scroll/Session/ScrollCaptureSessionManager.swift
git commit -m "feat(scroll): ScrollCaptureSessionManager — single-session lifecycle owner"
```

---

## Task 13: `HotkeyAction.captureScroll` + Preferences extension + tests

**Files:**
- Modify: `JuiceScreen/MenuBar/HotkeyService.swift`
- Modify: `JuiceScreen/Preferences/Preferences.swift`
- Modify: `JuiceScreen/Preferences/PreferencesStore.swift`
- Modify: `JuiceScreenTests/PreferencesStoreTests.swift`

- [ ] **Step 1: Add the `captureScroll` HotkeyAction case**

In `JuiceScreen/MenuBar/HotkeyService.swift`, add a case:

```swift
public enum HotkeyAction: UInt32, CaseIterable, Sendable {
    case captureRegion     = 1
    case captureWindow     = 2
    case captureFullScreen = 3
    case captureLastRegion = 4
    case recordScreen      = 5
    case openLibrary       = 6
    case stopRecording     = 7
    case captureScroll     = 8   // NEW
}
```

- [ ] **Step 2: Add `captureScrollHotkey` to `Preferences`**

In `JuiceScreen/Preferences/Preferences.swift`:

1. Add the property after `openLibraryHotkey`:

```swift
    public var captureScrollHotkey: Hotkey
```

2. Add a parameter to the public init (after `openLibraryHotkey: Hotkey`):

```swift
        captureScrollHotkey: Hotkey,
```

3. Assign in init body:

```swift
        self.captureScrollHotkey = captureScrollHotkey
```

4. In `Preferences.defaults`, add to the init call (after `openLibraryHotkey`):

```swift
            captureScrollHotkey:     Hotkey(keyCode: 22, modifiers: [.command, .shift]),
```

(Virtual keycode 22 = "6" on US layout.)

- [ ] **Step 3: Add persistence in `PreferencesStore`**

In `JuiceScreen/Preferences/PreferencesStore.swift`:

1. Add to `Key` enum: `static let captureScrollHotkey = "captureScrollHotkey"`
2. In `load()`, add: `captureScrollHotkey: loadHotkey(Key.captureScrollHotkey) ?? d.captureScrollHotkey,` (after `openLibraryHotkey`)
3. In `save(_:)`, add: `saveHotkey(prefs.captureScrollHotkey, key: Key.captureScrollHotkey)`

- [ ] **Step 4: Add a round-trip test**

In `JuiceScreenTests/PreferencesStoreTests.swift`, add a test:

```swift
    @Test("captureScrollHotkey round-trips")
    func captureScrollHotkeyRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.captureScrollHotkey = Hotkey(keyCode: 22, modifiers: [.command, .control])
        store.save(prefs)
        let reloaded = store.load()
        #expect(reloaded.captureScrollHotkey == Hotkey(keyCode: 22, modifiers: [.command, .control]))
    }
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PreferencesStoreTests 2>&1 | tail -10
```

Expected: existing tests + 1 new test all pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/MenuBar/HotkeyService.swift JuiceScreen/Preferences/Preferences.swift JuiceScreen/Preferences/PreferencesStore.swift JuiceScreenTests/PreferencesStoreTests.swift
git commit -m "feat(prefs): HotkeyAction.captureScroll + Preferences.captureScrollHotkey (default ⌘⇧6)"
```

---

## Task 14: `MenuBarMenuBuilder` — add Scroll Capture entry + AppDelegate wiring

**Files:**
- Modify: `JuiceScreen/MenuBar/MenuBarMenuBuilder.swift`
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Add `captureScroll` field to `MenuBarActions` and a menu entry**

In `JuiceScreen/MenuBar/MenuBarMenuBuilder.swift`, add a `captureScroll` closure to `MenuBarActions` (after `captureLastRegion`):

```swift
    public var captureScroll: () -> Void
```

Add to the `MenuBarActions` init signature + assignment, in the same position.

In the menu builder body (in `build(prefs:actions:)`), add a new menu item after the existing "Capture Last Region" item:

```swift
        menu.addItem(item("Capture Scrolling…",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureScrollHotkey),
                          action: actions.captureScroll))
```

- [ ] **Step 2: Wire into `AppDelegate`**

In `JuiceScreen/App/AppDelegate.swift`:

1. Add a lazy `scrollCaptureSessionManager` property (after `recordingSessionManager`):

```swift
    private lazy var scrollCaptureSessionManager: ScrollCaptureSessionManager = {
        ScrollCaptureSessionManager(
            serviceFactory: { ScrollCaptureServiceLive() },
            saveDirectory: SaveDirectoryProvider(rootDirectory: preferences.load().saveDirectory),
            onComplete: { [weak self] record in
                guard let self else { return }
                AppLog.logger(category: "App").info("Scroll capture → \(record.fileURL.path)")
                self.editorWindowManager.show(for: record)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await self.captureLibraryRecorder.record(record)
                    } catch {
                        AppLog.logger(category: "App").error("Library recording failed: \(String(describing: error))")
                    }
                }
            },
            onError: { error in
                if case .userCancelled = error {
                    AppLog.logger(category: "App").info("Scroll capture cancelled by user")
                } else {
                    AppLog.logger(category: "App").error("Scroll capture failed: \(String(describing: error))")
                }
            }
        )
    }()
```

(If lazy var has `@MainActor` issues per the workaround established in Plan 6 Task 17, use the same backing-optional + computed-property pattern.)

2. In `applicationDidFinishLaunching`, in the `MenuBarActions` initializer, add the `captureScroll` field:

```swift
            captureScroll:     { [weak self] in self?.scrollCaptureSessionManager.begin() },
```

3. In `registerHotkeys(prefs:actions:)`, add the registration:

```swift
        hotkeyService.register(prefs.captureScrollHotkey, for: .captureScroll) { actions.captureScroll() }
```

- [ ] **Step 3: Verify build + tests**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: build succeeds, all unit tests still pass.

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/MenuBar/MenuBarMenuBuilder.swift JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): wire Scroll Capture into menu + ⌘⇧6 hotkey + library recorder"
```

---

## Task 15: README — v0.8 paragraph + honest known-limitations section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append a paragraph after the v0.7 trim paragraph**

Find the v0.7 trim paragraph and append:

```markdown
**v0.8 update — scroll capture (with honest limits).** Press `⌘⇧6` to capture a scrolling area: pick a region, scroll slowly, press Esc. JuiceScreen captures frames at 10fps, stitches them into a tall PNG, and opens it in the editor. The stitcher uses brute-force sum-of-squared-differences over a horizontal mid-strip — works cleanly on most native macOS apps and simple web pages (~70% of cases). It will visibly fail on the other ~30%: pages with sticky headers/footers, lazy-loaded content, or parallax effects produce ghosting or torn images. Tools that hide this limitation are tools that lie. We list it here.
```

- [ ] **Step 2: Update the Known Limitations section**

Find the existing `## Known limitations` section and add bullets:

```markdown
- Scroll capture (v0.8): ~30% of complex web pages (sticky headers, lazy-load, parallax) produce ghosting or torn images. Native macOS apps and simple web pages stitch cleanly.
- Scroll capture only handles vertical scroll in v0.8.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README — v0.8 scroll capture paragraph + known-limits update"
```

---

## Task 16: Bump VERSION to 0.8.0 + tag

**Files:**
- Modify: `VERSION` — `0.8.0`
- Modify: `project.yml` — `MARKETING_VERSION: "0.8.0"`

- [ ] **Step 1: Update VERSION + project.yml**

Replace `VERSION` contents with:

```
0.8.0
```

In `project.yml`, change `MARKETING_VERSION: "0.7.0"` to `MARKETING_VERSION: "0.8.0"`.

- [ ] **Step 2: Clean build + full test**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
rm -rf ~/Library/Developer/Xcode/DerivedData/JuiceScreen-*
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
```

Expected: build + tests succeed (~235 tests).

- [ ] **Step 3: Manual smoke test (HUMAN STEP)**

Run the app and verify each on a known-good target (e.g., a long native macOS Settings panel or a long simple web article):

| # | Action | Expected |
|---|---|---|
| 1 | Press ⌘⇧6 | Scroll Capture prompt appears |
| 2 | Click Start, drag a region over a scrollable area | Region picker → control bar appears bottom-center; menu bar icon may flash |
| 3 | Slowly scroll the chosen area | Frame counter on the control bar increments while you scroll |
| 4 | Stop scrolling for 2 seconds | Counter holds; capturing continues but no offsets accumulate |
| 5 | Press Esc | Capture stops; stitcher runs; PNG saved to ~/Pictures/JuiceScreen/<today>/ |
| 6 | Editor window opens with the tall stitched image | Image visible; height > viewport size |
| 7 | Press ⌘⇧L → library | New tile shows the scroll capture with thumbnail |
| 8 | Inspector shows W × H of the tall image | Width matches region; height significantly larger |
| 9 | Try on a known-bad target (web page with sticky header) | Resulting image shows ghosting at the header — this is expected; documented in README |

If on a known-good target the image stitches cleanly, the feature works for v0.8.

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION project.yml
git commit -m "chore: bump VERSION to 0.8.0"
git tag -a v0.8.0 -m "Scroll Capture milestone: SCStream + SSD frame stitcher (~70% reliable)"
git tag -l v0.8.0
```

- [ ] **Step 5: Verify clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Task 17: Update spec doc with Plan 8 status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Update Plan 8 line**

Replace `⬜ Plan 8: Scroll capture` with:

```
- ✅ **Plan 8: Scroll capture** (v0.8.0, 2026-05-05) — Press ⌘⇧6 to launch the prompt, pick a region with the existing RegionPickerController, scroll slowly. SCStream captures at 10fps. FrameStitcher does brute-force SSD on a horizontal mid-strip to detect vertical offset (StitchOffset.maxAcceptableSSD threshold rejects unrelated frames). StitchedImageBuilder accumulates bottom slices into a growing CGImage, rebuilt once at end-of-session. Floating control bar with frame counter + Stop + Esc handler. Saves tall PNG to ~/Pictures/JuiceScreen/<date>/, library row with .scroll captureType, opens editor automatically. Honest scope: ~70% of native + simple-web cases work cleanly; ~30% (sticky headers/footers, lazy-load, parallax) fail visibly with ghosting. Documented honestly in README known-limitations. Sticky-region masks + adaptive frame rate + horizontal scroll deferred to v1.1. ~235 unit tests
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 8 (Scroll capture) complete in implementation status"
```

---

## Plan completion checklist

- [ ] `git tag -l` shows v0.1.0 → v0.8.0
- [ ] `xcodebuild test -only-testing:JuiceScreenTests` is green (~235 tests)
- [ ] All 9 manual smoke-test items pass on a known-good target
- [ ] Library shows the tall scroll capture with width/height matching the region

When everything checks out: ship v0.8.0 alpha. Plan 9 is next — PDF export + Sparkle integration + Settings completion.
