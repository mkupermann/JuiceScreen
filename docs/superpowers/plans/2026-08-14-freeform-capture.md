# FreeForm Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture a non-rectangular screen region drawn freehand or as a polygon, saved as a transparent PNG cropped to the shape's bounding box.

**Architecture:** The multi-display overlay plumbing is extracted from `RegionPickerController` into a generic `OverlayPickerHost<Payload>`; region and freeform become two thin controllers over it. Selection geometry (`FreeformSelection`) and masking (`FreeformMasker`) are pure, non-`@MainActor` units with full unit tests. Transparency survives to PNG; JPG, PDF and thumbnails flatten onto white explicitly.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, CoreGraphics, ScreenCaptureKit, swift-testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-14-freeform-capture-design.md`

## Global Constraints

- `SWIFT_VERSION: "5.10"`, `SWIFT_STRICT_CONCURRENCY: complete`. New types crossing concurrency domains must be `Sendable`; types holding non-`Sendable` AppKit state are `@MainActor`.
- Deployment target macOS 14.0. No API newer than that without a guard.
- Tests use **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), never XCTest.
- `project.yml` is the source of truth. **After creating any new `.swift` file, run `xcodegen generate` before building** — files not in the regenerated `.xcodeproj` are silently ignored and the test count stays constant with no error.
- `.xcodeproj` is NOT committed.
- Full test command: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests`
- Single suite: append `/SuiteTypeName`, e.g. `-only-testing:JuiceScreenTests/FreeformSelectionTests`.
- The authoritative pass/fail signal is `** TEST SUCCEEDED **` / `** TEST FAILED **`, not the per-test `✔`/`◇` lines.
- Baseline before this plan: **389 tests / 76 suites**, all passing.
- Coordinate rule: only bounding boxes cross the global/local boundary, and only through `ScreenCaptureKitHelpers`. Never hand-roll a coordinate conversion in a new call site.

---

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `JuiceScreen/Capture/Image/FreeformSelection.swift` | Pure selection geometry in overlay-local top-left points |
| `JuiceScreen/Capture/Image/FreeformMasker.swift` | Pure: clip a `CGImage` to a `CGPath`, transparent outside |
| `JuiceScreen/Capture/Image/OverlayPickerHost.swift` | Generic multi-display overlay window plumbing |
| `JuiceScreen/Capture/Image/FreeformPickerView.swift` | SwiftUI overlay surface for freehand + polygon |
| `JuiceScreen/Capture/Image/FreeformPickerController.swift` | Drives the host, converts local → global |
| `JuiceScreen/Shared/ImageFlattener.swift` | Composite an `NSImage` onto opaque white |
| `JuiceScreen/Annotation/Canvas/CheckerboardBackground.swift` | Editor-only transparency backdrop |
| `JuiceScreenTests/FreeformSelectionTests.swift` | |
| `JuiceScreenTests/FreeformMaskerTests.swift` | |
| `JuiceScreenTests/ImageFlattenerTests.swift` | |

**Modify:**

| File | Change |
|---|---|
| `JuiceScreen/Capture/Image/ScreenCaptureKitHelpers.swift` | add `globalBottomLeft(localTL:screenFrame:)` |
| `JuiceScreen/Capture/Image/RegionPickerController.swift` | use the new helper; rebuild on `OverlayPickerHost` |
| `JuiceScreen/Capture/Image/CaptureEngineLive.swift` | extract `captureRect(globalBL:)`; add `captureFreeform` |
| `JuiceScreen/Capture/Image/CaptureEngine.swift` | add `captureFreeform()` |
| `JuiceScreen/Capture/Image/FakeCaptureEngine.swift` | implement `captureFreeform()` |
| `JuiceScreen/Shared/CaptureType.swift` | add `freeform` case |
| `JuiceScreen/Annotation/Export/JPGEncoder.swift` | flatten on entry |
| `JuiceScreen/Annotation/Export/PDFEncoder.swift` | flatten on entry |
| `JuiceScreen/Library/…/ThumbnailGenerator.swift` | fill white before drawing |
| `JuiceScreen/MenuBar/HotkeyService.swift` | `HotkeyAction.captureFreeform = 9` |
| `JuiceScreen/MenuBar/MenuBarMenuBuilder.swift` | menu item + action closure |
| `JuiceScreen/Preferences/Preferences.swift` | `captureFreeformHotkey` |
| `JuiceScreen/App/AppDelegate.swift` | wire action + hotkey + `fireCapture` case |
| `JuiceScreen/Annotation/Editor/EditorView.swift` | checkerboard under the canvas |
| `JuiceScreenTests/ScreenCaptureKitHelpersTests.swift` | round-trip via the new helper |

---

### Task 1: `globalBottomLeft` helper and its round-trip

The inverse of `displayLocalTopLeft` currently lives inline in `RegionPickerController.commit()`. Moving it next to its inverse means one formula, tested in both directions.

**Files:**
- Modify: `JuiceScreen/Capture/Image/ScreenCaptureKitHelpers.swift`
- Modify: `JuiceScreen/Capture/Image/RegionPickerController.swift:108-125`
- Test: `JuiceScreenTests/ScreenCaptureKitHelpersTests.swift`

**Interfaces:**
- Consumes: `ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL:displayFrame:)` (exists).
- Produces: `ScreenCaptureKitHelpers.globalBottomLeft(localTL: CGRect, screenFrame: CGRect) -> CGRect`.

- [ ] **Step 1: Write the failing test**

Append to `JuiceScreenTests/ScreenCaptureKitHelpersTests.swift`, inside `struct DisplayLocalTopLeftTests`:

```swift
    @Test("globalBottomLeft is the exact inverse of displayLocalTopLeft")
    func globalBottomLeftInverse() {
        let screen = CGRect(x: 1920, y: 240, width: 2560, height: 1440)
        let localTL = CGRect(x: 120, y: 340, width: 500, height: 250)

        let global = ScreenCaptureKitHelpers.globalBottomLeft(localTL: localTL, screenFrame: screen)
        // local BL y = 1440 - (340 + 250) = 850 → global y = 850 + 240 = 1090
        #expect(global == CGRect(x: 2040, y: 1090, width: 500, height: 250))

        let back = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: screen)
        #expect(back == localTL)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/DisplayLocalTopLeftTests 2>&1 | tail -20`
Expected: compile error, `type 'ScreenCaptureKitHelpers' has no member 'globalBottomLeft'`.

- [ ] **Step 3: Write minimal implementation**

In `ScreenCaptureKitHelpers.swift`, directly below `displayLocalTopLeft`:

