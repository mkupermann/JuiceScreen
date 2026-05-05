# JuiceScreen — Annotation Editor Implementation Plan (Plan 3 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.3.0` — every successful capture from Plan 2 automatically opens a dedicated editor `NSWindow` containing the screenshot. The user can mark up the image with all 11 annotation tools (Select, Arrow, Double Arrow, Line, Rectangle, Ellipse, Pen, Highlighter, Text, Blur+Pixelate, Crop), undo/redo via ⌘Z/⌘⇧Z, and export the annotated result back to disk as PNG or JPG. PDF export is deferred to Plan 9.

**Architecture:** New `Annotation/` module with strict layering — pure value types (`Model/`), pure rendering helpers (`Canvas/`), pure undo (`Undo/`), pure export (`Export/`), and SwiftUI/AppKit on top (`Editor/`, `ToolUI/`). The editor never mutates the base capture image: edits live as a stack of typed `AnnotationLayer` value types over the original bitmap. Undo is implemented as snapshot-based: each user action pushes a copy of the document onto a stack. Export flattens layers via Core Graphics into a single image, applies destructive blur (so recipients can't reverse it), applies crop if set, and encodes via the existing `PNGEncoder` (Plan 2) plus a new JPG encoder.

**Tech Stack:** Swift 5.10+, SwiftUI `Canvas` (Metal-backed) for rendering, AppKit `NSWindow` per editor instance, `@Observable` for editor state, Core Image (`CIGaussianBlur`, `CIPixellate`) for destructive blur at export, `NSBitmapImageRep` for JPG encoding (PNG path reuses Plan 2's `PNGEncoder`), Swift Testing for unit tests.

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — section "Annotation editor".

**Plan 2 prerequisite:** v0.2.0 tagged. Captures save to `~/Pictures/JuiceScreen/<date>/` and `AppDelegate.fireCapture(_:)` returns a `CaptureRecord`. Plan 3 hooks in there: after a successful capture, the `EditorWindowManager` opens a window for that record.

**Scope deferred to later plans:**

- True vector PDF export (Plan 9)
- Advanced annotations: numbered step counter, callout speech bubbles, drop shadow on screenshot, magnifier loupe, image-on-image (these are CleanShot's "power" set per spec — explicitly out of v1 per design)
- Saving the annotation document as a JSON sidecar so users can re-edit later (the layer model is JSON-friendly and we'll expose this in a future plan; for v0.3.0 export is a one-way flatten)
- Color picker beyond the 7 preset swatches + custom NSColorPanel (the spec implicitly accepts a basic palette; full color management is a polish pass)

---

## File Structure

```
JuiceScreen/
├── Annotation/
│   ├── Model/
│   │   ├── ToolType.swift                    NEW — enum of the 11 tools
│   │   ├── ArrowProps.swift                  NEW — start/end/color/thickness/doubleHeaded
│   │   ├── LineProps.swift                   NEW — start/end/color/thickness
│   │   ├── ShapeProps.swift                  NEW — rect/color/thickness/filled (used by Rectangle and Ellipse)
│   │   ├── FreehandProps.swift               NEW — points/color/thickness/isHighlighter
│   │   ├── TextProps.swift                   NEW — origin/text/color/fontName/fontSize
│   │   ├── BlurProps.swift                   NEW — rect/style (gaussian/pixelate)/intensity
│   │   ├── AnnotationLayer.swift             NEW — enum cases per layer kind, with `id: UUID`
│   │   ├── AnnotationDocument.swift          NEW — baseImage + layers + canvasCrop
│   │   └── HitTest.swift                     NEW — pure point-in-layer math
│   ├── Undo/
│   │   └── UndoStack.swift                   NEW — snapshot-based push/undo/redo
│   ├── Editor/
│   │   ├── EditorState.swift                 NEW — @Observable: tool, selection, document, undo
│   │   ├── EditorView.swift                  NEW — SwiftUI: TopBar + ToolPalette + Canvas + Quick Actions
│   │   ├── EditorWindow.swift                NEW — NSWindow wrapping one EditorView for one CaptureRecord
│   │   ├── EditorWindowManager.swift         NEW — singleton tracking open windows; opens on capture
│   │   ├── KeyboardCommands.swift            NEW — ⌘Z/⌘⇧Z/⌘D/Delete/⌘W handler view modifier
│   │   └── QuickActions.swift                NEW — Copy/Save/Save As/Show in Finder/Discard
│   ├── Canvas/
│   │   ├── AnnotationCanvas.swift            NEW — SwiftUI Canvas drawing all layers
│   │   ├── LayerRenderer.swift               NEW — pure: GraphicsContext draw routines per layer
│   │   ├── SelectionHandlesView.swift        NEW — 8 handles + rotation handle for selected layer
│   │   └── CanvasGestures.swift              NEW — DragGesture state machine, dispatches per tool
│   ├── ToolUI/
│   │   ├── ToolPalette.swift                 NEW — left rail with 11 tool buttons
│   │   ├── ToolPaletteButton.swift           NEW — single button styling
│   │   ├── TopBar.swift                      NEW — context-sensitive control bar
│   │   ├── ColorSwatchPicker.swift           NEW — 7 presets + custom NSColorPanel
│   │   ├── ThicknessSlider.swift             NEW — 1–20pt slider
│   │   └── FontControls.swift                NEW — font name + size for text tool
│   └── Export/
│       ├── BlurEffect.swift                  NEW — CIGaussianBlur + CIPixellate destructive blur
│       ├── AnnotationRenderer.swift          NEW — flatten document → NSImage (applies crop, applies blur destructively)
│       ├── JPGEncoder.swift                  NEW — NSImage → JPG Data with quality
│       └── ExportService.swift               NEW — coordinates flatten + encode + write
├── App/
│   └── AppDelegate.swift                     MODIFY — call EditorWindowManager.show(for: record) after capture
└── Capture/Image/
    └── (no changes — Plan 2's CaptureRecord and Writer are already correct)

JuiceScreenTests/
├── AnnotationDocumentTests.swift             NEW
├── AnnotationLayerTests.swift                NEW
├── AnnotationPropsTests.swift                NEW (covers Arrow/Line/Shape/Freehand/Text/Blur)
├── HitTestTests.swift                        NEW
├── UndoStackTests.swift                      NEW
├── EditorStateTests.swift                    NEW
└── ExportServiceTests.swift                  NEW

VERSION                                       MODIFY — bump to 0.3.0 (Task 30)
project.yml                                   MODIFY — MARKETING_VERSION 0.3.0 (Task 30)
docs/superpowers/specs/2026-05-04-juicescreen-design.md  MODIFY — implementation status (Task 31)
```

---

## Task 1: `ToolType` enum + tests

**Files:**
- Create: `JuiceScreen/Annotation/Model/ToolType.swift`
- Create: `JuiceScreenTests/ToolTypeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import JuiceScreen

@Suite("ToolType")
struct ToolTypeTests {

    @Test("All 11 tools exist")
    func allCases() {
        #expect(ToolType.allCases.count == 11)
        let expected: Set<ToolType> = [
            .select, .arrow, .doubleArrow, .line,
            .rectangle, .ellipse, .pen, .highlighter,
            .text, .blur, .crop
        ]
        #expect(Set(ToolType.allCases) == expected)
    }

    @Test("SF Symbol name per tool")
    func sfSymbolNames() {
        #expect(ToolType.select.sfSymbol == "cursorarrow")
        #expect(ToolType.arrow.sfSymbol == "arrow.up.right")
        #expect(ToolType.doubleArrow.sfSymbol == "arrow.left.and.right")
        #expect(ToolType.line.sfSymbol == "line.diagonal")
        #expect(ToolType.rectangle.sfSymbol == "rectangle")
        #expect(ToolType.ellipse.sfSymbol == "circle")
        #expect(ToolType.pen.sfSymbol == "pencil.tip")
        #expect(ToolType.highlighter.sfSymbol == "highlighter")
        #expect(ToolType.text.sfSymbol == "textformat")
        #expect(ToolType.blur.sfSymbol == "drop")
        #expect(ToolType.crop.sfSymbol == "crop")
    }

    @Test("Display name per tool")
    func displayNames() {
        #expect(ToolType.select.displayName == "Select")
        #expect(ToolType.doubleArrow.displayName == "Double Arrow")
        #expect(ToolType.blur.displayName == "Blur")
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ToolTypeTests 2>&1 | tail -8
```

Expected: compile failure — `ToolType` undefined.

- [ ] **Step 3: Implement `ToolType.swift`**

```swift
import Foundation

public enum ToolType: String, CaseIterable, Sendable, Hashable {
    case select
    case arrow
    case doubleArrow
    case line
    case rectangle
    case ellipse
    case pen
    case highlighter
    case text
    case blur
    case crop

    public var displayName: String {
        switch self {
        case .select:      return "Select"
        case .arrow:       return "Arrow"
        case .doubleArrow: return "Double Arrow"
        case .line:        return "Line"
        case .rectangle:   return "Rectangle"
        case .ellipse:     return "Ellipse"
        case .pen:         return "Pen"
        case .highlighter: return "Highlighter"
        case .text:        return "Text"
        case .blur:        return "Blur"
        case .crop:        return "Crop"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .select:      return "cursorarrow"
        case .arrow:       return "arrow.up.right"
        case .doubleArrow: return "arrow.left.and.right"
        case .line:        return "line.diagonal"
        case .rectangle:   return "rectangle"
        case .ellipse:     return "circle"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text:        return "textformat"
        case .blur:        return "drop"
        case .crop:        return "crop"
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ToolTypeTests 2>&1 | tail -10
```

Expected: 3/3 cases pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Model/ToolType.swift JuiceScreenTests/ToolTypeTests.swift
git commit -m "feat(annotation): ToolType enum with display name + SF Symbol per tool"
```

---

## Task 2: Annotation prop value types (Arrow, Line, Shape, Freehand, Text, Blur) + tests

**Files:**
- Create: `JuiceScreen/Annotation/Model/ArrowProps.swift`
- Create: `JuiceScreen/Annotation/Model/LineProps.swift`
- Create: `JuiceScreen/Annotation/Model/ShapeProps.swift`
- Create: `JuiceScreen/Annotation/Model/FreehandProps.swift`
- Create: `JuiceScreen/Annotation/Model/TextProps.swift`
- Create: `JuiceScreen/Annotation/Model/BlurProps.swift`
- Create: `JuiceScreenTests/AnnotationPropsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("Annotation Props")
struct AnnotationPropsTests {

    // MARK: - Arrow

    @Test("ArrowProps stores all fields including doubleHeaded")
    func arrowProps() {
        let p = ArrowProps(
            start: CGPoint(x: 10, y: 20),
            end: CGPoint(x: 100, y: 200),
            color: .red,
            thickness: 3,
            doubleHeaded: true
        )
        #expect(p.start == CGPoint(x: 10, y: 20))
        #expect(p.end == CGPoint(x: 100, y: 200))
        #expect(p.thickness == 3)
        #expect(p.doubleHeaded == true)
    }

    @Test("ArrowProps bounding rect fits both endpoints")
    func arrowBounds() {
        let p = ArrowProps(start: CGPoint(x: 100, y: 50), end: CGPoint(x: 10, y: 200),
                           color: .red, thickness: 2, doubleHeaded: false)
        let b = p.boundingRect
        #expect(b.minX == 10)
        #expect(b.maxX == 100)
        #expect(b.minY == 50)
        #expect(b.maxY == 200)
    }

    // MARK: - Line

    @Test("LineProps stores all fields")
    func lineProps() {
        let p = LineProps(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10),
                          color: .blue, thickness: 1)
        #expect(p.start == .zero)
        #expect(p.end == CGPoint(x: 10, y: 10))
    }

    // MARK: - Shape (Rectangle / Ellipse)

    @Test("ShapeProps stores rect, color, thickness, filled flag")
    func shapeProps() {
        let p = ShapeProps(rect: CGRect(x: 5, y: 5, width: 20, height: 30),
                           color: .green, thickness: 2, filled: false)
        #expect(p.rect.width == 20)
        #expect(p.filled == false)
    }

    // MARK: - Freehand

    @Test("FreehandProps stores point list and highlighter flag")
    func freehandProps() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 8)]
        let p = FreehandProps(points: pts, color: .yellow, thickness: 6, isHighlighter: true)
        #expect(p.points.count == 3)
        #expect(p.isHighlighter == true)
    }

    @Test("FreehandProps bounding rect contains all points")
    func freehandBounds() {
        let pts = [CGPoint(x: 50, y: 10), CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 50)]
        let p = FreehandProps(points: pts, color: .red, thickness: 2, isHighlighter: false)
        let b = p.boundingRect
        #expect(b.minX == 0)
        #expect(b.maxX == 200)
        #expect(b.minY == 10)
        #expect(b.maxY == 100)
    }

    @Test("FreehandProps bounding rect for empty points is zero rect")
    func freehandEmptyBounds() {
        let p = FreehandProps(points: [], color: .red, thickness: 2, isHighlighter: false)
        #expect(p.boundingRect == .zero)
    }

    // MARK: - Text

    @Test("TextProps stores origin, text, font fields")
    func textProps() {
        let p = TextProps(origin: CGPoint(x: 50, y: 60), text: "hello",
                          color: .black, fontName: "Helvetica", fontSize: 14)
        #expect(p.text == "hello")
        #expect(p.fontSize == 14)
    }

    // MARK: - Blur

    @Test("BlurProps stores rect, style and intensity")
    func blurProps() {
        let p = BlurProps(rect: CGRect(x: 0, y: 0, width: 50, height: 30),
                          style: .pixelate, intensity: 12)
        #expect(p.style == .pixelate)
        #expect(p.intensity == 12)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/AnnotationPropsTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement the six prop files**

`JuiceScreen/Annotation/Model/ArrowProps.swift`:

```swift
import AppKit

public struct ArrowProps: Equatable, Hashable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var color: NSColor
    public var thickness: CGFloat
    public var doubleHeaded: Bool

    public init(start: CGPoint, end: CGPoint, color: NSColor, thickness: CGFloat, doubleHeaded: Bool) {
        self.start = start
        self.end = end
        self.color = color
        self.thickness = thickness
        self.doubleHeaded = doubleHeaded
    }

    public var boundingRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
```

`JuiceScreen/Annotation/Model/LineProps.swift`:

```swift
import AppKit

public struct LineProps: Equatable, Hashable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var color: NSColor
    public var thickness: CGFloat

    public init(start: CGPoint, end: CGPoint, color: NSColor, thickness: CGFloat) {
        self.start = start
        self.end = end
        self.color = color
        self.thickness = thickness
    }

    public var boundingRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
```

`JuiceScreen/Annotation/Model/ShapeProps.swift`:

```swift
import AppKit

/// Shared by Rectangle and Ellipse layers. Differentiated by which `AnnotationLayer` case wraps it.
public struct ShapeProps: Equatable, Hashable, Sendable {
    public var rect: CGRect
    public var color: NSColor
    public var thickness: CGFloat
    public var filled: Bool

    public init(rect: CGRect, color: NSColor, thickness: CGFloat, filled: Bool) {
        self.rect = rect
        self.color = color
        self.thickness = thickness
        self.filled = filled
    }

    public var boundingRect: CGRect { rect }
}
```

`JuiceScreen/Annotation/Model/FreehandProps.swift`:

```swift
import AppKit

public struct FreehandProps: Equatable, Hashable, Sendable {
    public var points: [CGPoint]
    public var color: NSColor
    public var thickness: CGFloat
    public var isHighlighter: Bool

    public init(points: [CGPoint], color: NSColor, thickness: CGFloat, isHighlighter: Bool) {
        self.points = points
        self.color = color
        self.thickness = thickness
        self.isHighlighter = isHighlighter
    }

    public var boundingRect: CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`JuiceScreen/Annotation/Model/TextProps.swift`:

```swift
import AppKit

public struct TextProps: Equatable, Hashable, Sendable {
    public var origin: CGPoint
    public var text: String
    public var color: NSColor
    public var fontName: String
    public var fontSize: CGFloat

    public init(origin: CGPoint, text: String, color: NSColor, fontName: String, fontSize: CGFloat) {
        self.origin = origin
        self.text = text
        self.color = color
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public func boundingRect() -> CGRect {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        return CGRect(origin: origin, size: size)
    }
}
```

`JuiceScreen/Annotation/Model/BlurProps.swift`:

```swift
import AppKit

public struct BlurProps: Equatable, Hashable, Sendable {

    public enum Style: String, Sendable, CaseIterable {
        case gaussian
        case pixelate
    }

    public var rect: CGRect
    public var style: Style
    public var intensity: CGFloat   // gaussian: blur radius; pixelate: cell size

    public init(rect: CGRect, style: Style, intensity: CGFloat) {
        self.rect = rect
        self.style = style
        self.intensity = intensity
    }

    public var boundingRect: CGRect { rect }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/AnnotationPropsTests 2>&1 | tail -10
```

Expected: 9/9 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Model/{ArrowProps,LineProps,ShapeProps,FreehandProps,TextProps,BlurProps}.swift JuiceScreenTests/AnnotationPropsTests.swift
git commit -m "feat(annotation): six annotation prop value types + tests"
```

---

## Task 3: `AnnotationLayer` enum + tests

**Files:**
- Create: `JuiceScreen/Annotation/Model/AnnotationLayer.swift`
- Create: `JuiceScreenTests/AnnotationLayerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("AnnotationLayer")
struct AnnotationLayerTests {

    @Test("Each layer carries a UUID")
    func layerHasId() {
        let a = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        let b = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        #expect(a.id != b.id)
    }

    @Test("Bounding rect dispatches per case")
    func bounds() {
        let line = AnnotationLayer.line(LineProps(start: .init(x: 5, y: 5), end: .init(x: 10, y: 20), color: .red, thickness: 2))
        #expect(line.boundingRect == CGRect(x: 5, y: 5, width: 5, height: 15))

        let rect = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 1, y: 2, width: 30, height: 40), color: .red, thickness: 2, filled: false))
        #expect(rect.boundingRect == CGRect(x: 1, y: 2, width: 30, height: 40))

        let blur = AnnotationLayer.blur(BlurProps(rect: CGRect(x: 0, y: 0, width: 50, height: 50), style: .gaussian, intensity: 8))
        #expect(blur.boundingRect == CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    @Test("Tool type per layer")
    func toolType() {
        let line = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 1))
        #expect(line.toolType == .line)

        let arrow = AnnotationLayer.arrow(ArrowProps(start: .zero, end: .zero, color: .red, thickness: 1, doubleHeaded: false))
        #expect(arrow.toolType == .arrow)

        let darrow = AnnotationLayer.arrow(ArrowProps(start: .zero, end: .zero, color: .red, thickness: 1, doubleHeaded: true))
        #expect(darrow.toolType == .doubleArrow)

        let rect = AnnotationLayer.rectangle(ShapeProps(rect: .zero, color: .red, thickness: 1, filled: false))
        #expect(rect.toolType == .rectangle)

        let ellipse = AnnotationLayer.ellipse(ShapeProps(rect: .zero, color: .red, thickness: 1, filled: false))
        #expect(ellipse.toolType == .ellipse)

        let pen = AnnotationLayer.freehand(FreehandProps(points: [], color: .red, thickness: 1, isHighlighter: false))
        #expect(pen.toolType == .pen)

        let high = AnnotationLayer.freehand(FreehandProps(points: [], color: .yellow, thickness: 8, isHighlighter: true))
        #expect(high.toolType == .highlighter)

        let text = AnnotationLayer.text(TextProps(origin: .zero, text: "x", color: .black, fontName: "Helvetica", fontSize: 12))
        #expect(text.toolType == .text)

        let blur = AnnotationLayer.blur(BlurProps(rect: .zero, style: .gaussian, intensity: 8))
        #expect(blur.toolType == .blur)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/AnnotationLayerTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `AnnotationLayer.swift`**

```swift
import Foundation

public enum AnnotationLayer: Equatable, Hashable, Sendable, Identifiable {

    case arrow(ArrowProps, id: UUID = UUID())
    case line(LineProps, id: UUID = UUID())
    case rectangle(ShapeProps, id: UUID = UUID())
    case ellipse(ShapeProps, id: UUID = UUID())
    case freehand(FreehandProps, id: UUID = UUID())
    case text(TextProps, id: UUID = UUID())
    case blur(BlurProps, id: UUID = UUID())

    public var id: UUID {
        switch self {
        case .arrow(_, let id),
             .line(_, let id),
             .rectangle(_, let id),
             .ellipse(_, let id),
             .freehand(_, let id),
             .text(_, let id),
             .blur(_, let id):
            return id
        }
    }

    public var boundingRect: CGRect {
        switch self {
        case .arrow(let p, _):     return p.boundingRect
        case .line(let p, _):      return p.boundingRect
        case .rectangle(let p, _): return p.boundingRect
        case .ellipse(let p, _):   return p.boundingRect
        case .freehand(let p, _):  return p.boundingRect
        case .text(let p, _):      return p.boundingRect()
        case .blur(let p, _):      return p.boundingRect
        }
    }

    public var toolType: ToolType {
        switch self {
        case .arrow(let p, _):     return p.doubleHeaded ? .doubleArrow : .arrow
        case .line:                return .line
        case .rectangle:           return .rectangle
        case .ellipse:             return .ellipse
        case .freehand(let p, _):  return p.isHighlighter ? .highlighter : .pen
        case .text:                return .text
        case .blur:                return .blur
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/AnnotationLayerTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Model/AnnotationLayer.swift JuiceScreenTests/AnnotationLayerTests.swift
git commit -m "feat(annotation): AnnotationLayer enum dispatching to per-tool props"
```

---

## Task 4: `AnnotationDocument` + tests

**Files:**
- Create: `JuiceScreen/Annotation/Model/AnnotationDocument.swift`
- Create: `JuiceScreenTests/AnnotationDocumentTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("AnnotationDocument")
struct AnnotationDocumentTests {

    private func makeImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return img
    }

    @Test("Initial document has no layers and no crop")
    func initial() {
        let doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        #expect(doc.layers.isEmpty)
        #expect(doc.canvasCrop == nil)
    }

    @Test("Append layer mutates layers array")
    func appendLayer() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        doc.append(layer)
        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].id == layer.id)
    }

    @Test("Replace layer by id keeps order and replaces in place")
    func replaceLayer() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        let l1 = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        let l2 = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 20, y: 20), color: .blue, thickness: 4))
        doc.append(l1)
        doc.append(l2)

        let updated = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 99, y: 99), color: .green, thickness: 8), id: l1.id)
        doc.replace(updated)
        #expect(doc.layers.count == 2)
        #expect(doc.layers[0].id == l1.id)
        if case .line(let p, _) = doc.layers[0] {
            #expect(p.color == .green)
        } else {
            Issue.record("Expected line at index 0")
        }
    }

    @Test("Remove layer by id")
    func removeLayer() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        let l1 = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 1))
        let l2 = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .blue, thickness: 1))
        doc.append(l1)
        doc.append(l2)
        doc.remove(id: l1.id)
        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].id == l2.id)
    }

    @Test("Crop is settable and clearable")
    func crop() {
        var doc = AnnotationDocument(baseImage: makeImage(width: 100, height: 100))
        doc.canvasCrop = CGRect(x: 10, y: 10, width: 50, height: 50)
        #expect(doc.canvasCrop == CGRect(x: 10, y: 10, width: 50, height: 50))
        doc.canvasCrop = nil
        #expect(doc.canvasCrop == nil)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/AnnotationDocumentTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `AnnotationDocument.swift`**

```swift
import AppKit

/// In-memory representation of one capture in the editor: the original bitmap (never mutated)
/// plus an ordered stack of annotation layers and an optional crop applied at export time.
public struct AnnotationDocument: Sendable {

    public let baseImage: NSImage
    public private(set) var layers: [AnnotationLayer]
    public var canvasCrop: CGRect?

    public init(baseImage: NSImage, layers: [AnnotationLayer] = [], canvasCrop: CGRect? = nil) {
        self.baseImage = baseImage
        self.layers = layers
        self.canvasCrop = canvasCrop
    }

    public mutating func append(_ layer: AnnotationLayer) {
        layers.append(layer)
    }

    public mutating func replace(_ layer: AnnotationLayer) {
        guard let idx = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        layers[idx] = layer
    }

    public mutating func remove(id: UUID) {
        layers.removeAll { $0.id == id }
    }

    public func layer(id: UUID) -> AnnotationLayer? {
        layers.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/AnnotationDocumentTests 2>&1 | tail -10
```

Expected: 5/5 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Model/AnnotationDocument.swift JuiceScreenTests/AnnotationDocumentTests.swift
git commit -m "feat(annotation): AnnotationDocument value type (baseImage + layers + crop)"
```

---

## Task 5: `HitTest` helper + tests

**Files:**
- Create: `JuiceScreen/Annotation/Model/HitTest.swift`
- Create: `JuiceScreenTests/HitTestTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("HitTest")
struct HitTestTests {

    @Test("Rectangle: point inside hits, outside does not")
    func rect() {
        let layer = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 10, y: 10, width: 50, height: 50), color: .red, thickness: 2, filled: false))
        #expect(HitTest.contains(layer, point: CGPoint(x: 30, y: 30)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 5, y: 5)))
    }

    @Test("Ellipse: hit uses inscribed ellipse, not the bounding rect")
    func ellipse() {
        // 100x100 ellipse from (0,0). Corner (5,5) is inside the bounding rect but outside the ellipse.
        let layer = AnnotationLayer.ellipse(ShapeProps(rect: CGRect(x: 0, y: 0, width: 100, height: 100), color: .red, thickness: 2, filled: false))
        #expect(HitTest.contains(layer, point: CGPoint(x: 50, y: 50)))   // center, inside
        #expect(!HitTest.contains(layer, point: CGPoint(x: 5, y: 5)))    // corner, outside
    }

    @Test("Line: point near segment hits, far from segment misses")
    func line() {
        // Horizontal line from (0,50) to (100,50), thickness 4, hit-tolerance = thickness/2 + 4
        let layer = AnnotationLayer.line(LineProps(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 100, y: 50), color: .red, thickness: 4))
        #expect(HitTest.contains(layer, point: CGPoint(x: 50, y: 51)))   // very close
        #expect(!HitTest.contains(layer, point: CGPoint(x: 50, y: 80)))  // 30pt away
    }

    @Test("Arrow: same hit logic as line")
    func arrow() {
        let layer = AnnotationLayer.arrow(ArrowProps(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), color: .red, thickness: 2, doubleHeaded: false))
        #expect(HitTest.contains(layer, point: CGPoint(x: 50, y: 1)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 50, y: 50)))
    }

    @Test("Text: hits inside the text bounding rect")
    func text() {
        let layer = AnnotationLayer.text(TextProps(origin: CGPoint(x: 100, y: 100), text: "Hello world",
                                                    color: .black, fontName: "Helvetica", fontSize: 24))
        #expect(HitTest.contains(layer, point: CGPoint(x: 105, y: 105)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 5, y: 5)))
    }

    @Test("Blur: hits inside the rect")
    func blur() {
        let layer = AnnotationLayer.blur(BlurProps(rect: CGRect(x: 50, y: 50, width: 30, height: 30),
                                                    style: .gaussian, intensity: 8))
        #expect(HitTest.contains(layer, point: CGPoint(x: 60, y: 60)))
        #expect(!HitTest.contains(layer, point: CGPoint(x: 10, y: 10)))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/HitTestTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `HitTest.swift`**

```swift
import AppKit

/// Pure point-in-layer hit testing. Used by the Select tool to figure out which
/// layer the user clicked on.
public enum HitTest {

    /// Returns true if `point` is inside (or close to, for stroke-based layers) the layer.
    public static func contains(_ layer: AnnotationLayer, point: CGPoint) -> Bool {
        switch layer {
        case .rectangle(let p, _):
            return p.rect.contains(point)

        case .ellipse(let p, _):
            return ellipseContains(rect: p.rect, point: point)

        case .blur(let p, _):
            return p.rect.contains(point)

        case .text(let p, _):
            return p.boundingRect().contains(point)

        case .arrow(let p, _):
            return distanceFromSegment(point: point, a: p.start, b: p.end) <= max(p.thickness / 2 + 4, 6)

        case .line(let p, _):
            return distanceFromSegment(point: point, a: p.start, b: p.end) <= max(p.thickness / 2 + 4, 6)

        case .freehand(let p, _):
            for i in 1..<p.points.count {
                if distanceFromSegment(point: point, a: p.points[i - 1], b: p.points[i]) <= max(p.thickness / 2 + 4, 6) {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Geometry helpers

    private static func ellipseContains(rect: CGRect, point: CGPoint) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        let nx = (point.x - cx) / rx
        let ny = (point.y - cy) / ry
        return (nx * nx + ny * ny) <= 1
    }

    /// Shortest distance from `point` to segment `a→b`.
    private static func distanceFromSegment(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 {
            let dxp = point.x - a.x, dyp = point.y - a.y
            return (dxp * dxp + dyp * dyp).squareRoot()
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let pdx = point.x - projX, pdy = point.y - projY
        return (pdx * pdx + pdy * pdy).squareRoot()
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/HitTestTests 2>&1 | tail -10
```

Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Model/HitTest.swift JuiceScreenTests/HitTestTests.swift
git commit -m "feat(annotation): HitTest with shape-aware contains() (ellipse vs rect, segment distance)"
```

---

## Task 6: `UndoStack` + tests

**Files:**
- Create: `JuiceScreen/Annotation/Undo/UndoStack.swift`
- Create: `JuiceScreenTests/UndoStackTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import JuiceScreen

@Suite("UndoStack")
struct UndoStackTests {

    @Test("Initial state: cannot undo or redo")
    func initial() {
        let stack = UndoStack<Int>(initial: 0)
        #expect(stack.current == 0)
        #expect(stack.canUndo == false)
        #expect(stack.canRedo == false)
    }

    @Test("Push moves current forward and enables undo")
    func pushEnablesUndo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        #expect(stack.current == 1)
        #expect(stack.canUndo == true)
        #expect(stack.canRedo == false)
    }

    @Test("Undo restores previous state and enables redo")
    func undoEnablesRedo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        stack.undo()
        #expect(stack.current == 0)
        #expect(stack.canUndo == false)
        #expect(stack.canRedo == true)
    }

    @Test("Redo restores re-done state")
    func redo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        stack.undo()
        stack.redo()
        #expect(stack.current == 1)
        #expect(stack.canUndo == true)
        #expect(stack.canRedo == false)
    }

    @Test("Push after undo discards forward history")
    func pushDiscardsRedo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        stack.push(2)
        stack.undo()
        #expect(stack.current == 1)
        #expect(stack.canRedo == true)

        stack.push(99)
        #expect(stack.current == 99)
        #expect(stack.canRedo == false)
    }

    @Test("Many pushes work without errors")
    func manyPushes() {
        var stack = UndoStack<Int>(initial: 0)
        for i in 1...100 { stack.push(i) }
        #expect(stack.current == 100)
        for _ in 1...100 { stack.undo() }
        #expect(stack.current == 0)
        #expect(stack.canUndo == false)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/UndoStackTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `UndoStack.swift`**

```swift
/// Generic snapshot-based undo stack. Each `push` records the new value so a later
/// `undo` can restore the previous one. Pushing after an `undo` discards the redo tail.
///
/// Used by the editor with `T = AnnotationDocument`.
public struct UndoStack<T> {

    private var past: [T] = []
    private var future: [T] = []
    public private(set) var current: T

    public init(initial: T) {
        self.current = initial
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public mutating func push(_ next: T) {
        past.append(current)
        current = next
        future.removeAll()
    }

    public mutating func undo() {
        guard let prev = past.popLast() else { return }
        future.append(current)
        current = prev
    }

    public mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(current)
        current = next
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/UndoStackTests 2>&1 | tail -10
```

Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Undo/UndoStack.swift JuiceScreenTests/UndoStackTests.swift
git commit -m "feat(annotation): UndoStack snapshot-based undo/redo"
```

---

## Task 7: `EditorState` (@Observable) + tests

**Files:**
- Create: `JuiceScreen/Annotation/Editor/EditorState.swift`
- Create: `JuiceScreenTests/EditorStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("EditorState")
@MainActor
struct EditorStateTests {

    private func makeImage() -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.addRepresentation(rep)
        return img
    }

    private func makeRecord(at url: URL = URL(fileURLWithPath: "/tmp/x.png")) -> CaptureRecord {
        CaptureRecord(fileURL: url, captureType: .region, capturedAt: Date(),
                      pixelWidth: 100, pixelHeight: 100, sourceApp: nil)
    }

    @Test("Initial state: select tool, no selection, empty document")
    func initial() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        #expect(state.currentTool == .select)
        #expect(state.selectedLayerID == nil)
        #expect(state.document.layers.isEmpty)
    }

    @Test("addLayer pushes onto document and undo stack")
    func addLayer() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        state.add(layer)
        #expect(state.document.layers.count == 1)
        #expect(state.canUndo == true)
    }

    @Test("Undo pops the last add")
    func undo() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .init(x: 10, y: 10), color: .red, thickness: 2))
        state.add(layer)
        state.undo()
        #expect(state.document.layers.isEmpty)
        #expect(state.canUndo == false)
        #expect(state.canRedo == true)
    }

    @Test("Setting selectedLayerID updates state but does not affect undo stack")
    func selectionDoesNotPushUndo() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 2))
        state.add(layer)
        let undoBefore = state.canUndo
        state.selectedLayerID = layer.id
        #expect(state.selectedLayerID == layer.id)
        #expect(state.canUndo == undoBefore)
    }

    @Test("Delete selected layer mutates document and pushes undo")
    func deleteSelected() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.line(LineProps(start: .zero, end: .zero, color: .red, thickness: 2))
        state.add(layer)
        state.selectedLayerID = layer.id
        state.deleteSelected()
        #expect(state.document.layers.isEmpty)
        #expect(state.selectedLayerID == nil)
    }

    @Test("Duplicate selected adds a copy with a new id")
    func duplicateSelected() {
        let state = EditorState(captureRecord: makeRecord(), baseImage: makeImage())
        let layer = AnnotationLayer.rectangle(ShapeProps(rect: CGRect(x: 0, y: 0, width: 10, height: 10), color: .red, thickness: 2, filled: false))
        state.add(layer)
        state.selectedLayerID = layer.id
        state.duplicateSelected()
        #expect(state.document.layers.count == 2)
        #expect(state.document.layers[0].id != state.document.layers[1].id)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/EditorStateTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `EditorState.swift`**

```swift
import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class EditorState {

    public let captureRecord: CaptureRecord

    public var currentTool: ToolType = .select
    public var currentColor: NSColor = .systemRed
    public var currentThickness: CGFloat = 3
    public var currentFontName: String = "Helvetica"
    public var currentFontSize: CGFloat = 18
    public var currentFilled: Bool = false
    public var currentBlurStyle: BlurProps.Style = .gaussian
    public var currentBlurIntensity: CGFloat = 12

    public var selectedLayerID: UUID? = nil
    public var isEdited: Bool = false   // tracks whether anything has been added since open

    private var undoStack: UndoStack<AnnotationDocument>

    public init(captureRecord: CaptureRecord, baseImage: NSImage) {
        self.captureRecord = captureRecord
        self.undoStack = UndoStack(initial: AnnotationDocument(baseImage: baseImage))
    }

    public var document: AnnotationDocument { undoStack.current }
    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }

    // MARK: - Mutations (each pushes onto the undo stack)

    public func add(_ layer: AnnotationLayer) {
        var next = undoStack.current
        next.append(layer)
        undoStack.push(next)
        isEdited = true
    }

    public func replace(_ layer: AnnotationLayer) {
        var next = undoStack.current
        next.replace(layer)
        undoStack.push(next)
        isEdited = true
    }

    public func deleteSelected() {
        guard let id = selectedLayerID else { return }
        var next = undoStack.current
        next.remove(id: id)
        undoStack.push(next)
        selectedLayerID = nil
        isEdited = true
    }

    public func duplicateSelected() {
        guard let id = selectedLayerID,
              let layer = undoStack.current.layer(id: id) else { return }
        let copy = duplicate(layer)
        var next = undoStack.current
        next.append(copy)
        undoStack.push(next)
        selectedLayerID = copy.id
        isEdited = true
    }

    public func setCrop(_ rect: CGRect?) {
        var next = undoStack.current
        next.canvasCrop = rect
        undoStack.push(next)
        isEdited = true
    }

    public func undo() {
        undoStack.undo()
    }

    public func redo() {
        undoStack.redo()
    }

    // MARK: - Helpers

    private func duplicate(_ layer: AnnotationLayer) -> AnnotationLayer {
        let offset = CGSize(width: 12, height: 12)
        switch layer {
        case .arrow(let p, _):
            return .arrow(ArrowProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                     color: p.color, thickness: p.thickness, doubleHeaded: p.doubleHeaded))
        case .line(let p, _):
            return .line(LineProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                   color: p.color, thickness: p.thickness))
        case .rectangle(let p, _):
            return .rectangle(ShapeProps(rect: p.rect.offsetBy(offset), color: p.color, thickness: p.thickness, filled: p.filled))
        case .ellipse(let p, _):
            return .ellipse(ShapeProps(rect: p.rect.offsetBy(offset), color: p.color, thickness: p.thickness, filled: p.filled))
        case .freehand(let p, _):
            return .freehand(FreehandProps(points: p.points.map { $0.offsetBy(offset) },
                                           color: p.color, thickness: p.thickness, isHighlighter: p.isHighlighter))
        case .text(let p, _):
            return .text(TextProps(origin: p.origin.offsetBy(offset), text: p.text,
                                   color: p.color, fontName: p.fontName, fontSize: p.fontSize))
        case .blur(let p, _):
            return .blur(BlurProps(rect: p.rect.offsetBy(offset), style: p.style, intensity: p.intensity))
        }
    }
}

// MARK: - Geometry helpers (shared with CanvasGestures.translate in Task 10)

extension CGPoint {
    func offsetBy(_ s: CGSize) -> CGPoint { CGPoint(x: x + s.width, y: y + s.height) }
}

extension CGRect {
    func offsetBy(_ s: CGSize) -> CGRect { offsetBy(dx: s.width, dy: s.height) }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/EditorStateTests 2>&1 | tail -10
```

Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Editor/EditorState.swift JuiceScreenTests/EditorStateTests.swift
git commit -m "feat(annotation): EditorState observable model with undo + selection + tool config"
```

---

## Task 8: `LayerRenderer` (pure draw routines)

**Files:**
- Create: `JuiceScreen/Annotation/Canvas/LayerRenderer.swift`

(No automated tests — visual rendering. Smoke-tested by Task 9 + manual verification.)

- [ ] **Step 1: Implement `LayerRenderer.swift`**

```swift
import AppKit
import SwiftUI

/// Pure draw routines: given a SwiftUI `GraphicsContext`, render a single annotation layer.
/// No state, no view tree — used by `AnnotationCanvas` (live editor) and
/// `AnnotationRenderer` (export flatten via a pixel-backed CGContext).
public enum LayerRenderer {

    public static func draw(_ layer: AnnotationLayer, in ctx: inout GraphicsContext) {
        switch layer {
        case .arrow(let p, _):
            drawArrow(p, in: &ctx)
        case .line(let p, _):
            drawLine(p, in: &ctx)
        case .rectangle(let p, _):
            drawRectangle(p, in: &ctx)
        case .ellipse(let p, _):
            drawEllipse(p, in: &ctx)
        case .freehand(let p, _):
            drawFreehand(p, in: &ctx)
        case .text(let p, _):
            drawText(p, in: &ctx)
        case .blur:
            // Blur is destructive at export. In the live editor it shows as a
            // semi-transparent overlay so the user knows where it will be applied.
            drawBlurPlaceholder(layer, in: &ctx)
        }
    }

    // MARK: - Per-layer

    private static func drawLine(_ p: LineProps, in ctx: inout GraphicsContext) {
        var path = Path()
        path.move(to: p.start)
        path.addLine(to: p.end)
        ctx.stroke(path, with: .color(Color(p.color)), style: StrokeStyle(lineWidth: p.thickness, lineCap: .round))
    }

    private static func drawArrow(_ p: ArrowProps, in ctx: inout GraphicsContext) {
        // Shaft
        var shaft = Path()
        shaft.move(to: p.start)
        shaft.addLine(to: p.end)
        ctx.stroke(shaft, with: .color(Color(p.color)), style: StrokeStyle(lineWidth: p.thickness, lineCap: .round))

        // Head at end
        ctx.fill(arrowHeadPath(at: p.end, from: p.start, length: max(p.thickness * 4, 12)),
                 with: .color(Color(p.color)))
        if p.doubleHeaded {
            ctx.fill(arrowHeadPath(at: p.start, from: p.end, length: max(p.thickness * 4, 12)),
                     with: .color(Color(p.color)))
        }
    }

    private static func arrowHeadPath(at tip: CGPoint, from origin: CGPoint, length: CGFloat) -> Path {
        let dx = tip.x - origin.x, dy = tip.y - origin.y
        let angle = atan2(dy, dx)
        let h = length
        let w = length * 0.7
        let baseX = tip.x - cos(angle) * h
        let baseY = tip.y - sin(angle) * h
        let leftX = baseX + cos(angle + .pi / 2) * (w / 2)
        let leftY = baseY + sin(angle + .pi / 2) * (w / 2)
        let rightX = baseX - cos(angle + .pi / 2) * (w / 2)
        let rightY = baseY - sin(angle + .pi / 2) * (w / 2)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: leftX, y: leftY))
        path.addLine(to: CGPoint(x: rightX, y: rightY))
        path.closeSubpath()
        return path
    }

    private static func drawRectangle(_ p: ShapeProps, in ctx: inout GraphicsContext) {
        let path = Path(p.rect)
        if p.filled {
            ctx.fill(path, with: .color(Color(p.color)))
        } else {
            ctx.stroke(path, with: .color(Color(p.color)), lineWidth: p.thickness)
        }
    }

    private static func drawEllipse(_ p: ShapeProps, in ctx: inout GraphicsContext) {
        let path = Path(ellipseIn: p.rect)
        if p.filled {
            ctx.fill(path, with: .color(Color(p.color)))
        } else {
            ctx.stroke(path, with: .color(Color(p.color)), lineWidth: p.thickness)
        }
    }

    private static func drawFreehand(_ p: FreehandProps, in ctx: inout GraphicsContext) {
        guard p.points.count >= 2 else { return }
        var path = Path()
        path.move(to: p.points[0])
        for pt in p.points.dropFirst() { path.addLine(to: pt) }
        var color = Color(p.color)
        if p.isHighlighter {
            color = color.opacity(0.45)
        }
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: p.thickness, lineCap: .round, lineJoin: .round))
    }

    private static func drawText(_ p: TextProps, in ctx: inout GraphicsContext) {
        let font = NSFont(name: p.fontName, size: p.fontSize) ?? NSFont.systemFont(ofSize: p.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: p.color
        ]
        let attributed = NSAttributedString(string: p.text, attributes: attrs)
        let resolved = ctx.resolve(Text(AttributedString(attributed)))
        ctx.draw(resolved, at: p.origin, anchor: .topLeading)
    }

    private static func drawBlurPlaceholder(_ layer: AnnotationLayer, in ctx: inout GraphicsContext) {
        let rect = layer.boundingRect
        // semi-transparent gray fill + dashed stroke to indicate "blur applied here"
        ctx.fill(Path(rect), with: .color(Color.gray.opacity(0.35)))
        var dashed = StrokeStyle(lineWidth: 1)
        dashed.dash = [4, 3]
        ctx.stroke(Path(rect), with: .color(Color.gray.opacity(0.85)), style: dashed)
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
git add JuiceScreen/Annotation/Canvas/LayerRenderer.swift
git commit -m "feat(annotation): LayerRenderer pure draw routines for all 7 layer kinds"
```

---

## Task 9: `AnnotationCanvas` — base image + layers

**Files:**
- Create: `JuiceScreen/Annotation/Canvas/AnnotationCanvas.swift`

(No automated tests — visual.)

- [ ] **Step 1: Implement `AnnotationCanvas.swift`**

```swift
import AppKit
import SwiftUI

/// Renders the base capture bitmap underneath, then draws every annotation layer
/// in order via `LayerRenderer`. Pure presentation — no gestures (those live in
/// `CanvasGestures` in Task 10).
struct AnnotationCanvas: View {

    let baseImage: NSImage
    let layers: [AnnotationLayer]
    let canvasSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            // Base image
            if let cg = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(Image(cg, scale: 1, label: Text("base")), in: CGRect(origin: .zero, size: size))
            }
            // Layers (bottom-to-top)
            for layer in layers {
                var ctxCopy = ctx
                LayerRenderer.draw(layer, in: &ctxCopy)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
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
git add JuiceScreen/Annotation/Canvas/AnnotationCanvas.swift
git commit -m "feat(annotation): AnnotationCanvas (base image + layers via LayerRenderer)"
```

---

## Task 10: `CanvasGestures` — drag dispatch + create gestures for line/rect/freehand families

**Files:**
- Create: `JuiceScreen/Annotation/Canvas/CanvasGestures.swift`

(No automated tests — gestures need a SwiftUI runtime. Smoke-tested via running the app.)

- [ ] **Step 1: Implement `CanvasGestures.swift`**

```swift
import AppKit
import SwiftUI

/// Drag handlers per tool. Dispatches based on `state.currentTool`.
/// Held by `EditorView` and overlaid on top of `AnnotationCanvas`.
struct CanvasGestures: View {

    @Bindable var state: EditorState
    @State private var dragStart: CGPoint? = nil
    @State private var freehandPoints: [CGPoint] = []
    @State private var inProgressLayerID: UUID? = nil
    @State private var moveOriginalLayer: AnnotationLayer? = nil  // snapshot of selected layer at drag start

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in handleChanged(value) }
                    .onEnded { value in handleEnded(value) }
            )
            .onTapGesture { location in handleTap(at: location) }
    }

    // MARK: - Tap (Select + Text)

    private func handleTap(at location: CGPoint) {
        switch state.currentTool {
        case .select:
            // Hit-test top-down (last drawn = topmost)
            for layer in state.document.layers.reversed() {
                if HitTest.contains(layer, point: location) {
                    state.selectedLayerID = layer.id
                    return
                }
            }
            state.selectedLayerID = nil

        case .text:
            // Drop a text layer with placeholder text — user can edit via inspector or by typing
            let layer = AnnotationLayer.text(TextProps(
                origin: location,
                text: "Text",
                color: state.currentColor,
                fontName: state.currentFontName,
                fontSize: state.currentFontSize
            ))
            state.add(layer)
            state.selectedLayerID = layer.id

        default:
            break
        }
    }

    // MARK: - Drag dispatch

    private func handleChanged(_ value: DragGesture.Value) {
        switch state.currentTool {
        case .arrow, .doubleArrow, .line, .rectangle, .ellipse, .blur, .crop:
            updateDragShape(start: value.startLocation, current: value.location)
        case .pen, .highlighter:
            updateFreehand(point: value.location)
        case .select:
            updateSelectMove(start: value.startLocation, current: value.location)
        case .text:
            break
        }
    }

    private func handleEnded(_ value: DragGesture.Value) {
        switch state.currentTool {
        case .arrow, .doubleArrow, .line, .rectangle, .ellipse, .blur:
            // Layer was added incrementally during onChanged; nothing more to do
            inProgressLayerID = nil
        case .pen, .highlighter:
            inProgressLayerID = nil
            freehandPoints = []
        case .crop:
            // Crop sets canvasCrop instead of adding a layer
            let rect = normalizedRect(from: value.startLocation, to: value.location)
            state.setCrop(rect.width >= 4 && rect.height >= 4 ? rect : nil)
        case .select:
            moveOriginalLayer = nil
        case .text:
            break
        }
    }

    // MARK: - Select tool: drag-to-move the currently selected layer

    private func updateSelectMove(start: CGPoint, current: CGPoint) {
        // First tick of the drag: snapshot the selected layer if the drag started inside its bounds.
        if moveOriginalLayer == nil {
            guard let id = state.selectedLayerID,
                  let layer = state.document.layer(id: id),
                  HitTest.contains(layer, point: start) else {
                return
            }
            moveOriginalLayer = layer
        }
        guard let original = moveOriginalLayer else { return }
        let offset = CGSize(width: current.x - start.x, height: current.y - start.y)
        let translated = translate(layer: original, by: offset)
        state.replace(translated)
    }

    private func translate(layer: AnnotationLayer, by offset: CGSize) -> AnnotationLayer {
        switch layer {
        case .arrow(let p, let id):
            return .arrow(ArrowProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                     color: p.color, thickness: p.thickness, doubleHeaded: p.doubleHeaded), id: id)
        case .line(let p, let id):
            return .line(LineProps(start: p.start.offsetBy(offset), end: p.end.offsetBy(offset),
                                   color: p.color, thickness: p.thickness), id: id)
        case .rectangle(let p, let id):
            return .rectangle(ShapeProps(rect: p.rect.offsetBy(offset),
                                         color: p.color, thickness: p.thickness, filled: p.filled), id: id)
        case .ellipse(let p, let id):
            return .ellipse(ShapeProps(rect: p.rect.offsetBy(offset),
                                       color: p.color, thickness: p.thickness, filled: p.filled), id: id)
        case .freehand(let p, let id):
            return .freehand(FreehandProps(points: p.points.map { $0.offsetBy(offset) },
                                           color: p.color, thickness: p.thickness, isHighlighter: p.isHighlighter), id: id)
        case .text(let p, let id):
            return .text(TextProps(origin: p.origin.offsetBy(offset), text: p.text,
                                   color: p.color, fontName: p.fontName, fontSize: p.fontSize), id: id)
        case .blur(let p, let id):
            return .blur(BlurProps(rect: p.rect.offsetBy(offset),
                                   style: p.style, intensity: p.intensity), id: id)
        }
    }

    // MARK: - Helpers — drag-to-create shape (in-progress layer is updated on each onChanged tick)

    private func updateDragShape(start: CGPoint, current: CGPoint) {
        let rect = normalizedRect(from: start, to: current)
        let line = (start: start, end: current)

        let newLayer = makeLayerForCurrentTool(rect: rect, line: line)

        if let id = inProgressLayerID,
           let existingIdx = state.document.layers.firstIndex(where: { $0.id == id }) {
            // Replace in place
            let layerWithSameID = newLayer.withID(id)
            state.replace(layerWithSameID)
            _ = existingIdx
        } else {
            state.add(newLayer)
            inProgressLayerID = newLayer.id
        }
    }

    private func makeLayerForCurrentTool(rect: CGRect, line: (start: CGPoint, end: CGPoint)) -> AnnotationLayer {
        switch state.currentTool {
        case .arrow:
            return .arrow(ArrowProps(start: line.start, end: line.end, color: state.currentColor,
                                     thickness: state.currentThickness, doubleHeaded: false))
        case .doubleArrow:
            return .arrow(ArrowProps(start: line.start, end: line.end, color: state.currentColor,
                                     thickness: state.currentThickness, doubleHeaded: true))
        case .line:
            return .line(LineProps(start: line.start, end: line.end, color: state.currentColor,
                                   thickness: state.currentThickness))
        case .rectangle:
            return .rectangle(ShapeProps(rect: rect, color: state.currentColor,
                                         thickness: state.currentThickness, filled: state.currentFilled))
        case .ellipse:
            return .ellipse(ShapeProps(rect: rect, color: state.currentColor,
                                       thickness: state.currentThickness, filled: state.currentFilled))
        case .blur:
            return .blur(BlurProps(rect: rect, style: state.currentBlurStyle, intensity: state.currentBlurIntensity))
        default:
            return .rectangle(ShapeProps(rect: rect, color: state.currentColor,
                                         thickness: state.currentThickness, filled: false))
        }
    }

    // MARK: - Freehand (pen / highlighter)

    private func updateFreehand(point: CGPoint) {
        if inProgressLayerID == nil {
            freehandPoints = [point]
            let layer = AnnotationLayer.freehand(FreehandProps(
                points: freehandPoints,
                color: state.currentColor,
                thickness: state.currentTool == .highlighter ? max(state.currentThickness, 12) : state.currentThickness,
                isHighlighter: state.currentTool == .highlighter
            ))
            state.add(layer)
            inProgressLayerID = layer.id
        } else {
            freehandPoints.append(point)
            let updated = AnnotationLayer.freehand(FreehandProps(
                points: freehandPoints,
                color: state.currentColor,
                thickness: state.currentTool == .highlighter ? max(state.currentThickness, 12) : state.currentThickness,
                isHighlighter: state.currentTool == .highlighter
            ), id: inProgressLayerID!)
            state.replace(updated)
        }
    }

    // MARK: - Geometry

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

