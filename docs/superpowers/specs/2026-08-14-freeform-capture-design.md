# FreeForm Capture — Design

**Date:** 2026-08-14
**Status:** Approved, ready for implementation planning
**Baseline:** v1.1.2

## Goal

Capture a non-rectangular region of the screen. The user draws a shape — freehand or as a polygon — and JuiceScreen writes a PNG cropped to the shape's bounding box, with everything outside the shape transparent.

## Scope

In:

- A `Capture Freeform` menu item with its own hotkey slot.
- Two drawing modes in one overlay: freehand (default) and polygon, toggled with Tab before the first point is placed.
- Transparent PNG output, cropped to the bounding box.
- Explicit white flattening wherever transparency cannot survive: JPG export, PDF export, library thumbnails.
- A checkerboard behind the image in the editor so transparency is visible.

Out, deliberately:

- FreeForm for video recording and scroll capture. Separate features with separate capture pipelines.
- Feathered / anti-aliased soft edges beyond what `CGContext` path clipping gives for free.
- Automatic edge or subject detection.

## Architecture

Four new units, one refactor, and three touched call sites.

### `OverlayPickerHost<Payload>` (new)

Owns the parts of `RegionPickerController` that have nothing to do with rectangles: one borderless overlay window per `NSScreen`, arbitration of which overlay owns the in-flight gesture, the Esc monitor, and the `CheckedContinuation` that turns the callback flow into `async`.

```swift
@MainActor
final class OverlayPickerHost<Payload> {
    typealias ContentBuilder = (
        _ screen: NSScreen,
        _ isActive: Bool,
        _ onBegan: @escaping () -> Void,
        _ onCommitted: @escaping (Payload?) -> Void
    ) -> AnyView

    func pick(content: @escaping ContentBuilder) async throws -> (payload: Payload, screen: NSScreen)
}
```

The host returns the payload together with the `NSScreen` whose overlay owned the gesture, and performs no coordinate conversion of its own. Geometry stays with the caller. `nil` from `onCommitted` throws `CaptureError.userCancelled`, matching today's behaviour.

`RegionPickerController` is rewritten on top of the host. Its externally visible contract — `pickRegion() async throws -> CGRect` in global bottom-left points — does not change, so `CaptureEngineLive` is unaffected by the refactor.

### `FreeformSelection` (new, pure)

A value type in overlay-local top-left coordinates. No AppKit, no `@MainActor`, fully testable.

```swift
enum FreeformMode { case freehand, polygon }

struct FreeformSelection: Equatable, Sendable {
    var mode: FreeformMode
    private(set) var points: [CGPoint]

    mutating func append(_ point: CGPoint)      // freehand: min-distance filtered
    mutating func appendVertex(_ point: CGPoint) // polygon
    mutating func removeLastVertex()             // polygon undo

    var bounds: CGRect        // normalised, rounded outward to whole points
    var isUsable: Bool        // >= 3 points and bounds >= 1x1
    var closedPath: CGPath    // in overlay-local top-left space
    var pathInBounds: CGPath  // closedPath translated by -bounds.origin
}
```

Freehand `append` drops points closer than 2pt to the previous one. Without the filter a slow drag accumulates thousands of collinear points that carry no information and slow down both the live mask and the final clip.

`bounds` rounds outward (`integral`) so the captured rect never clips the stroke by a sub-point sliver.

### `FreeformPickerView` (new)

SwiftUI, one per overlay, same `GeometryReader` discipline as `RegionPickerView` (gesture space and render space must be the same `proxy.size` rect — see the comment in that file for why).

Renders the 35% dim layer masked by the current path, the path itself as a white 1pt stroke, and the existing `w × h` size label derived from `bounds`. In polygon mode a rubber-band segment follows the cursor from the last placed vertex, and a one-line HUD names the active mode.

Input:

| Key / gesture | Freehand | Polygon |
|---|---|---|
| Drag | draws the path | — |
| Click | — | places a vertex |
| Double-click / Enter | — | closes the shape |
| Backspace | — | removes the last vertex |
| Tab | switches to polygon (only before the first point) | switches to freehand (only before the first point) |
| Esc | cancels | cancels |

### `FreeformPickerController` (new)

Drives the host with `FreeformPickerView` and converts the result:

```swift
struct FreeformPick: Sendable {
    let globalBoundsBL: CGRect  // AppKit global, bottom-left origin
    let pathInBounds: CGPath    // relative to the bounds box, top-left origin
}
```

**Invariant:** the path is never expressed in global coordinates. Only the bounding box crosses the global/local boundary, and it does so through the same shared function every other capture path uses. This is the direct lesson of the v1.1.2 bug — every additional place that hand-rolls a coordinate conversion is a place it can be hand-rolled wrong.

### `FreeformMasker` (new, pure)

The only genuinely new image logic.

```swift
enum FreeformMasker {
    static func apply(path: CGPath, pathSpaceSize: CGSize, to image: CGImage) -> CGImage?
}
```

Allocates a `CGContext` at the source image's pixel dimensions in `premultipliedLast`, scales the path by `CGFloat(image.width) / pathSpaceSize.width` (points → pixels), flips the y axis once (`CGContext` is bottom-left, the path is top-left), clips to the transformed path and draws the image. Pixels outside the path keep alpha 0.