```swift
    /// Inverse of `displayLocalTopLeft(globalBL:displayFrame:)`: converts an
    /// overlay-local, top-left-origin rect into AppKit's global bottom-left space.
    ///
    /// - Parameters:
    ///   - rect: The rect in the overlay's local top-left coordinates (points).
    ///   - screenFrame: The overlay screen's `NSScreen.frame` (points).
    public static func globalBottomLeft(localTL rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + screenFrame.minX,
            y: (screenFrame.height - (rect.minY + rect.height)) + screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/DisplayLocalTopLeftTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Use the helper in `RegionPickerController.commit`**

Replace the body of `commit(localRect:on:)` between the `guard` and `finish(.success(globalRect))`:

```swift
        let globalRect = ScreenCaptureKitHelpers.globalBottomLeft(
            localTL: localRect,
            screenFrame: screen.frame
        )
        finish(.success(globalRect))
```

Delete the now-dead `let frame = screen.frame` and `let blLocalY = …` lines and the two-line comment above them.

- [ ] **Step 6: Run the full suite**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`, 390 tests.

- [ ] **Step 7: Commit**

```bash
git add JuiceScreen/Capture/Image/ScreenCaptureKitHelpers.swift \
        JuiceScreen/Capture/Image/RegionPickerController.swift \
        JuiceScreenTests/ScreenCaptureKitHelpersTests.swift
git commit -m "refactor(capture): share the local-TL to global-BL conversion"
```

---

### Task 2: `FreeformSelection`

**Files:**
- Create: `JuiceScreen/Capture/Image/FreeformSelection.swift`
- Test: `JuiceScreenTests/FreeformSelectionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `FreeformMode` (`.freehand`, `.polygon`); `FreeformSelection` with `init(mode:points:)`, `mutating setMode(_:)`, `mutating append(_:)`, `mutating appendVertex(_:)`, `mutating removeLastVertex()`, `var bounds: CGRect`, `var isUsable: Bool`, `var closedPath: CGPath`, `var pathInBounds: CGPath`, `static let minimumPointSpacing: CGFloat`.

- [ ] **Step 1: Write the failing tests**

Create `JuiceScreenTests/FreeformSelectionTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FreeformSelection")
struct FreeformSelectionTests {

    @Test("Freehand append drops points closer than the minimum spacing")
    func minimumSpacing() {
        var s = FreeformSelection(mode: .freehand)
        s.append(CGPoint(x: 0, y: 0))
        s.append(CGPoint(x: 1, y: 0))     // 1pt away — dropped
        s.append(CGPoint(x: 2, y: 0))     // 2pt from the first kept point — kept
        #expect(s.points == [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0)])
    }

    @Test("Polygon vertices are never distance-filtered")
    func polygonKeepsEveryVertex() {
        var s = FreeformSelection(mode: .polygon)
        s.appendVertex(CGPoint(x: 0, y: 0))
        s.appendVertex(CGPoint(x: 1, y: 0))
        s.appendVertex(CGPoint(x: 1, y: 1))
        #expect(s.points.count == 3)
    }

    @Test("removeLastVertex undoes one point and is safe when empty")
    func undoVertex() {
        var s = FreeformSelection(mode: .polygon)
        s.appendVertex(CGPoint(x: 5, y: 5))
        s.removeLastVertex()
        #expect(s.points.isEmpty)
        s.removeLastVertex()          // must not trap
        #expect(s.points.isEmpty)
    }

    @Test("bounds is the outward-rounded box around all points")
    func boundsRoundOutward() {
        var s = FreeformSelection(mode: .polygon)
        s.appendVertex(CGPoint(x: 10.4, y: 20.7))
        s.appendVertex(CGPoint(x: 50.2, y: 20.7))
        s.appendVertex(CGPoint(x: 30.0, y: 60.1))
        #expect(s.bounds == CGRect(x: 10, y: 20, width: 41, height: 41))
    }