// Helper: rebuild a layer with a specific id (preserves identity during in-progress drag)
private extension AnnotationLayer {
    func withID(_ id: UUID) -> AnnotationLayer {
        switch self {
        case .arrow(let p, _):     return .arrow(p, id: id)
        case .line(let p, _):      return .line(p, id: id)
        case .rectangle(let p, _): return .rectangle(p, id: id)
        case .ellipse(let p, _):   return .ellipse(p, id: id)
        case .freehand(let p, _):  return .freehand(p, id: id)
        case .text(let p, _):      return .text(p, id: id)
        case .blur(let p, _):      return .blur(p, id: id)
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
git add JuiceScreen/Annotation/Canvas/CanvasGestures.swift
git commit -m "feat(annotation): CanvasGestures — drag dispatch for all tools + tap (Select/Text)"
```

---

## Task 11: `SelectionHandlesView` — 8 corner/edge handles for selected layer

**Files:**
- Create: `JuiceScreen/Annotation/Canvas/SelectionHandlesView.swift`

- [ ] **Step 1: Implement `SelectionHandlesView.swift`**

```swift
import AppKit
import SwiftUI

/// Renders the 8-point selection handles around the bounding rect of the selected layer.
/// Drag handlers for resizing land in a later iteration; v0.3.0 ships the handles as a
/// visual indicator + supports moving the entire layer by dragging anywhere inside its bounds.
struct SelectionHandlesView: View {

    let layer: AnnotationLayer

    var body: some View {
        let rect = layer.boundingRect
        ZStack {
            // Outline
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // 8 handles at the corners + midpoints
            ForEach(handlePositions(in: rect), id: \.self) { pt in
                Rectangle()
                    .fill(Color.white)
                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .position(pt)
            }
        }
        .allowsHitTesting(false)
    }

    private func handlePositions(in r: CGRect) -> [CGPoint] {
        [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.midY),
            CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY)
        ]
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
git add JuiceScreen/Annotation/Canvas/SelectionHandlesView.swift
git commit -m "feat(annotation): SelectionHandlesView 8-point handles around selected layer"
```

---

## Task 12: `ToolPalette` + `ToolPaletteButton` (left rail)

**Files:**
- Create: `JuiceScreen/Annotation/ToolUI/ToolPaletteButton.swift`
- Create: `JuiceScreen/Annotation/ToolUI/ToolPalette.swift`

- [ ] **Step 1: Implement `ToolPaletteButton.swift`**

```swift
import SwiftUI

struct ToolPaletteButton: View {

    let tool: ToolType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: tool.sfSymbol)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }
}
```

- [ ] **Step 2: Implement `ToolPalette.swift`**

```swift
import SwiftUI

struct ToolPalette: View {