Rejected alternatives: `CGImage.masking(_:)` requires a source without an alpha channel, and ScreenCaptureKit hands back BGRA. Core Image with `CIBlendWithMask` needs a `CIContext` and buys nothing here.

### Refactor: `CaptureEngineLive.captureRect(globalBL:)`

Region, last-region and freeform all perform the same four steps: resolve the display containing the rect's centre, convert with `displayLocalTopLeft`, build the configuration, capture the image. That sequence is extracted into

```swift
private func captureRect(globalBL rect: CGRect) async throws -> (image: CGImage, display: SCDisplay)
```

and the three callers use it. Without this the sequence exists three times after the feature lands, and the third copy is the one a future fix forgets.

### Coordinate helper symmetry

`RegionPickerController.commit()` currently inlines the local-top-left → global-bottom-left conversion. It moves next to its inverse as

```swift
ScreenCaptureKitHelpers.globalBottomLeft(localTL:screenFrame:)
```

Both picker controllers then share one formula, and the existing round-trip test in `DisplayLocalTopLeftTests` covers both directions instead of re-deriving one of them.

## Transparency handling

Transparency survives only where the format supports it. Everywhere else it is flattened **explicitly onto white**, not left to AppKit's default.

| Path | Behaviour | Change needed |
|---|---|---|
| Capture → disk | PNG with alpha | none — `CaptureRecordWriter` already writes PNG, and `PNGEncoder` takes the `NSBitmapImageRep(cgImage:)` branch, which preserves alpha |
| Editor canvas | checkerboard behind the base image | view-only; must **not** enter `AnnotationRenderer`, or the pattern ends up in exports |
| Export PNG | alpha preserved | none |
| Export JPG | flatten to white | **yes** — `JPGEncoder` currently hands an alpha-carrying rep to `representation(using: .jpeg)`, which composites transparent areas onto **black** |
| Export PDF | flatten to white | **yes**, same reason |
| Library thumbnail | flatten to white | **yes** — `ThumbnailGenerator` draws into an alpha rep and then encodes JPEG, so transparent areas become black in the grid |
| Clipboard | PNG with alpha | none |

One shared helper does the flattening:

```swift
enum ImageFlattener {
    static func onWhite(_ image: NSImage) -> NSImage
}
```

`JPGEncoder` and `PDFEncoder` call it on entry. `ThumbnailGenerator` applies the same policy but fills its existing bitmap context with white before drawing, rather than calling the helper — it already allocates a target-sized context, and routing through the helper would add a full-resolution RGBA copy of the source before downscaling (~100 MB for a large Retina capture) for no gain.

This changes behaviour for existing captures only where an image already carries alpha, which today it never does — so the change is invisible for every capture taken before this feature.

## Data model

`CaptureType` gains a `freeform` case. `CaptureType` is **not** persisted — the `captures` table stores `mediaType` only — so there is no schema migration and no backfill.

`CaptureEngine` gains `captureFreeform() async throws -> CaptureRecord`; `FakeCaptureEngine` implements it so the menu and library flows stay testable without a screen.

## Wiring

A `Capture Freeform` item in the menu-bar dropdown next to `Capture Region`, routed through `AppDelegate` exactly like the region action, plus `HotkeyAction.captureFreeform = 9` and `Preferences.captureFreeformHotkey`.

Default binding **⌘⇧7** (keyCode 26). An unassigned default would be preferable, but `Hotkey` is a non-optional value type and every consumer — persistence, `HotkeyService.register`, the menu's shortcut string, the settings tab — assumes a binding exists. Making it optional is a larger change than this feature warrants. ⌘⇧7 continues the existing ⌘⇧2…⌘⇧6 family, is free in the current set (keyCodes 21, 19, 20, 15, 23, 37, 22), and is not a system shortcut.

## Testing

Three levels, all runnable without a display or Screen Recording permission.

**`FreeformSelection`** — pure geometry: freehand min-distance filtering, polygon vertex add and undo, `bounds` normalisation and outward rounding, `isUsable` at the 3-point and 1×1 boundaries, `pathInBounds` translation, and that a path drawn in either direction yields the same bounds.

**`FreeformMasker`** — an **asymmetric** path, because a vertically mirrored mask looks perfectly correct on a symmetric one. Assertions: a corner pixel outside the path is transparent, a pixel inside is opaque, the shape lands in the upper half when the path is in the upper half, and a 2:1 point-to-pixel scale maps correctly.

**Format chain** — alpha survives `PNGEncoder`, `JPGEncoder` produces white and not black where the source was transparent, `ThumbnailGenerator` likewise.

The menu and engine wiring rides on `FakeCaptureEngine`.

## Risks

The y-flip in `FreeformMasker` is the same class of bug as the v1.1.2 defect, one layer down. It is covered by an asymmetric-path test specifically because the symmetric case hides it.

`ImageFlattener` touches three encoders that existing captures already flow through. The behavioural change is confined to alpha-carrying input, which no capture taken before this feature produces, but the existing encoder tests must stay green unchanged.