    @Test("bounds is identical whichever direction the shape is drawn")
    func boundsDirectionIndependent() {
        var a = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 40, y: 30)] { a.appendVertex(p) }
        var b = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 40, y: 30), CGPoint(x: 40, y: 0), CGPoint(x: 0, y: 0)] { b.appendVertex(p) }
        #expect(a.bounds == b.bounds)
    }

    @Test("isUsable requires three points and a box of at least 1x1")
    func usability() {
        var two = FreeformSelection(mode: .polygon)
        two.appendVertex(CGPoint(x: 0, y: 0))
        two.appendVertex(CGPoint(x: 10, y: 10))
        #expect(two.isUsable == false)

        var degenerate = FreeformSelection(mode: .polygon)
        for _ in 0..<3 { degenerate.appendVertex(CGPoint(x: 7, y: 7)) }
        #expect(degenerate.isUsable == false)

        var ok = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 4)] { ok.appendVertex(p) }
        #expect(ok.isUsable == true)
    }

    @Test("pathInBounds is the closed path translated to the bounds origin")
    func pathInBoundsTranslation() {
        var s = FreeformSelection(mode: .polygon)
        for p in [CGPoint(x: 100, y: 200), CGPoint(x: 140, y: 200), CGPoint(x: 140, y: 230)] {
            s.appendVertex(p)
        }
        #expect(s.bounds.origin == CGPoint(x: 100, y: 200))
        #expect(s.pathInBounds.boundingBox.origin.x == 0)
        #expect(s.pathInBounds.boundingBox.origin.y == 0)
        #expect(s.closedPath.isEmpty == false)
    }

    @Test("Mode can be switched only before the first point")
    func modeLock() {
        var s = FreeformSelection(mode: .freehand)
        s.setMode(.polygon)
        #expect(s.mode == .polygon)
        s.appendVertex(CGPoint(x: 1, y: 1))
        s.setMode(.freehand)
        #expect(s.mode == .polygon)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FreeformSelectionTests 2>&1 | tail -20`
Expected: build failure, `cannot find 'FreeformSelection' in scope`. (The test file itself compiles only after `xcodegen generate` in Step 3 — if the run instead reports the old passing count with no error, the file is not in the project yet.)

- [ ] **Step 3: Write the implementation**

Create `JuiceScreen/Capture/Image/FreeformSelection.swift`:

```swift
import CoreGraphics
import Foundation

/// Which drawing interaction produced a `FreeformSelection`.
public enum FreeformMode: String, Sendable, CaseIterable {
    case freehand
    case polygon
}

/// A non-rectangular selection in overlay-local, top-left-origin points.
///
/// Pure value type: no AppKit, no actor isolation. The picker view mutates it
/// during the gesture; `FreeformPickerController` converts `bounds` to global
/// screen coordinates once, at commit time.
public struct FreeformSelection: Equatable, Sendable {

    /// Freehand points closer together than this are dropped. A slow drag
    /// otherwise accumulates thousands of collinear points that carry no
    /// information and slow down both the live mask and the final clip.
    public static let minimumPointSpacing: CGFloat = 2

    public private(set) var mode: FreeformMode
    public private(set) var points: [CGPoint]

    public init(mode: FreeformMode, points: [CGPoint] = []) {
        self.mode = mode
        self.points = points
    }

    /// Switching modes mid-shape would leave the points half-freehand and
    /// half-polygon, so it is only allowed before the first point.
    public mutating func setMode(_ newMode: FreeformMode) {
        guard points.isEmpty else { return }
        mode = newMode
    }

    /// Freehand: appends `point` unless it is within `minimumPointSpacing` of
    /// the previous one.
    public mutating func append(_ point: CGPoint) {
        guard let last = points.last else {
            points.append(point)
            return
        }
        let dx = point.x - last.x
        let dy = point.y - last.y
        guard (dx * dx + dy * dy) >= (Self.minimumPointSpacing * Self.minimumPointSpacing) else {
            return
        }
        points.append(point)
    }

    /// Polygon: appends a deliberate vertex, unfiltered.
    public mutating func appendVertex(_ point: CGPoint) {
        points.append(point)
    }

    public mutating func removeLastVertex() {
        guard !points.isEmpty else { return }
        points.removeLast()
    }

    /// Bounding box of every point, rounded outward to whole points so the
    /// captured rect never clips the shape by a sub-point sliver.
    public var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    public var isUsable: Bool {
        points.count >= 3 && bounds.width >= 1 && bounds.height >= 1
    }

    /// The selection as a closed path, in overlay-local top-left coordinates.
    public var closedPath: CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() {
            path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    /// `closedPath` translated so that `bounds.origin` becomes (0, 0). This is
    /// the form handed to `FreeformMasker` — the path is never expressed in
    /// global screen coordinates.
    public var pathInBounds: CGPath {
        let origin = bounds.origin
        var transform = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        return closedPath.copy(using: &transform) ?? closedPath
    }
}
```

- [ ] **Step 4: Regenerate the project and run the tests**

```bash
xcodegen generate
xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FreeformSelectionTests 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`, 8 tests in the suite.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/FreeformSelection.swift JuiceScreenTests/FreeformSelectionTests.swift
git commit -m "feat(capture): FreeformSelection geometry"
```

---

### Task 3: `FreeformMasker`

**Files:**
- Create: `JuiceScreen/Capture/Image/FreeformMasker.swift`
- Test: `JuiceScreenTests/FreeformMaskerTests.swift`

**Interfaces:**
- Consumes: nothing (takes a `CGPath` — in practice `FreeformSelection.pathInBounds` from Task 2).
- Produces: `FreeformMasker.apply(path: CGPath, pathSpaceSize: CGSize, to image: CGImage) -> CGImage?`.

- [ ] **Step 1: Write the failing tests**

Create `JuiceScreenTests/FreeformMaskerTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FreeformMasker")
struct FreeformMaskerTests {

    /// Opaque red image of the given pixel size.
    private func redImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// RGBA of one pixel, addressed from the TOP-LEFT of the image.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let i = (y * image.width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    /// Top-left quadrant, in a 100x100 top-left-origin path space.
    private var topLeftQuadrant: CGPath {
        CGPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50), transform: nil)
    }

    @Test("Pixels inside the path stay opaque, pixels outside become transparent")
    func insideOpaqueOutsideTransparent() throws {
        let source = redImage(width: 100, height: 100)
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 100, height: 100), to: source)
        )
        #expect(pixel(masked, x: 10, y: 10).a == 255)
        #expect(pixel(masked, x: 90, y: 90).a == 0)
    }

    @Test("The mask is not vertically mirrored")
    func noVerticalMirror() throws {
        // Asymmetric on purpose: a mirrored mask would keep the BOTTOM-left
        // quadrant instead, and a symmetric shape would hide the bug entirely.
        let source = redImage(width: 100, height: 100)
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 100, height: 100), to: source)
        )
        #expect(pixel(masked, x: 10, y: 10).a == 255)   // top-left: kept
        #expect(pixel(masked, x: 10, y: 90).a == 0)     // bottom-left: dropped
        #expect(pixel(masked, x: 90, y: 10).a == 0)     // top-right: dropped
    }

    @Test("Path points are scaled to image pixels (Retina 2:1)")
    func retinaScale() throws {
        let source = redImage(width: 200, height: 200)
        // Same quadrant, but the path space is 100x100 points against a 200x200
        // pixel image, so the kept area must cover pixels 0..<100.
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 100, height: 100), to: source)
        )
        #expect(pixel(masked, x: 20, y: 20).a == 255)
        #expect(pixel(masked, x: 120, y: 20).a == 0)
        #expect(pixel(masked, x: 20, y: 120).a == 0)
    }

    @Test("Output keeps the source pixel dimensions")
    func dimensionsPreserved() throws {
        let source = redImage(width: 64, height: 48)
        let masked = try #require(
            FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: CGSize(width: 64, height: 48), to: source)
        )
        #expect(masked.width == 64)
        #expect(masked.height == 48)
    }

    @Test("Zero-sized path space returns nil rather than dividing by zero")
    func zeroPathSpace() {
        let source = redImage(width: 10, height: 10)
        #expect(FreeformMasker.apply(path: topLeftQuadrant, pathSpaceSize: .zero, to: source) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FreeformMaskerTests 2>&1 | tail -20`
Expected: build failure, `cannot find 'FreeformMasker' in scope`.

- [ ] **Step 3: Write the implementation**

Create `JuiceScreen/Capture/Image/FreeformMasker.swift`:

```swift
import CoreGraphics
import Foundation

/// Clips a captured image to an arbitrary path, leaving everything outside the
/// path fully transparent.
///
/// Pure function: no AppKit, no actor isolation, no shared state.
public enum FreeformMasker {

    /// - Parameters:
    ///   - path: The shape to keep, in a **top-left-origin** space of size
    ///     `pathSpaceSize` (i.e. `FreeformSelection.pathInBounds`).
    ///   - pathSpaceSize: The size of that space, in points.
    ///   - image: The captured image, in pixels. May be larger than
    ///     `pathSpaceSize` on Retina displays.
    /// - Returns: A new image of the same pixel dimensions with alpha 0 outside
    ///   the path, or nil if the inputs are degenerate or the context cannot be
    ///   allocated.
    public static func apply(path: CGPath, pathSpaceSize: CGSize, to image: CGImage) -> CGImage? {
        guard pathSpaceSize.width > 0, pathSpaceSize.height > 0,
              image.width > 0, image.height > 0 else {
            return nil
        }

        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // The path is top-left origin, CGContext is bottom-left. Flip once and
        // scale points to pixels in the same transform: a point (x, y) maps to
        // (x * scaleX, height - y * scaleY).
        let scaleX = CGFloat(image.width) / pathSpaceSize.width
        let scaleY = CGFloat(image.height) / pathSpaceSize.height
        var transform = CGAffineTransform(translationX: 0, y: CGFloat(image.height))
            .scaledBy(x: scaleX, y: -scaleY)

        guard let scaledPath = path.copy(using: &transform) else { return nil }

        ctx.addPath(scaledPath)
        ctx.clip()
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

```bash
xcodegen generate
xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FreeformMaskerTests 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/FreeformMasker.swift JuiceScreenTests/FreeformMaskerTests.swift
git commit -m "feat(capture): FreeformMasker path clipping"
```

---

### Task 4: `ImageFlattener` and the three formats that cannot carry alpha

**Files:**
- Create: `JuiceScreen/Shared/ImageFlattener.swift`
- Modify: `JuiceScreen/Annotation/Export/JPGEncoder.swift`
- Modify: `JuiceScreen/Annotation/Export/PDFEncoder.swift`
- Modify: `JuiceScreen/Library/Thumbnails/ThumbnailGenerator.swift` (locate with `find JuiceScreen -name ThumbnailGenerator.swift`)
- Test: `JuiceScreenTests/ImageFlattenerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ImageFlattener.onWhite(_ image: NSImage) -> NSImage`.

- [ ] **Step 1: Write the failing tests**

Create `JuiceScreenTests/ImageFlattenerTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("ImageFlattener")
struct ImageFlattenerTests {

    /// A 20x20 image: left half opaque red, right half fully transparent.
    private func halfTransparentImage() -> NSImage {
        let ctx = CGContext(
            data: nil, width: 20, height: 20,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: 20, height: 20))
    }

    private func pixel(_ image: NSImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        data.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        let i = (y * cg.width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    @Test("Transparent areas become white, not black")
    func transparentBecomesWhite() {
        let flat = ImageFlattener.onWhite(halfTransparentImage())
        let right = pixel(flat, x: 15, y: 10)
        #expect(right.a == 255)
        #expect(right.r == 255)
        #expect(right.g == 255)
        #expect(right.b == 255)
    }

    @Test("Opaque areas are untouched")
    func opaqueUnchanged() {
        let flat = ImageFlattener.onWhite(halfTransparentImage())
        let left = pixel(flat, x: 5, y: 10)
        #expect(left.r == 255)
        #expect(left.g == 0)
        #expect(left.b == 0)
        #expect(left.a == 255)
    }

    @Test("Pixel dimensions are preserved")
    func dimensionsPreserved() {
        let flat = ImageFlattener.onWhite(halfTransparentImage())
        let cg = flat.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        #expect(cg.width == 20)
        #expect(cg.height == 20)
    }

    @Test("JPGEncoder renders transparent source areas white")
    func jpgIsWhiteNotBlack() throws {
        let data = try JPGEncoder.encode(halfTransparentImage(), quality: 1.0)
        let decoded = NSImage(data: data)!
        let right = pixel(decoded, x: 15, y: 10)
        // JPEG is lossy — assert "bright", not exactly 255.
        #expect(right.r > 240)
        #expect(right.g > 240)
        #expect(right.b > 240)
    }

    @Test("PNGEncoder preserves the alpha channel")
    func pngKeepsAlpha() throws {
        let data = try PNGEncoder.encode(halfTransparentImage())
        let decoded = NSImage(data: data)!
        #expect(pixel(decoded, x: 15, y: 10).a == 0)     // transparent half stays transparent
        #expect(pixel(decoded, x: 5, y: 10).a == 255)    // opaque half stays opaque
    }

    @Test("ThumbnailGenerator renders transparent areas white, not black")
    func thumbnailIsWhiteNotBlack() throws {
        let data = try ThumbnailGenerator.generate(from: halfTransparentImage(), maxDimension: 20, quality: 1.0)
        let decoded = NSImage(data: data)!
        let right = pixel(decoded, x: 15, y: 10)
        #expect(right.r > 240)
        #expect(right.g > 240)
        #expect(right.b > 240)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/ImageFlattenerTests 2>&1 | tail -20`
Expected: build failure, `cannot find 'ImageFlattener' in scope`.

- [ ] **Step 3: Write `ImageFlattener`**

Create `JuiceScreen/Shared/ImageFlattener.swift`:

```swift
import AppKit
import Foundation

/// Composites an image onto opaque white.
///
/// PNG carries alpha; JPEG and PDF do not. Leaving the flattening to AppKit
/// produces a **black** background for transparent areas, which is the wrong
/// default for a screenshot tool — so every lossy path flattens explicitly.
public enum ImageFlattener {

    public static func onWhite(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0,
              let ctx = CGContext(
                data: nil,
                width: cg.width,
                height: cg.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return image
        }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(full)
        ctx.draw(cg, in: full)
        guard let flattened = ctx.makeImage() else { return image }
        return NSImage(cgImage: flattened, size: image.size)
    }
}
```

- [ ] **Step 4: Route JPG and PDF through it**

In `JPGEncoder.encode`, immediately after the `zeroSize` guard:

```swift
        let image = ImageFlattener.onWhite(image)
```

In `PDFEncoder.encode`, immediately after the `zeroSize` guard:

```swift
        let image = ImageFlattener.onWhite(image)
```

Both shadow the parameter deliberately, so no later line in either function can reach the unflattened original.

- [ ] **Step 5: Fill the thumbnail context with white**

In `ThumbnailGenerator.generate`, after `nsCtx.imageInterpolation = .high` and before the `nsCtx.cgContext.draw(...)` line:

```swift
        nsCtx.cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        nsCtx.cgContext.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
```

The generator already allocates a target-sized context, so filling it directly avoids a full-resolution RGBA copy of the source that `ImageFlattener.onWhite` would make before the downscale.

- [ ] **Step 6: Regenerate and run the full suite**

```bash
xcodegen generate
xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`. The existing `JPGEncoderTests`, `PDFEncoderTests` and thumbnail tests must pass **unchanged** — if one now fails, the flattening changed behaviour for opaque input, which it must not.

- [ ] **Step 7: Commit**

```bash
git add JuiceScreen/Shared/ImageFlattener.swift \
        JuiceScreen/Annotation/Export/JPGEncoder.swift \
        JuiceScreen/Annotation/Export/PDFEncoder.swift \
        JuiceScreen/Library/Thumbnails/ThumbnailGenerator.swift \
        JuiceScreenTests/ImageFlattenerTests.swift
git commit -m "feat(export): flatten alpha onto white for JPG, PDF and thumbnails"
```

---

### Task 5: `OverlayPickerHost` and `RegionPickerController` rebuilt on it

**Honest note on testing:** this task has no unit test. The host owns `NSWindow`, `NSScreen` and a global event monitor; none of it is reachable from a test process without a real display session. The regression guard is that the full suite still passes and that the manual smoke check in Step 4 behaves exactly as before. Do not invent a test that asserts nothing.

**Files:**
- Create: `JuiceScreen/Capture/Image/OverlayPickerHost.swift`
- Modify: `JuiceScreen/Capture/Image/RegionPickerController.swift` (rewritten)

**Interfaces:**
- Consumes: `RegionPickerOverlayWindow` (exists), `ScreenCaptureKitHelpers.globalBottomLeft(localTL:screenFrame:)` (Task 1).
- Produces: `OverlayPickerHost<Payload>` with nested `Result` (`payload`, `screen`), `typealias ContentBuilder`, and `func pick(content: @escaping ContentBuilder) async throws -> Result`.

- [ ] **Step 1: Write the host**

Create `JuiceScreen/Capture/Image/OverlayPickerHost.swift`:

```swift
import AppKit
import SwiftUI

/// Multi-display overlay plumbing shared by every picker.
///
/// Owns one borderless overlay window per `NSScreen`, decides which overlay owns
/// the in-flight gesture, installs the Esc-to-cancel monitor, and bridges the
/// callback flow to `async`. It deliberately knows nothing about geometry —
/// callers convert coordinates themselves, using the screen this returns.
@MainActor
final class OverlayPickerHost<Payload> {

    struct Result {
        let payload: Payload
        let screen: NSScreen
    }

    /// Builds the SwiftUI surface for one overlay. `isActive` is false for every
    /// overlay except the one that started the current gesture.
    typealias ContentBuilder = (
        _ screen: NSScreen,
        _ isActive: Bool,
        _ onBegan: @escaping () -> Void,
        _ onCommitted: @escaping (Payload?) -> Void
    ) -> AnyView

    private struct Overlay {
        let window: RegionPickerOverlayWindow
        let screen: NSScreen
    }

    private var overlays: [Overlay] = []
    private var continuation: CheckedContinuation<Result, Error>?
    private var activeScreen: NSScreen?
    private var escMonitor: Any?
    private var builder: ContentBuilder?

    func pick(content: @escaping ContentBuilder) async throws -> Result {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw CaptureError.noDisplaysAvailable
        }
        builder = content

        for screen in screens {
            let win = RegionPickerOverlayWindow(frame: screen.frame)
            overlays.append(Overlay(window: win, screen: screen))
        }
        for entry in overlays {
            installContent(for: entry)
            entry.window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        installEscMonitor()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Result, Error>) in
            self.continuation = cont
        }
    }

    // MARK: - Overlay content

    private func installContent(for entry: Overlay) {
        guard let builder else { return }
        let view = builder(
            entry.screen,
            activeScreen == nil ? true : (activeScreen === entry.screen),
            { [weak self] in self?.markActive(entry.screen) },
            { [weak self] payload in self?.commit(payload, on: entry.screen) }
        )
        entry.window.contentView = NSHostingView(rootView: view)
    }

    /// First overlay to start a gesture owns it; the others are rebuilt with
    /// `isActive = false` so they stop responding.
    private func markActive(_ screen: NSScreen) {
        guard activeScreen == nil else { return }
        activeScreen = screen
        for entry in overlays where entry.screen !== screen {
            installContent(for: entry)
        }
    }

    // MARK: - Esc

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.commit(nil, on: self.activeScreen ?? self.overlays.first!.screen)
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let m = escMonitor {
            NSEvent.removeMonitor(m)
            escMonitor = nil
        }
    }

    // MARK: - Commit

    private func commit(_ payload: Payload?, on screen: NSScreen) {
        guard continuation != nil else { return }   // already finished
        guard let payload else {
            finish(.failure(CaptureError.userCancelled))
            return
        }
        finish(.success(Result(payload: payload, screen: screen)))
    }

    private func finish(_ outcome: Swift.Result<Result, Error>) {
        removeEscMonitor()
        for entry in overlays { entry.window.orderOut(nil) }
        overlays.removeAll()
        activeScreen = nil
        builder = nil
        switch outcome {
        case .success(let result): continuation?.resume(returning: result)
        case .failure(let error):  continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
```

- [ ] **Step 2: Rewrite `RegionPickerController` on top of the host**

Replace the whole body of `JuiceScreen/Capture/Image/RegionPickerController.swift` with:

```swift
import AppKit
import SwiftUI

/// Rectangular region picker.
///
/// The overlay mechanics live in `OverlayPickerHost`; this type only supplies
/// the SwiftUI surface and converts the committed rect from the overlay's local
/// top-left space into AppKit's global bottom-left space.
@MainActor
public final class RegionPickerController {

    private let host = OverlayPickerHost<CGRect>()

    public init() {}

    /// Returns the selected rect in global bottom-left screen coordinates.
    public func pickRegion() async throws -> CGRect {
        let result = try await host.pick { screen, isActive, onBegan, onCommitted in
            AnyView(
                RegionPickerView(
                    canvasSize: screen.frame.size,
                    isActive: isActive,
                    onBegan: onBegan,
                    onCommitted: { localRect in
                        guard let localRect, localRect.width >= 1, localRect.height >= 1 else {
                            onCommitted(nil)
                            return
                        }
                        onCommitted(localRect)
                    }
                )
            )
        }
        return ScreenCaptureKitHelpers.globalBottomLeft(
            localTL: result.payload,
            screenFrame: result.screen.frame
        )
    }
}
```

- [ ] **Step 3: Regenerate and run the full suite**

```bash
xcodegen generate
xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`, same count as after Task 4.

- [ ] **Step 4: Manual smoke check (required — no test covers this)**

```bash
scripts/build-release.sh && open build/JuiceScreen.app
```

Verify, on a multi-display setup if available: Capture Region opens overlays on every display; dragging on one deactivates the others; the captured PNG matches the selected area on both the main and a secondary display; Esc cancels with no window left behind.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/OverlayPickerHost.swift JuiceScreen/Capture/Image/RegionPickerController.swift
git commit -m "refactor(capture): extract OverlayPickerHost from RegionPickerController"
```

---

### Task 6: FreeForm picker view and controller

**Testing note:** as in Task 5, the SwiftUI surface and the controller are not unit-testable — `CanvasGestures` and `LayerRenderer` are already documented in this repo as untestable for the same reason. All the logic worth testing was pushed into `FreeformSelection` in Task 2. The check here is the manual smoke step.

**Files:**
- Create: `JuiceScreen/Capture/Image/FreeformPickerView.swift`
- Create: `JuiceScreen/Capture/Image/FreeformPickerController.swift`

**Interfaces:**
- Consumes: `FreeformSelection` (Task 2), `OverlayPickerHost<Payload>` (Task 5), `ScreenCaptureKitHelpers.globalBottomLeft(localTL:screenFrame:)` (Task 1).
- Produces: `FreeformPick` (`globalBoundsBL: CGRect`, `pathInBounds: CGPath`); `FreeformPickerController.pickFreeform() async throws -> FreeformPick`.

- [ ] **Step 1: Write the view**

Create `JuiceScreen/Capture/Image/FreeformPickerView.swift`:

```swift
import SwiftUI

/// One overlay's interactive surface for freeform selection.
///
/// Same `GeometryReader` discipline as `RegionPickerView`: gesture space and
/// render space must be the same `proxy.size` rect, or safe-area insets shift
/// the drawn path away from where the gesture thinks it is.
struct FreeformPickerView: View {

    let canvasSize: CGSize
    let isActive: Bool
    let onBegan: () -> Void
    let onCommitted: (FreeformSelection?) -> Void

    @State private var selection = FreeformSelection(mode: .freehand)
    @State private var cursor: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.35)
                    .mask(dimMask)

                Path(selection.closedPath)
                    .stroke(Color.white, lineWidth: 1)
                    .allowsHitTesting(false)

                if selection.mode == .polygon, let cursor, let last = selection.points.last {
                    Path { p in
                        p.move(to: last)
                        p.addLine(to: cursor)
                    }
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .allowsHitTesting(false)
                }

                if let cursor, selection.isUsable {
                    Text("\(Int(selection.bounds.width)) × \(Int(selection.bounds.height))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: cursor.x + 16, y: cursor.y + 16)
                        .allowsHitTesting(false)
                }

                hud
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(freehandGesture)
            .onTapGesture(count: 2) { closeIfPossible() }
            .simultaneousGesture(polygonTap)
            .onContinuousHover { phase in
                if case .active(let point) = phase { cursor = point } else { cursor = nil }
            }
        }
        .ignoresSafeArea()
        // focusable() is required — onKeyPress only fires for a focused view, and
        // without it Tab / Return / Backspace silently do nothing in the overlay.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.tab) { toggleMode(); return .handled }
        .onKeyPress(.return) { closeIfPossible(); return .handled }
        .onKeyPress(.delete) { selection.removeLastVertex(); return .handled }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var dimMask: some View {
        if selection.points.count >= 3 {
            Rectangle()
                .overlay(Path(selection.closedPath).fill(Color.black).blendMode(.destinationOut))
                .compositingGroup()
        } else {
            Rectangle()
        }
    }

    private var hud: some View {
        VStack {
            Spacer()
            Text(selection.mode == .freehand
                 ? "Freehand · Tab for polygon · Esc cancels"
                 : "Polygon · click to add · ⏎ or double-click to close · ⌫ undo · Esc cancels")
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 24)
                .allowsHitTesting(false)
        }
    }

    private var freehandGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard selection.mode == .freehand else { return }
                if selection.points.isEmpty { onBegan() }
                guard isActive else { return }
                selection.append(value.location)
                cursor = value.location
            }
            .onEnded { _ in
                guard selection.mode == .freehand, isActive else { return }
                commit()
            }
    }

    private var polygonTap: some Gesture {
        SpatialTapGesture(count: 1, coordinateSpace: .local)
            .onEnded { value in
                guard selection.mode == .polygon else { return }
                if selection.points.isEmpty { onBegan() }
                guard isActive else { return }
                selection.appendVertex(value.location)
            }
    }

    // MARK: - Actions

    private func toggleMode() {
        selection.setMode(selection.mode == .freehand ? .polygon : .freehand)
    }

    private func closeIfPossible() {
        guard selection.mode == .polygon, isActive else { return }
        commit()
    }

    private func commit() {
        if selection.isUsable {
            onCommitted(selection)
        } else {
            onCommitted(nil)
        }
        selection = FreeformSelection(mode: selection.mode)
        cursor = nil
    }
}
```

- [ ] **Step 2: Write the controller**

Create `JuiceScreen/Capture/Image/FreeformPickerController.swift`:

```swift
import AppKit
import CoreGraphics
import SwiftUI