    @Bindable var state: EditorState

    var body: some View {
        VStack(spacing: 4) {
            ForEach(ToolType.allCases, id: \.self) { tool in
                ToolPaletteButton(tool: tool, isSelected: state.currentTool == tool) {
                    state.currentTool = tool
                    if tool != .select {
                        state.selectedLayerID = nil
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 48)
        .background(.regularMaterial)
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
git add JuiceScreen/Annotation/ToolUI/ToolPaletteButton.swift JuiceScreen/Annotation/ToolUI/ToolPalette.swift
git commit -m "feat(annotation): ToolPalette left rail with all 11 tool buttons"
```

---

## Task 13: `ColorSwatchPicker` + `ThicknessSlider` + `FontControls`

**Files:**
- Create: `JuiceScreen/Annotation/ToolUI/ColorSwatchPicker.swift`
- Create: `JuiceScreen/Annotation/ToolUI/ThicknessSlider.swift`
- Create: `JuiceScreen/Annotation/ToolUI/FontControls.swift`

- [ ] **Step 1: Implement `ColorSwatchPicker.swift`**

```swift
import AppKit
import SwiftUI

struct ColorSwatchPicker: View {

    @Binding var color: NSColor

    private static let presets: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .black, .white
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.presets.indices, id: \.self) { i in
                let preset = Self.presets[i]
                Circle()
                    .fill(Color(preset))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle().stroke(Color.primary.opacity(color == preset ? 0.9 : 0.2), lineWidth: color == preset ? 2 : 1)
                    )
                    .onTapGesture { color = preset }
            }

            // Custom color via NSColorPanel
            Image(systemName: "paintpalette")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(4)
                .onTapGesture { showCustomColorPanel() }
                .help("Custom color")
        }
    }

    private func showCustomColorPanel() {
        let panel = NSColorPanel.shared
        panel.color = color
        panel.makeKeyAndOrderFront(nil)
        // The user-selected color flows back via observation in v0.3.1; for v0.3.0
        // we rely on the seven presets and surface NSColorPanel as an open hook only.
    }
}
```

- [ ] **Step 2: Implement `ThicknessSlider.swift`**

```swift
import SwiftUI

struct ThicknessSlider: View {