/// The result of a freeform pick.
///
/// Only the bounding box is expressed globally. The path stays relative to that
/// box, so exactly one coordinate conversion happens per capture and it happens
/// through `ScreenCaptureKitHelpers`.
public struct FreeformPick: @unchecked Sendable {
    public let globalBoundsBL: CGRect
    public let pathInBounds: CGPath
}

@MainActor
public final class FreeformPickerController {

    private let host = OverlayPickerHost<FreeformSelection>()

    public init() {}

    public func pickFreeform() async throws -> FreeformPick {
        let result = try await host.pick { screen, isActive, onBegan, onCommitted in
            AnyView(
                FreeformPickerView(
                    canvasSize: screen.frame.size,
                    isActive: isActive,
                    onBegan: onBegan,
                    onCommitted: onCommitted
                )
            )
        }
        let selection = result.payload
        return FreeformPick(
            globalBoundsBL: ScreenCaptureKitHelpers.globalBottomLeft(
                localTL: selection.bounds,
                screenFrame: result.screen.frame
            ),
            pathInBounds: selection.pathInBounds
        )
    }
}
```

- [ ] **Step 3: Regenerate and build**

```bash
xcodegen generate
xcodebuild build -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If `onKeyPress` or `onContinuousHover` fails to resolve, check the deployment target is 14.0 — both are available from macOS 14.