    @Binding var thickness: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lineweight").font(.system(size: 12)).foregroundStyle(.secondary)
            Slider(value: $thickness, in: 1...20, step: 1)
                .frame(width: 100)
            Text("\(Int(thickness))")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 18)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Implement `FontControls.swift`**

```swift
import AppKit
import SwiftUI

struct FontControls: View {

    @Binding var fontName: String
    @Binding var fontSize: CGFloat

    private let fonts = ["Helvetica", "Helvetica Neue", "Menlo", "SF Pro", "Times New Roman"]

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $fontName) {
                ForEach(fonts, id: \.self) { f in
                    Text(f).tag(f)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Stepper(value: $fontSize, in: 8...96, step: 1) {
                Text("\(Int(fontSize))pt")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 36)
                    .foregroundStyle(.secondary)
            }
        }
    }
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
git add JuiceScreen/Annotation/ToolUI/ColorSwatchPicker.swift JuiceScreen/Annotation/ToolUI/ThicknessSlider.swift JuiceScreen/Annotation/ToolUI/FontControls.swift
git commit -m "feat(annotation): ColorSwatchPicker + ThicknessSlider + FontControls"
```

---

## Task 14: `TopBar` (context-sensitive)

**Files:**
- Create: `JuiceScreen/Annotation/ToolUI/TopBar.swift`

- [ ] **Step 1: Implement `TopBar.swift`**

```swift
import SwiftUI

/// Renders only the controls that apply to the current tool. For `.select`, it shows
/// controls for the selected layer's properties (color/thickness if shape; font if text).
struct TopBar: View {

    @Bindable var state: EditorState

    var body: some View {
        HStack(spacing: 14) {
            switch state.currentTool {
            case .select:
                if let id = state.selectedLayerID, let layer = state.document.layer(id: id) {
                    selectionControls(for: layer)
                } else {
                    Text("Click an annotation to edit it. Press a tool below to add a new one.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

            case .arrow, .doubleArrow, .line:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                ThicknessSlider(thickness: $state.currentThickness)

            case .rectangle, .ellipse:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                ThicknessSlider(thickness: $state.currentThickness)
                Toggle("Filled", isOn: $state.currentFilled).toggleStyle(.switch).labelsHidden()
                Text(state.currentFilled ? "Fill" : "Outline")
                    .font(.system(size: 11)).foregroundStyle(.secondary)

            case .pen, .highlighter:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                ThicknessSlider(thickness: $state.currentThickness)

            case .text:
                ColorSwatchPicker(color: $state.currentColor)
                Divider().frame(height: 18)
                FontControls(fontName: $state.currentFontName, fontSize: $state.currentFontSize)

            case .blur:
                Picker("Style", selection: $state.currentBlurStyle) {
                    Text("Blur").tag(BlurProps.Style.gaussian)
                    Text("Pixelate").tag(BlurProps.Style.pixelate)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Divider().frame(height: 18)
                Slider(value: $state.currentBlurIntensity, in: 4...32, step: 1).frame(width: 120)
                Text("\(Int(state.currentBlurIntensity))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

            case .crop:
                Text("Drag a rectangle to crop. Drag again to update; clear by selecting another tool then re-selecting Crop.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func selectionControls(for layer: AnnotationLayer) -> some View {
        switch layer {
        case .arrow, .line, .freehand:
            Text("Color/thickness apply to the next stroke. Edit via re-creating for v0.3.0.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .rectangle, .ellipse:
            Text("Filled / outlined toggle applies to the next shape.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .text(let p, _):
            Text("\"\(p.text)\" • \(p.fontName) \(Int(p.fontSize))pt")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        case .blur(let p, _):
            Text("\(p.style == .gaussian ? "Blur" : "Pixelate") • intensity \(Int(p.intensity))")
                .font(.system(size: 11)).foregroundStyle(.secondary)
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
git add JuiceScreen/Annotation/ToolUI/TopBar.swift
git commit -m "feat(annotation): TopBar context-sensitive controls (per tool)"
```

---

## Task 15: `BlurEffect` (Core Image gaussian + pixelate destructive blur)

**Files:**
- Create: `JuiceScreen/Annotation/Export/BlurEffect.swift`

(No automated test for visual output. Smoke-tested via export.)

- [ ] **Step 1: Implement `BlurEffect.swift`**

```swift
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Applies a destructive blur or pixelate filter to a region of a CGImage.
/// Returns a new CGImage with the original pixels in `region` replaced by the
/// filtered version (clipped to `region`). Used at export time so recipients
/// of the exported file cannot reverse the blur.
public enum BlurEffect {

    public static func apply(_ props: BlurProps, to image: CGImage) -> CGImage? {
        let ciContext = CIContext(options: nil)
        let baseCI = CIImage(cgImage: image)

        // The blur region in CI coordinates. CI uses bottom-left origin; AppKit/SwiftUI use top-left.
        // We assume `image` is already in the same coordinate space as `props.rect` (both AppKit/top-left)
        // and convert to CI's bottom-left here.
        let imgHeight = CGFloat(image.height)
        let ciRect = CGRect(
            x: props.rect.minX,
            y: imgHeight - props.rect.maxY,
            width: props.rect.width,
            height: props.rect.height
        )

        let filter: CIFilter
        switch props.style {
        case .gaussian:
            let f = CIFilter.gaussianBlur()
            f.inputImage = baseCI.cropped(to: ciRect).clampedToExtent()
            f.radius = Float(props.intensity)
            filter = f
        case .pixelate:
            let f = CIFilter.pixellate()
            f.inputImage = baseCI.cropped(to: ciRect).clampedToExtent()
            f.scale = Float(props.intensity)
            filter = f
        }

        guard let blurredFull = filter.outputImage else { return image }
        let blurredCropped = blurredFull.cropped(to: ciRect)
        let composite = blurredCropped.composited(over: baseCI)

        return ciContext.createCGImage(composite, from: baseCI.extent)
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
git add JuiceScreen/Annotation/Export/BlurEffect.swift
git commit -m "feat(annotation): BlurEffect destructive Core Image blur + pixelate"
```

---

## Task 16: `AnnotationRenderer` (flatten document → NSImage)

**Files:**
- Create: `JuiceScreen/Annotation/Export/AnnotationRenderer.swift`

(No automated test — visual rendering. Smoke-tested via ExportService tests in Task 18 + manual verification.)

- [ ] **Step 1: Implement `AnnotationRenderer.swift`**

```swift
import AppKit
import SwiftUI

/// Flattens an `AnnotationDocument` into a single `NSImage`, applying:
///   1. Destructive blur regions (so recipients cannot reverse them)
///   2. All non-blur layers via `LayerRenderer` into a SwiftUI ImageRenderer pipeline
///   3. Crop, if `document.canvasCrop` is set
///
/// The output preserves the base image's pixel resolution.
@MainActor
public enum AnnotationRenderer {

    public enum RenderError: Error, Equatable {
        case noBaseCGImage
        case rendererFailed
    }

    public static func render(_ document: AnnotationDocument) throws -> NSImage {
        guard let baseCG = document.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw RenderError.noBaseCGImage
        }

        // Step 1: apply blur layers destructively to the base CGImage
        var workingCG = baseCG
        for layer in document.layers {
            if case .blur(let p, _) = layer {
                if let next = BlurEffect.apply(p, to: workingCG) {
                    workingCG = next
                }
            }
        }

        // Step 2: build a SwiftUI Canvas with the blurred base + non-blur layers, render to image
        let pixelWidth = workingCG.width
        let pixelHeight = workingCG.height
        let pointSize = NSSize(width: pixelWidth, height: pixelHeight)
        let nonBlurLayers = document.layers.filter {
            if case .blur = $0 { return false } else { return true }
        }

        let view = AnnotationCanvas(
            baseImage: NSImage(cgImage: workingCG, size: pointSize),
            layers: nonBlurLayers,
            canvasSize: pointSize
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1   // already at native pixel resolution
        guard let flattened = renderer.nsImage else {
            throw RenderError.rendererFailed
        }

        // Step 3: crop if requested
        if let crop = document.canvasCrop, crop.width >= 1, crop.height >= 1 {
            return cropped(image: flattened, to: crop)
        }
        return flattened
    }

    private static func cropped(image: NSImage, to rect: CGRect) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        // Convert top-left rect to CGImage coordinates (CGImage origin is top-left already).
        let scaleX = CGFloat(cg.width) / image.size.width
        let scaleY = CGFloat(cg.height) / image.size.height
        let scaledRect = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        guard let croppedCG = cg.cropping(to: scaledRect) else { return image }
        return NSImage(cgImage: croppedCG, size: rect.size)
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
git add JuiceScreen/Annotation/Export/AnnotationRenderer.swift
git commit -m "feat(annotation): AnnotationRenderer flattens layers + applies destructive blur + crop"
```

---

## Task 17: `JPGEncoder` + tests

**Files:**
- Create: `JuiceScreen/Annotation/Export/JPGEncoder.swift`
- Create: `JuiceScreenTests/JPGEncoderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("JPGEncoder")
struct JPGEncoderTests {

    /// Deterministic 1× test fixture (same pattern as PNGEncoderTests).
    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
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

    @Test("Output starts with the JPEG SOI marker FF D8")
    func jpegSignature() throws {
        let img = solidImage(width: 8, height: 8, color: .red)
        let data = try JPGEncoder.encode(img, quality: 0.9)
        let prefix: [UInt8] = [0xFF, 0xD8]
        #expect(Array(data.prefix(2)) == prefix)
    }

    @Test("Higher quality produces equal-or-larger file than lower quality")
    func qualityImpactsSize() throws {
        let img = solidImage(width: 64, height: 64, color: .blue)
        let high = try JPGEncoder.encode(img, quality: 0.95)
        let low  = try JPGEncoder.encode(img, quality: 0.10)
        #expect(high.count >= low.count)
    }

    @Test("Throws on zero-size image")
    func zeroSize() {
        let bad = NSImage(size: .zero)
        #expect(throws: JPGEncoderError.self) {
            _ = try JPGEncoder.encode(bad, quality: 0.9)
        }
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/JPGEncoderTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `JPGEncoder.swift`**

```swift
import AppKit

public enum JPGEncoderError: Error, Equatable {
    case zeroSize
    case noBitmapRepresentation
    case encodingFailed
}

public enum JPGEncoder {