- [ ] **Step 4: Run the full suite**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`, unchanged count (this task adds no tests).

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Image/FreeformPickerView.swift JuiceScreen/Capture/Image/FreeformPickerController.swift
git commit -m "feat(capture): freeform picker overlay and controller"
```

---

### Task 7: Capture path — `captureRect` extraction and `captureFreeform`

**Files:**
- Modify: `JuiceScreen/Shared/CaptureType.swift`
- Modify: `JuiceScreen/Capture/Image/CaptureEngine.swift`
- Modify: `JuiceScreen/Capture/Image/FakeCaptureEngine.swift`
- Modify: `JuiceScreen/Capture/Image/CaptureEngineLive.swift`
- Test: `JuiceScreenTests/FakeCaptureEngineTests.swift`

**Interfaces:**
- Consumes: `FreeformPickerController.pickFreeform()` (Task 6), `FreeformMasker.apply(path:pathSpaceSize:to:)` (Task 3), `ScreenCaptureKitHelpers.displayLocalTopLeft` / `.display(containing:in:)` / `.globalFrame(of:)` (existing).
- Produces: `CaptureType.freeform`; `CaptureEngine.captureFreeform() async throws -> CaptureRecord`; private `CaptureEngineLive.captureRect(globalBL:) async throws -> (image: CGImage, display: SCDisplay)`.

- [ ] **Step 1: Write the failing test**

Append to `JuiceScreenTests/FakeCaptureEngineTests.swift`, inside the existing suite:

```swift
    @Test("captureFreeform dispatches and records the freeform call")
    func freeformDispatch() async throws {
        let engine = FakeCaptureEngine()
        let expected = CaptureRecord(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/freeform.png"),
            captureType: .freeform,
            capturedAt: Date(),
            pixelWidth: 100,
            pixelHeight: 80,
            sourceApp: nil
        )
        engine.recordsToReturn[.freeform] = .success(expected)

        let record = try await engine.captureFreeform()

        #expect(record.captureType == .freeform)
        #expect(engine.calls == [.freeform])
    }

    @Test("captureFreeform throws when no outcome is configured")
    func freeformDefaultsToCancelled() async {
        let engine = FakeCaptureEngine()
        await #expect(throws: CaptureError.userCancelled) {
            _ = try await engine.captureFreeform()
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FakeCaptureEngineTests 2>&1 | tail -20`
Expected: build failure, `type 'CaptureType' has no member 'freeform'`.

- [ ] **Step 3: Add the case, the protocol requirement and the fake**

`CaptureType.swift` — add below `case scroll`:

```swift
    case freeform
```

`CaptureEngine.swift` — add to the protocol:

```swift
    func captureFreeform() async throws -> CaptureRecord
```

`FakeCaptureEngine.swift` — add below `captureLastRegion()`:

```swift
    public func captureFreeform() async throws -> CaptureRecord {
        try await dispatch(.freeform)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/FakeCaptureEngineTests 2>&1 | tail -5`
Expected: build failure in `CaptureEngineLive` — it does not satisfy the protocol yet. That is expected; Step 5 fixes it.

- [ ] **Step 5: Extract `captureRect` in `CaptureEngineLive`**

Add this private method next to the other helpers:

```swift
    /// Shared by region, last-region and freeform: resolve the display holding
    /// the rect's centre, convert to `sourceRect` space, capture.
    /// `rect` is in global bottom-left screen coordinates.
    private func captureRect(globalBL rect: CGRect) async throws -> (image: CGImage, display: SCDisplay) {
        let content = try await ScreenCaptureKitHelpers.shareableContent()
        guard let display = ScreenCaptureKitHelpers.display(
            containing: CGPoint(x: rect.midX, y: rect.midY),
            in: content
        ) else {
            throw CaptureError.regionOutsideDisplays
        }
        let displayLocal = ScreenCaptureKitHelpers.displayLocalTopLeft(
            globalBL: rect,
            displayFrame: ScreenCaptureKitHelpers.globalFrame(of: display)
        )
        let filter = SCContentFilter(
            display: display,
            excludingApplications: try await ownApplications(),
            exceptingWindows: []
        )
        let cfg = ScreenCaptureKitHelpers.configuration(for: display, regionInPoints: displayLocal)
        let cg = try await ScreenCaptureKitHelpers.captureImage(filter: filter, configuration: cfg)
        return (cg, display)
    }
```

Then replace the body of `captureLastRegionInternal()` after the `guard let regionInScreen` block with:

```swift
        let (cg, display) = try await captureRect(globalBL: regionInScreen)
        return try await persist(cg: cg, captureType: .lastRegion, sourceApp: nil,
                                 scaleFactor: backingScaleFactor(for: display))
```

and the body of `captureRegionInternal()` after `let regionInScreen = try await regionPicker.pickRegion()` with:

```swift
        let (cg, display) = try await captureRect(globalBL: regionInScreen)

        // Remember this region for "Capture Last Region".
        var prefs = preferences.load()
        prefs.lastRegion = regionInScreen
        preferences.save(prefs)

        return try await persist(cg: cg, captureType: .region, sourceApp: nil,
                                 scaleFactor: backingScaleFactor(for: display))
```

- [ ] **Step 6: Add `captureFreeform` to `CaptureEngineLive`**

Add the picker property next to `regionPicker`:

```swift
    private let freeformPicker: FreeformPickerController
```

and in `init`, next to `self.regionPicker = RegionPickerController()`:

```swift
        self.freeformPicker = FreeformPickerController()
```

Add the `nonisolated` entry point next to the others:

```swift
    nonisolated public func captureFreeform() async throws -> CaptureRecord {
        try await captureFreeformInternal()
    }
```

and the implementation next to `captureRegionInternal`:

```swift
    private func captureFreeformInternal() async throws -> CaptureRecord {
        let pick = try await freeformPicker.pickFreeform()
        let (cg, display) = try await captureRect(globalBL: pick.globalBoundsBL)

        // The path is in points relative to the bounding box; the image is in
        // pixels. FreeformMasker scales between the two.
        guard let masked = FreeformMasker.apply(
            path: pick.pathInBounds,
            pathSpaceSize: pick.globalBoundsBL.size,
            to: cg
        ) else {
            throw CaptureError.captureFailed(underlying: "Freeform masking failed")
        }

        return try await persist(cg: masked, captureType: .freeform, sourceApp: nil,
                                 scaleFactor: backingScaleFactor(for: display))
    }
```

- [ ] **Step 7: Regenerate and run the full suite**

```bash
xcodegen generate
xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`. If a `switch` over `CaptureType` now fails to compile as non-exhaustive, add the `.freeform` case there rather than a `default:` — the compiler error is the feature.

- [ ] **Step 8: Commit**

```bash
git add JuiceScreen/Shared/CaptureType.swift \
        JuiceScreen/Capture/Image/CaptureEngine.swift \
        JuiceScreen/Capture/Image/FakeCaptureEngine.swift \
        JuiceScreen/Capture/Image/CaptureEngineLive.swift \
        JuiceScreenTests/FakeCaptureEngineTests.swift
git commit -m "feat(capture): captureFreeform end to end"
```

---

### Task 8: Menu item, hotkey, AppDelegate wiring