    public static func encode(_ image: NSImage, quality: Double) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else {
            throw JPGEncoderError.zeroSize
        }

        if let rep = image.representations.first as? NSBitmapImageRep,
           let data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)]) {
            return data
        }

        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw JPGEncoderError.noBitmapRepresentation
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: quality)]) else {
            throw JPGEncoderError.encodingFailed
        }
        return data
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/JPGEncoderTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Export/JPGEncoder.swift JuiceScreenTests/JPGEncoderTests.swift
git commit -m "feat(annotation): JPGEncoder for NSImage → JPG Data with quality"
```

---

## Task 18: `ExportService` + tests

**Files:**
- Create: `JuiceScreen/Annotation/Export/ExportService.swift`
- Create: `JuiceScreenTests/ExportServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Testing
@testable import JuiceScreen

@Suite("ExportService")
@MainActor
struct ExportServiceTests {

    private func solidImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
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

    private func tempURL(ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JS-export-\(UUID().uuidString).\(ext)")
    }

    @Test("Export PNG produces a file starting with PNG signature")
    func exportPNG() async throws {
        let doc = AnnotationDocument(baseImage: solidImage(width: 64, height: 64, color: .red))
        let url = tempURL(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.export(document: doc, format: .png, jpegQuality: 0.9, to: url)

        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test("Export JPG produces a file starting with JPEG SOI")
    func exportJPG() async throws {
        let doc = AnnotationDocument(baseImage: solidImage(width: 64, height: 64, color: .blue))
        let url = tempURL(ext: "jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.export(document: doc, format: .jpg, jpegQuality: 0.85, to: url)

        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(2)) == [0xFF, 0xD8])
    }

    @Test("Crop reduces output dimensions")
    func cropReducesSize() async throws {
        var doc = AnnotationDocument(baseImage: solidImage(width: 100, height: 100, color: .green))
        doc.canvasCrop = CGRect(x: 0, y: 0, width: 25, height: 25)
        let url = tempURL(ext: "png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ExportService.export(document: doc, format: .png, jpegQuality: 0.9, to: url)

        let data = try Data(contentsOf: url)
        let rep = NSBitmapImageRep(data: data)
        #expect(rep != nil)
        #expect((rep?.pixelsWide ?? 0) <= 50)   // significantly smaller than original 100
        #expect((rep?.pixelsHigh ?? 0) <= 50)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ExportServiceTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `ExportService.swift`**

```swift
import AppKit
import Foundation

@MainActor
public enum ExportService {

    public enum Format: String, Sendable, CaseIterable {
        case png
        case jpg
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
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw ExportError.writeFailed("\(error)")
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/ExportServiceTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Annotation/Export/ExportService.swift JuiceScreenTests/ExportServiceTests.swift
git commit -m "feat(annotation): ExportService coordinates flatten + encode + write (PNG/JPG)"
```

---

## Task 19: `QuickActions` (Copy/Save/Save As/Show in Finder/Discard)

**Files:**
- Create: `JuiceScreen/Annotation/Editor/QuickActions.swift`

- [ ] **Step 1: Implement `QuickActions.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
public final class QuickActions {

    private let state: EditorState
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "QuickActions")

    public init(state: EditorState, preferences: PreferencesStore) {
        self.state = state
        self.preferences = preferences
    }

    /// Copies the flattened image to the system pasteboard as PNG.
    public func copyToClipboard() {
        do {
            let flattened = try AnnotationRenderer.render(state.document)
            let data = try PNGEncoder.encode(flattened)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: .png)
            log.info("Copied flattened image to clipboard (\(data.count) bytes)")
        } catch {
            log.error("Copy failed: \(String(describing: error))")
            NSSound.beep()
        }
    }

    /// Saves to the original capture's location, replacing the file in place.
    public func save() {
        let url = state.captureRecord.fileURL
        let format: ExportService.Format = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" ? .jpg : .png
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

    /// Opens an `NSSavePanel` and writes to the chosen location.
    public func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = state.captureRecord.fileURL.deletingPathExtension().lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format: ExportService.Format = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" ? .jpg : .png
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

    /// Reveals the original capture file in Finder.
    public func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([state.captureRecord.fileURL])
    }

    /// Asks the user to confirm if there are unsaved edits, then closes the editor window.
    /// Returns true if the caller should close the window.
    public func discardConfirm() -> Bool {
        guard state.isEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard edits?"
        alert.informativeText = "You have unsaved annotation changes. Closing will lose them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Helpers

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not save"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
git add JuiceScreen/Annotation/Editor/QuickActions.swift
git commit -m "feat(annotation): QuickActions (Copy/Save/Save As/Show in Finder/Discard)"
```

---

## Task 20: `KeyboardCommands` view modifier

**Files:**
- Create: `JuiceScreen/Annotation/Editor/KeyboardCommands.swift`

- [ ] **Step 1: Implement `KeyboardCommands.swift`**

```swift
import SwiftUI

/// Applies keyboard shortcuts to the editor: undo, redo, duplicate, delete.
/// Save / Save As / Copy / Discard are wired by the EditorView's toolbar buttons
/// (Task 21) since they need access to the QuickActions instance.
struct KeyboardCommandsModifier: ViewModifier {

    @Bindable var state: EditorState

    func body(content: Content) -> some View {
        content
            .onKeyPress(.init("z"), action: {
                if NSEvent.modifierFlags.contains(.shift) {
                    state.redo()
                } else {
                    state.undo()
                }
                return .handled
            })
            .onKeyPress(.init("d"), action: {
                state.duplicateSelected()
                return .handled
            })
            .onKeyPress(.delete, action: {
                state.deleteSelected()
                return .handled
            })
    }
}

extension View {
    func editorKeyboardCommands(state: EditorState) -> some View {
        modifier(KeyboardCommandsModifier(state: state))
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
git add JuiceScreen/Annotation/Editor/KeyboardCommands.swift
git commit -m "feat(annotation): KeyboardCommands view modifier (undo/redo/duplicate/delete)"
```

---

## Task 21: `EditorView` (top-level SwiftUI: TopBar + Palette + Canvas + toolbar)

**Files:**
- Create: `JuiceScreen/Annotation/Editor/EditorView.swift`

- [ ] **Step 1: Implement `EditorView.swift`**

```swift
import AppKit
import SwiftUI

struct EditorView: View {

    @Bindable var state: EditorState
    let actions: QuickActions

    var body: some View {
        HStack(spacing: 0) {
            ToolPalette(state: state)

            VStack(spacing: 0) {
                TopBar(state: state)

                ZStack(alignment: .topLeading) {
                    AnnotationCanvas(
                        baseImage: state.document.baseImage,
                        layers: state.document.layers,
                        canvasSize: canvasPointSize
                    )

                    if let id = state.selectedLayerID, let layer = state.document.layer(id: id) {
                        SelectionHandlesView(layer: layer)
                            .frame(width: canvasPointSize.width, height: canvasPointSize.height, alignment: .topLeading)
                    }

                    CanvasGestures(state: state)
                        .frame(width: canvasPointSize.width, height: canvasPointSize.height)
                }
                .frame(width: canvasPointSize.width, height: canvasPointSize.height)
                .clipped()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    actions.copyToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy to clipboard (⌘C)")

                Button {
                    actions.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save (⌘S)")

                Button {
                    actions.saveAs()
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down.on.square")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Save As… (⌘⇧S)")

                Button {
                    actions.showInFinder()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .help("Show in Finder")
            }
        }
        .editorKeyboardCommands(state: state)
    }

    private var canvasPointSize: CGSize {
        let pixelW = CGFloat(state.captureRecord.pixelWidth)
        let pixelH = CGFloat(state.captureRecord.pixelHeight)
        // Treat captures as 2x retina; show at half-pixel point size to fit on screen
        return CGSize(width: pixelW / 2, height: pixelH / 2)
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
git add JuiceScreen/Annotation/Editor/EditorView.swift
git commit -m "feat(annotation): EditorView wires palette + topbar + canvas + toolbar"
```

---

## Task 22: `EditorWindow` + `EditorWindowManager`

**Files:**
- Create: `JuiceScreen/Annotation/Editor/EditorWindow.swift`
- Create: `JuiceScreen/Annotation/Editor/EditorWindowManager.swift`

- [ ] **Step 1: Implement `EditorWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class EditorWindow {

    let window: NSWindow
    private let state: EditorState
    private let actions: QuickActions
    private let onClose: () -> Void
    private var closeObserver: NSObjectProtocol?

    init(captureRecord: CaptureRecord, baseImage: NSImage, preferences: PreferencesStore, onClose: @escaping () -> Void) {
        let state = EditorState(captureRecord: captureRecord, baseImage: baseImage)
        self.state = state
        self.actions = QuickActions(state: state, preferences: preferences)
        self.onClose = onClose

        // Initial window size: half the capture's pixel size + chrome (toolbar + palette + topbar).
        let canvasW = CGFloat(captureRecord.pixelWidth) / 2
        let canvasH = CGFloat(captureRecord.pixelHeight) / 2
        let chromeW: CGFloat = 48 + 0   // tool palette
        let chromeH: CGFloat = 40 + 28  // top bar + window title bar
        let frame = NSRect(x: 0, y: 0, width: canvasW + chromeW, height: canvasH + chromeH)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "JuiceScreen — \(captureRecord.fileURL.lastPathComponent)"
        win.contentView = NSHostingView(rootView: EditorView(state: state, actions: actions))
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { _ in
            onClose()
        }
        self.closeObserver = observer
    }

    deinit {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Confirms discard with the user (if edited) and returns true if the window may close.
    func confirmClose() -> Bool {
        actions.discardConfirm()
    }
}
```

- [ ] **Step 2: Implement `EditorWindowManager.swift`**

```swift
import AppKit
import Foundation

@MainActor
public final class EditorWindowManager {

    private var openWindows: [UUID: EditorWindow] = [:]
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "EditorWindowManager")

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    /// Opens an editor window for a successful capture. If a window is already
    /// open for this capture (matched by UUID), brings it to the front instead.
    public func show(for record: CaptureRecord) {
        if let existing = openWindows[record.id] {
            existing.show()
            return
        }
        guard let image = NSImage(contentsOf: record.fileURL) else {
            log.error("Could not load image at \(record.fileURL.path)")
            return
        }
        let window = EditorWindow(
            captureRecord: record,
            baseImage: image,
            preferences: preferences,
            onClose: { [weak self] in
                self?.openWindows.removeValue(forKey: record.id)
            }
        )
        openWindows[record.id] = window
        window.show()
        log.info("Opened editor for capture \(record.id) (\(record.fileURL.lastPathComponent))")
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
git add JuiceScreen/Annotation/Editor/EditorWindow.swift JuiceScreen/Annotation/Editor/EditorWindowManager.swift
git commit -m "feat(annotation): EditorWindow per capture + EditorWindowManager singleton tracker"
```

---

## Task 23: Integrate `EditorWindowManager` into `AppDelegate`

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Add `editorWindowManager` and open on capture**

In `JuiceScreen/App/AppDelegate.swift`:

1. Add a property:

```swift
    private lazy var editorWindowManager: EditorWindowManager = {
        EditorWindowManager(preferences: preferences)
    }()
```

2. In `fireCapture(_:)`, modify the success branch (`log.info("Captured...")`) to also open the editor:

```swift
                log.info("Captured \(String(describing: record.captureType)) → \(record.fileURL.path)")
                editorWindowManager.show(for: record)
```

The full updated `fireCapture` method:

```swift
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
                editorWindowManager.show(for: record)
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
```

- [ ] **Step 2: Verify build + run all unit tests**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: `** BUILD SUCCEEDED **` and all unit tests still pass (~94 across many suites: 55 from Plan 2 + 39 added by Plan 3 — Tool/Props/Layer/Document/HitTest/Undo/EditorState/JPG/Export tests).

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): open EditorWindow automatically after a successful capture"
```

---

## Task 24: Bump VERSION to 0.3.0, full test run, manual smoke, tag

**Files:**
- Modify: `VERSION` — `0.3.0`
- Modify: `project.yml` — `MARKETING_VERSION: "0.3.0"`

- [ ] **Step 1: Update VERSION**

Replace the contents of `VERSION` with a single line:

```
0.3.0
```

- [ ] **Step 2: Update project.yml MARKETING_VERSION**

In `project.yml`, change `MARKETING_VERSION: "0.2.0"` to `MARKETING_VERSION: "0.3.0"`.

- [ ] **Step 3: Clean build + full test**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
rm -rf ~/Library/Developer/Xcode/DerivedData/JuiceScreen-*
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
```

Expected: build + tests succeed (~94 unit tests).

- [ ] **Step 4: Manual smoke test (HUMAN STEP)**

```bash
APP_PATH="$(xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
open "$APP_PATH"
```

Verify each capture mode opens an editor window:

| # | Action | Expected |
|---|---|---|
| 1 | Trigger Capture Region (⌘⌃4 / ⌘⇧4) → drag a rectangle | Editor window opens with the captured image |
| 2 | In editor: select Arrow tool, draw an arrow | Arrow appears on the canvas |
| 3 | ⌘Z | Arrow disappears |
| 4 | ⌘⇧Z | Arrow reappears |
| 5 | Click Select tool, click the arrow | Selection handles appear around it |
| 6 | Press Delete | Arrow disappears |
| 7 | Try each tool: Rectangle (filled toggle), Ellipse, Pen, Highlighter, Text, Blur (gaussian + pixelate), Crop | Each places its own annotation correctly |
| 8 | ⌘C in editor | Pasteboard contains the annotated image (verify by pasting into a chat app) |
| 9 | ⌘S | Original file is overwritten with annotated version (check file mtime in Finder) |
| 10 | ⌘⇧S | Save As panel opens; choose a new location and save |
| 11 | Trigger Capture Full Screen | New editor window opens for the new capture (the original editor stays open) |
| 12 | Close an edited editor | Discard prompt appears; choose Discard or Cancel |
| 13 | Verify Plan 2 captures still work end-to-end | All four modes still produce PNGs in `~/Pictures/JuiceScreen/<date>/` |

If any step fails: do **not** tag. Fix and re-test.

- [ ] **Step 5: Commit + tag**

```bash
git add VERSION project.yml
git commit -m "chore: bump VERSION to 0.3.0"
git tag -a v0.3.0 -m "Annotation Editor milestone: 11 tools + undo + export PNG/JPG"
git tag -l v0.3.0
```

- [ ] **Step 6: Verify clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Task 25: Update spec doc with Plan 3 status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Update Plan 3 line**

Replace `⬜ Plan 3: Annotation editor` with:

```
- ✅ **Plan 3: Annotation editor** (v0.3.0, 2026-05-05) — Per-capture NSWindow opens automatically after each capture. All 11 tools implemented: Select, Arrow, Double Arrow, Line, Rectangle (hollow/filled), Ellipse (hollow/filled), Pen, Highlighter, Text, Blur (gaussian/pixelate), Crop. Snapshot-based undo/redo via UndoStack. Top bar shows context-sensitive controls per tool. Export to PNG and JPG with quality from preferences (PDF deferred to Plan 9). Quick actions: Copy/Save/Save As/Show in Finder/Discard with confirmation. Destructive blur via Core Image at export. ~39 new unit tests; ~94 total
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 3 (Annotation editor) complete in implementation status"
```

---

## Plan completion checklist

After Task 25:

- [ ] `git log --oneline | head -30` shows ~25 new commits since v0.2.0
- [ ] `git tag -l` shows v0.1.0, v0.2.0, v0.3.0
- [ ] `xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests` is green (~94 tests)
- [ ] All 13 manual smoke-test items pass
- [ ] Each capture flow (Plan 2) → editor opens (Plan 3) → annotate → save → file on disk has the annotation

When everything checks out: ship v0.3.0 alpha. Plan 4 is next — the SQLite-backed library + main window + soft delete.