**Files:**
- Modify: `JuiceScreen/MenuBar/HotkeyService.swift:6-14`
- Modify: `JuiceScreen/Preferences/Preferences.swift:24-31, 54-61`
- Modify: `JuiceScreen/MenuBar/MenuBarMenuBuilder.swift:7-35, 45-60`
- Modify: `JuiceScreen/App/AppDelegate.swift:202-235, 238-250`
- Test: `JuiceScreenTests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: `CaptureType.freeform` and `CaptureEngine.captureFreeform()` (Task 7).
- Produces: `HotkeyAction.captureFreeform = 9`; `Preferences.captureFreeformHotkey: Hotkey`; `MenuBarActions.captureFreeform: () -> Void`.

- [ ] **Step 1: Write the failing test**

Append to `JuiceScreenTests/PreferencesStoreTests.swift`, inside the existing suite:

```swift
    @Test("captureFreeformHotkey defaults to Cmd+Shift+7 and round-trips")
    func freeformHotkeyDefaultAndRoundTrip() {
        let (store, _) = makeEphemeralStore()
        #expect(store.load().captureFreeformHotkey == Hotkey(keyCode: 26, modifiers: [.command, .shift]))

        var prefs = store.load()
        prefs.captureFreeformHotkey = Hotkey(keyCode: 26, modifiers: [.command, .option])
        store.save(prefs)
        #expect(store.load().captureFreeformHotkey == Hotkey(keyCode: 26, modifiers: [.command, .option]))
    }
```

`makeEphemeralStore()` is the existing private helper at the top of that suite; it builds a `PreferencesStore(defaults:)` over a UUID-named `UserDefaults` suite.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests/PreferencesStoreTests 2>&1 | tail -20`
Expected: build failure, `value of type 'Preferences' has no member 'captureFreeformHotkey'`.

- [ ] **Step 3: Add the preference**

In `Preferences.swift`, next to `captureScrollHotkey`:

```swift
    public var captureFreeformHotkey: Hotkey
```

In the `defaults` factory, next to `captureScrollHotkey:` (and extend the keycode comment above it with `26=7`):

```swift
            captureFreeformHotkey:   Hotkey(keyCode: 26, modifiers: [.command, .shift]),
```

Add the parameter to `Preferences.init` in the same position as the property.

Then three lines in `PreferencesStore.swift`, each next to its `captureScrollHotkey` sibling:

```swift
        static let captureFreeformHotkey = "captureFreeformHotkey"   // in enum Key, after line 18
```

```swift
            captureFreeformHotkey:   loadHotkey(Key.captureFreeformHotkey)   ?? d.captureFreeformHotkey,   // in load(), after line 65
```

```swift
        saveHotkey(prefs.captureFreeformHotkey,   key: Key.captureFreeformHotkey)   // in save(), after line 88
```

- [ ] **Step 4: Add the hotkey action**

In `HotkeyService.swift`, extend `HotkeyAction`:

```swift
    case captureFreeform   = 9
```

- [ ] **Step 5: Add the menu item**

In `MenuBarMenuBuilder.swift`, add to `MenuBarActions` (property, init parameter, and assignment — all three, in the same relative position as `captureRegion`):

```swift
    public var captureFreeform: () -> Void
```

and in `build`, directly after the `Capture Region` item:

```swift
        menu.addItem(item("Capture Freeform",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureFreeformHotkey),
                          action: actions.captureFreeform))
```

- [ ] **Step 6: Wire the AppDelegate**

In the `MenuBarActions(...)` construction, after the `captureRegion:` line:

```swift
            captureFreeform:   { [weak self] in self?.fireCapture(.freeform) },
```

After the `hotkeyService.register(prefs.captureRegionHotkey, …)` line:

```swift
        hotkeyService.register(prefs.captureFreeformHotkey, for: .captureFreeform) { actions.captureFreeform() }
```

In `fireCapture(_:)`, add to the switch:

```swift
                case .freeform:    record = try await engine.captureFreeform()
```

- [ ] **Step 7: Run the full suite**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add JuiceScreen/MenuBar/HotkeyService.swift \
        JuiceScreen/MenuBar/MenuBarMenuBuilder.swift \
        JuiceScreen/Preferences/Preferences.swift \
        JuiceScreen/App/AppDelegate.swift \
        JuiceScreenTests/PreferencesStoreTests.swift
git commit -m "feat(menu): Capture Freeform item and hotkey"
```

---

### Task 9: Editor checkerboard

**Testing note:** SwiftUI `Canvas` drawing is not unit-testable in this repo (same reason as `LayerRenderer`). The check is visual, in Step 3.

**Files:**
- Create: `JuiceScreen/Annotation/Canvas/CheckerboardBackground.swift`
- Modify: `JuiceScreen/Annotation/Editor/EditorView.swift:10-24`

**Interfaces:**
- Consumes: nothing.
- Produces: `CheckerboardBackground` (SwiftUI `View`, `squareSize: CGFloat = 8`).

- [ ] **Step 1: Write the view**

Create `JuiceScreen/Annotation/Canvas/CheckerboardBackground.swift`:

```swift
import SwiftUI

/// Editor-only backdrop that makes transparency visible.
///
/// Deliberately NOT part of `AnnotationCanvas`: that view is also what
/// `AnnotationRenderer` rasterises for export, and the pattern must never end
/// up in an exported file.
struct CheckerboardBackground: View {

    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 1.0)))
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            guard cols > 0, rows > 0 else { return }
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 1 {
                    let square = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    ctx.fill(Path(square), with: .color(Color(white: 0.86)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Put it under the canvas**

In `EditorView.swift`, make it the first child of the `ZStack`, above `AnnotationCanvas`:

```swift
            ZStack(alignment: .topLeading) {
                CheckerboardBackground()
                    .frame(width: canvasPointSize.width, height: canvasPointSize.height)
                AnnotationCanvas(baseImage: state.document.baseImage,
```

- [ ] **Step 3: Regenerate, build, verify visually**

```bash
xcodegen generate
scripts/build-release.sh && open build/JuiceScreen.app
```

Take a freeform capture. The editor must show the checkerboard through the transparent area. Then export as PNG (transparency preserved), as JPG (white, not black), and check the library grid thumbnail is white outside the shape, not black.

- [ ] **Step 4: Run the full suite**

Run: `xcodebuild test -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Canvas/CheckerboardBackground.swift JuiceScreen/Annotation/Editor/EditorView.swift
git commit -m "feat(editor): checkerboard backdrop for transparent captures"
```

---

## Release

Not part of the task sequence — do it once every task is green.

Bump `VERSION` and `project.yml`'s `MARKETING_VERSION` to `1.2.0` (a feature, not a patch), add the changelog section, then follow the signed local pipeline: `xcodegen generate` **after** the bump, archive with `CODE_SIGN_IDENTITY="Developer ID Application: Michael Kupermann (8K23FDC4TM)"` and `ENABLE_HARDENED_RUNTIME=YES`, export with the `developer-id` options plist, verify `CFBundleShortVersionString` in the built bundle before submitting, notarize app and DMG, staple both, EdDSA-sign the stapled DMG, update the appcast, tag, cancel the CI run, publish with the signed asset.
