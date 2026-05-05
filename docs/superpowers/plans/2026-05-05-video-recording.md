# JuiceScreen — Video Recording Implementation Plan (Plan 6 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.6.0` — pressing the configured Record Screen hotkey (default `⌘⇧5`) opens a region picker, the user drags a rectangle (or presses Enter for full-screen on a single display), and a recording starts: ScreenCaptureKit captures frames at 60fps, system audio is mixed in by default, optional microphone audio comes from a separate `AVCaptureSession`, a cursor highlight ring is composited into every frame, and the result writes to an MP4 H.264 file at `~/Pictures/JuiceScreen/<date>/JuiceScreen_<timestamp>.mp4`. A small floating control bar shows duration + Stop button while recording. The menu bar icon switches to a red `record.circle` symbol. Stop via the control bar, the menu, or a global Stop Recording hotkey. After stop, a `CaptureRow` of `mediaType: .video` is inserted with a 256-px thumbnail derived from the first frame.

**Architecture:** New `Capture/Video/` module split into `Recording/` (orchestrator + protocol + Live + Fake), `Audio/` (microphone capture), `Overlay/` (cursor / click / keystroke renderers — pure functions over `CGContext`), `Composition/` (per-frame `FrameCompositor` that draws enabled overlays on top of incoming frames), `Output/` (`AVAssetWriter` wrapper), and `UI/` (floating control bar + window). The recording session is owned by an `@MainActor` `RecordingSession` actor that wires the recorder to the UI and the menu-bar indicator. Cursor highlight uses public-API `NSEvent.mouseLocation()` polled at 50Hz and needs no extra TCC permission. Click pulse and keystroke display require Input Monitoring (Plan 1's `PermissionsService` already handles the prompt) and default to OFF — first-time enable shows a permission rationale.

**Tech Stack:** ScreenCaptureKit (`SCStream`, `SCStreamConfiguration`, `SCContentFilter`, `SCStreamOutput`), AVFoundation (`AVAssetWriter`, `AVAssetWriterInput`, `AVCaptureSession`, `AVCaptureAudioDataOutput`), Core Graphics (`CGContext` for overlay rendering — sufficient at 60fps for our overlay sizes; can migrate to Core Image with Metal later if needed), AppKit (`NSEvent`, `CGEventTap`), existing modules from Plans 1–5 (`PermissionsService`, `CaptureRecord`, `CaptureLibraryRecorder`, `LibraryStore`, `MenuBarController.setRecordingIndicator`).

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — sections "Video recording" and "Menu bar item".

**Plan 5 prerequisite:** v0.5.0 tagged. The full-screen image-capture and region-picker code paths from Plan 2 already exist (`RegionPickerController`, `ScreenCaptureKitHelpers.shareableContent`). `MenuBarController.setRecordingIndicator(_:)` already exists from Plan 1 — Plan 6 finally calls it. Library schema (Plan 4) already has `media_type` and `duration_ms` columns ready for video rows.

**Scope deferred to later plans:**

- **Trim handles + AVAssetExportSession** — Plan 7 adds the post-record trim UI
- **Multi-monitor full-screen recording** — v0.6.0 records the primary display only when "full-screen" is chosen; multi-display recording orchestration is explicitly out of v1 per spec
- **Webcam picture-in-picture** — explicitly out of v1
- **GIF export** — explicitly out of v1
- **Pause/resume during recording** — out of scope; Stop is the only way to end
- **Per-frame cursor pixel-accurate compositing using Core Image + Metal** — v0.6.0 uses CGContext per-frame which is fine at our overlay sizes (small ring + small text); migrate if profiling shows a real bottleneck
- **Recording quality presets in Settings** — fps/codec/bitrate use sensible hard-coded defaults for v0.6.0; Plan 9 settings completion adds user-configurable presets

---

## File Structure

```
JuiceScreen/
├── Capture/
│   └── Video/
│       ├── Model/
│       │   ├── VideoRecordingMode.swift       NEW — enum: fullScreen / region(CGRect on screen)
│       │   ├── VideoRecordingOptions.swift    NEW — fps/codec defaults + audio + overlay toggles
│       │   └── VideoRecordingError.swift      NEW — Error enum
│       ├── Recording/
│       │   ├── VideoRecorder.swift            NEW — protocol
│       │   ├── VideoRecorderLive.swift        NEW — SCStream + AVAssetWriter impl
│       │   └── FakeVideoRecorder.swift        NEW — test double
│       ├── Audio/
│       │   └── MicrophoneCapture.swift        NEW — AVCaptureSession wrapper for mic
│       ├── Overlay/
│       │   ├── CursorTracker.swift            NEW — 50Hz NSEvent.mouseLocation polling
│       │   ├── CursorHighlightRenderer.swift  NEW — draws ring on CGContext at cursor point
│       │   ├── ClickTracker.swift             NEW — NSEvent global monitor for mouseDown (opt-in)
│       │   ├── ClickPulseRenderer.swift       NEW — draws expanding pulse ring on CGContext
│       │   ├── KeystrokeTracker.swift         NEW — NSEvent global monitor for keyDown (opt-in)
│       │   └── KeystrokeOverlayRenderer.swift NEW — draws last 3 keystrokes in corner
│       ├── Composition/
│       │   └── FrameCompositor.swift          NEW — applies enabled overlays to a CGContext per frame
│       ├── Output/
│       │   └── VideoFileWriter.swift          NEW — AVAssetWriter wrapper, append video + audio samples
│       ├── UI/
│       │   ├── RecordingControlBarView.swift  NEW — SwiftUI: Stop button + duration + mic mute toggle
│       │   └── RecordingControlWindow.swift   NEW — borderless always-on-top NSWindow, draggable
│       └── Session/
│           ├── RecordingSession.swift         NEW — coordinator: wires recorder + UI + lifecycle
│           └── RecordingSessionManager.swift  NEW — singleton, holds active session, exposes stop()
├── App/
│   └── AppDelegate.swift                      MODIFY — replace todoLog("recordScreen") with recording flow
├── MenuBar/
│   └── HotkeyService.swift                    (no change — `stopRecording` HotkeyAction already exists)
└── MainWindow/
    └── Settings/
        └── RecordingTab.swift                 MODIFY — replace placeholder with toggles for cursor/click/keystroke + mic default
```

```
JuiceScreenTests/
├── VideoRecordingOptionsTests.swift            NEW
├── VideoRecordingModeTests.swift               NEW
├── CursorTrackerTests.swift                    NEW
├── KeystrokeTrackerTests.swift                 NEW
├── FrameCompositorTests.swift                  NEW (renders to fixture CGContext, asserts pixel)
├── FakeVideoRecorderTests.swift                NEW
└── RecordingSessionTests.swift                 NEW
```

```
VERSION                                         MODIFY — bump to 0.6.0 (Task 22)
project.yml                                     MODIFY — MARKETING_VERSION 0.6.0 (Task 22)
docs/superpowers/specs/2026-05-04-juicescreen-design.md  MODIFY — implementation status (Task 23)
```

---

## Task 1: `VideoRecordingMode` enum + tests

**Files:**
- Create: `JuiceScreen/Capture/Video/Model/VideoRecordingMode.swift`
- Create: `JuiceScreenTests/VideoRecordingModeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("VideoRecordingMode")
struct VideoRecordingModeTests {

    @Test("Full screen mode has no associated rect")
    func fullScreen() {
        let mode = VideoRecordingMode.fullScreen
        if case .fullScreen = mode {
            // ok
        } else {
            Issue.record("expected .fullScreen")
        }
    }

    @Test("Region mode carries a CGRect in screen coordinates")
    func regionStoresRect() {
        let rect = CGRect(x: 100, y: 200, width: 640, height: 480)
        let mode = VideoRecordingMode.region(rect)
        if case .region(let r) = mode {
            #expect(r == rect)
        } else {
            Issue.record("expected .region")
        }
    }

    @Test("Equatable: same case + same rect == equal")
    func equality() {
        let a = VideoRecordingMode.region(CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = VideoRecordingMode.region(CGRect(x: 0, y: 0, width: 100, height: 100))
        let c = VideoRecordingMode.region(CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(a == b)
        #expect(a != c)
        #expect(VideoRecordingMode.fullScreen == VideoRecordingMode.fullScreen)
        #expect(VideoRecordingMode.fullScreen != a)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/VideoRecordingModeTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `VideoRecordingMode.swift`**

```swift
import CoreGraphics

/// What kind of region a video recording covers.
public enum VideoRecordingMode: Equatable, Sendable {
    /// Full primary display.
    case fullScreen

    /// A rectangle in global screen coordinates (top-left origin, AppKit convention),
    /// matching what `RegionPickerController.pickRegion()` returns.
    case region(CGRect)
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/VideoRecordingModeTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Video/Model/VideoRecordingMode.swift JuiceScreenTests/VideoRecordingModeTests.swift
git commit -m "feat(video): VideoRecordingMode enum (fullScreen / region(CGRect))"
```

---

## Task 2: `VideoRecordingOptions` value type + tests

**Files:**
- Create: `JuiceScreen/Capture/Video/Model/VideoRecordingOptions.swift`
- Create: `JuiceScreenTests/VideoRecordingOptionsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("VideoRecordingOptions")
struct VideoRecordingOptionsTests {

    @Test("Defaults match spec: 60fps + system audio on + cursor ring on + click pulse off + keystrokes off")
    func defaults() {
        let o = VideoRecordingOptions.defaults
        #expect(o.targetFps == 60)
        #expect(o.captureSystemAudio == true)
        #expect(o.captureMicrophone == false)
        #expect(o.showCursorHighlight == true)
        #expect(o.showClickPulse == false)
        #expect(o.showKeystrokes == false)
    }

    @Test("Equatable")
    func equatable() {
        var a = VideoRecordingOptions.defaults
        var b = VideoRecordingOptions.defaults
        #expect(a == b)
        a.captureMicrophone = true
        #expect(a != b)
        b.captureMicrophone = true
        #expect(a == b)
    }

    @Test("requiresInputMonitoring is true iff click pulse OR keystrokes are enabled")
    func requiresInputMonitoring() {
        var o = VideoRecordingOptions.defaults
        #expect(o.requiresInputMonitoring == false)
        o.showClickPulse = true
        #expect(o.requiresInputMonitoring == true)
        o.showClickPulse = false
        o.showKeystrokes = true
        #expect(o.requiresInputMonitoring == true)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/VideoRecordingOptionsTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `VideoRecordingOptions.swift`**

```swift
import Foundation

public struct VideoRecordingOptions: Equatable, Sendable {

    public var targetFps: Int
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool
    public var showCursorHighlight: Bool
    public var showClickPulse: Bool
    public var showKeystrokes: Bool

    public init(
        targetFps: Int,
        captureSystemAudio: Bool,
        captureMicrophone: Bool,
        showCursorHighlight: Bool,
        showClickPulse: Bool,
        showKeystrokes: Bool
    ) {
        self.targetFps = targetFps
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.showCursorHighlight = showCursorHighlight
        self.showClickPulse = showClickPulse
        self.showKeystrokes = showKeystrokes
    }

    public static let defaults = VideoRecordingOptions(
        targetFps: 60,
        captureSystemAudio: true,
        captureMicrophone: false,
        showCursorHighlight: true,
        showClickPulse: false,
        showKeystrokes: false
    )

    /// True if the user has enabled any feature that requires Input Monitoring TCC.
    public var requiresInputMonitoring: Bool {
        showClickPulse || showKeystrokes
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/VideoRecordingOptionsTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Video/Model/VideoRecordingOptions.swift JuiceScreenTests/VideoRecordingOptionsTests.swift
git commit -m "feat(video): VideoRecordingOptions (60fps default, sys audio on, overlays opt-in)"
```

---

## Task 3: `VideoRecordingError` enum

**Files:**
- Create: `JuiceScreen/Capture/Video/Model/VideoRecordingError.swift`

(No tests — pure error enum.)

- [ ] **Step 1: Implement `VideoRecordingError.swift`**

```swift
import Foundation

public enum VideoRecordingError: Error, Equatable {
    case missingScreenRecordingPermission
    case missingMicrophonePermission
    case missingInputMonitoringPermission
    case userCancelled
    case noDisplaysAvailable
    case streamConfigurationFailed(String)
    case writerSetupFailed(String)
    case streamFailed(String)
    case writeFailed(String)
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
git add JuiceScreen/Capture/Video/Model/VideoRecordingError.swift
git commit -m "feat(video): VideoRecordingError enum"
```

---

## Task 4: `CursorTracker` (50Hz `NSEvent.mouseLocation()` polling) + tests

**Files:**
- Create: `JuiceScreen/Capture/Video/Overlay/CursorTracker.swift`
- Create: `JuiceScreenTests/CursorTrackerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("CursorTracker")
struct CursorTrackerTests {

    @Test("Initial currentLocation is .zero")
    func initialLocation() {
        let tracker = CursorTracker()
        #expect(tracker.currentLocation == .zero)
    }

    @Test("Manually-injected location updates currentLocation")
    func manualUpdate() {
        let tracker = CursorTracker()
        tracker._setLocationForTesting(CGPoint(x: 100, y: 200))
        #expect(tracker.currentLocation == CGPoint(x: 100, y: 200))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CursorTrackerTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `CursorTracker.swift`**

```swift
import AppKit
import Foundation

/// Polls `NSEvent.mouseLocation()` at 50Hz on a private timer queue.
/// Public API requires no extra TCC permission. Used by `FrameCompositor`
/// to draw the cursor highlight ring onto recorded frames.
public final class CursorTracker: @unchecked Sendable {

    private let lock = NSLock()
    private var location: CGPoint = .zero
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.cursor-tracker")

    public init() {}

    public func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))   // 50Hz
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            self.lock.lock()
            self.location = CGPoint(x: loc.x, y: loc.y)
            self.lock.unlock()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public var currentLocation: CGPoint {
        lock.lock(); defer { lock.unlock() }
        return location
    }

    /// Test-only injection seam.
    public func _setLocationForTesting(_ point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        location = point
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CursorTrackerTests 2>&1 | tail -10
```

Expected: 2/2 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Video/Overlay/CursorTracker.swift JuiceScreenTests/CursorTrackerTests.swift
git commit -m "feat(video): CursorTracker — 50Hz NSEvent.mouseLocation polling"
```

---

## Task 5: `CursorHighlightRenderer` (pure CGContext draw)

**Files:**
- Create: `JuiceScreen/Capture/Video/Overlay/CursorHighlightRenderer.swift`

(No automated test — visual rendering. Smoke-tested via `FrameCompositor` test in Task 11.)

- [ ] **Step 1: Implement `CursorHighlightRenderer.swift`**

```swift
import AppKit
import CoreGraphics

/// Renders a translucent yellow ring around the cursor position into a `CGContext`.
/// Pure function — no state.
public enum CursorHighlightRenderer {

    public static let ringDiameter: CGFloat = 28
    public static let ringStrokeWidth: CGFloat = 3
    public static let ringColor = NSColor.systemYellow.withAlphaComponent(0.85)

    /// Draws a ring centered at `point` (in CGContext coordinates — caller is responsible
    /// for converting from screen coordinates to frame-pixel coordinates).
    public static func draw(at point: CGPoint, in ctx: CGContext) {
        let radius = ringDiameter / 2
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: ringDiameter,
            height: ringDiameter
        )
        ctx.saveGState()
        ctx.setStrokeColor(ringColor.cgColor)
        ctx.setLineWidth(ringStrokeWidth)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
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
git add JuiceScreen/Capture/Video/Overlay/CursorHighlightRenderer.swift
git commit -m "feat(video): CursorHighlightRenderer — yellow translucent ring at cursor point"
```

---

## Task 6: `ClickTracker` + `ClickPulseRenderer`

**Files:**
- Create: `JuiceScreen/Capture/Video/Overlay/ClickTracker.swift`
- Create: `JuiceScreen/Capture/Video/Overlay/ClickPulseRenderer.swift`

(No automated tests — `NSEvent.addGlobalMonitorForEvents` requires Input Monitoring TCC and a runloop. Smoke-tested manually.)

- [ ] **Step 1: Implement `ClickTracker.swift`**

```swift
import AppKit
import Foundation

/// Tracks mouse-down events globally and exposes recent clicks for the renderer.
/// **Requires Input Monitoring permission.** Callers MUST verify the permission
/// is granted (via `PermissionsService`) before calling `start()`.
public final class ClickTracker: @unchecked Sendable {

    public struct Click: Equatable, Sendable {
        public let location: CGPoint
        public let timestamp: Date
    }

    private let lock = NSLock()
    private var recent: [Click] = []
    private var monitor: Any?
    private let log = AppLog.logger(category: "ClickTracker")

    /// How long a click stays in the renderable history. Animations fade out within this window.
    public static let clickLifetime: TimeInterval = 0.6

    public init() {}

    public func start() {
        stop()
        let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            let click = Click(location: CGPoint(x: loc.x, y: loc.y), timestamp: Date())
            self.lock.lock()
            self.recent.append(click)
            self.purgeOldLocked()
            self.lock.unlock()
        }
        monitor = m
        if monitor == nil {
            log.error("Failed to install click monitor (Input Monitoring not granted?)")
        }
    }

    public func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    /// Returns clicks newer than `clickLifetime` ago.
    public func recentClicks(now: Date = Date()) -> [Click] {
        lock.lock(); defer { lock.unlock() }
        purgeOldLocked(now: now)
        return recent
    }

    private func purgeOldLocked(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.clickLifetime)
        recent.removeAll { $0.timestamp < cutoff }
    }

    /// Test-only seam.
    public func _injectClickForTesting(_ click: Click) {
        lock.lock(); defer { lock.unlock() }
        recent.append(click)
    }
}
```

- [ ] **Step 2: Implement `ClickPulseRenderer.swift`**

```swift
import AppKit
import CoreGraphics

/// Renders an expanding ring at each recent click location, fading out over `ClickTracker.clickLifetime`.
public enum ClickPulseRenderer {

    public static let maxRadius: CGFloat = 36
    public static let strokeWidth: CGFloat = 4
    public static let pulseColor = NSColor.systemBlue

    public static func draw(clicks: [ClickTracker.Click], in ctx: CGContext, now: Date = Date()) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        for click in clicks {
            let age = now.timeIntervalSince(click.timestamp)
            let progress = min(max(age / ClickTracker.clickLifetime, 0), 1)
            let radius = maxRadius * CGFloat(progress)
            let alpha = (1.0 - CGFloat(progress)) * 0.85
            let rect = CGRect(
                x: click.location.x - radius,
                y: click.location.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            ctx.setStrokeColor(pulseColor.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(strokeWidth)
            ctx.strokeEllipse(in: rect)
        }
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
git add JuiceScreen/Capture/Video/Overlay/ClickTracker.swift JuiceScreen/Capture/Video/Overlay/ClickPulseRenderer.swift
git commit -m "feat(video): ClickTracker + ClickPulseRenderer (Input Monitoring opt-in)"
```

---

## Task 7: `KeystrokeTracker` + `KeystrokeOverlayRenderer` + tests

**Files:**
- Create: `JuiceScreen/Capture/Video/Overlay/KeystrokeTracker.swift`
- Create: `JuiceScreen/Capture/Video/Overlay/KeystrokeOverlayRenderer.swift`
- Create: `JuiceScreenTests/KeystrokeTrackerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("KeystrokeTracker")
struct KeystrokeTrackerTests {

    @Test("Initial recent keys is empty")
    func initial() {
        let tracker = KeystrokeTracker()
        #expect(tracker.recentKeys().isEmpty)
    }

    @Test("Injected keys appear in recentKeys, oldest first, capped at maxKeys")
    func injectAndCap() {
        let tracker = KeystrokeTracker(maxKeys: 3)
        let now = Date()
        tracker._injectKeyForTesting(.init(label: "a", timestamp: now.addingTimeInterval(-3)))
        tracker._injectKeyForTesting(.init(label: "b", timestamp: now.addingTimeInterval(-2)))
        tracker._injectKeyForTesting(.init(label: "c", timestamp: now.addingTimeInterval(-1)))
        tracker._injectKeyForTesting(.init(label: "d", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["b", "c", "d"])
    }

    @Test("Keys older than lifetime are pruned")
    func ttl() {
        let tracker = KeystrokeTracker(maxKeys: 5)
        let now = Date()
        tracker._injectKeyForTesting(.init(label: "old", timestamp: now.addingTimeInterval(-10)))
        tracker._injectKeyForTesting(.init(label: "new", timestamp: now))

        let keys = tracker.recentKeys(now: now)
        #expect(keys.map { $0.label } == ["new"])
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/KeystrokeTrackerTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `KeystrokeTracker.swift`**

```swift
import AppKit
import Foundation

public final class KeystrokeTracker: @unchecked Sendable {

    public struct Key: Equatable, Sendable {
        public var label: String       // human-readable: "A", "↩", "⌘C"
        public var timestamp: Date

        public init(label: String, timestamp: Date) {
            self.label = label
            self.timestamp = timestamp
        }
    }

    public static let lifetime: TimeInterval = 2.5

    private let lock = NSLock()
    private var keys: [Key] = []
    private let maxKeys: Int
    private var monitor: Any?
    private let log = AppLog.logger(category: "KeystrokeTracker")

    public init(maxKeys: Int = 3) {
        self.maxKeys = maxKeys
    }

    public func start() {
        stop()
        let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            let label = Self.label(for: event)
            let key = Key(label: label, timestamp: Date())
            self.lock.lock()
            self.keys.append(key)
            self.purgeLocked()
            self.lock.unlock()
        }
        monitor = m
        if monitor == nil {
            log.error("Failed to install keystroke monitor (Input Monitoring not granted?)")
        }
    }

    public func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    public func recentKeys(now: Date = Date()) -> [Key] {
        lock.lock(); defer { lock.unlock() }
        purgeLocked(now: now)
        return keys
    }

    public func _injectKeyForTesting(_ key: Key) {
        lock.lock(); defer { lock.unlock() }
        keys.append(key)
    }

    // MARK: - Helpers

    private func purgeLocked(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.lifetime)
        keys.removeAll { $0.timestamp < cutoff }
        if keys.count > maxKeys {
            keys.removeFirst(keys.count - maxKeys)
        }
    }

    private static func label(for event: NSEvent) -> String {
        var prefix = ""
        if event.modifierFlags.contains(.control) { prefix += "⌃" }
        if event.modifierFlags.contains(.option)  { prefix += "⌥" }
        if event.modifierFlags.contains(.shift)   { prefix += "⇧" }
        if event.modifierFlags.contains(.command) { prefix += "⌘" }
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        return prefix + chars
    }
}
```

- [ ] **Step 4: Implement `KeystrokeOverlayRenderer.swift`**

```swift
import AppKit
import CoreGraphics

/// Draws the most recent keystrokes as monochrome chips in the bottom-right corner of the frame.
public enum KeystrokeOverlayRenderer {

    public static let chipHeight: CGFloat = 28
    public static let chipPadding: CGFloat = 8
    public static let chipGap: CGFloat = 6
    public static let cornerInset: CGFloat = 24
    public static let fontSize: CGFloat = 16

    public static func draw(keys: [KeystrokeTracker.Key], frameSize: CGSize, in ctx: CGContext) {
        guard !keys.isEmpty else { return }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        var x = frameSize.width - cornerInset
        let y = cornerInset

        ctx.saveGState()
        defer { ctx.restoreGState() }

        for key in keys.reversed() {
            let attributedString = NSAttributedString(string: key.label, attributes: textAttributes)
            let textSize = attributedString.size()
            let chipWidth = textSize.width + chipPadding * 2
            let chipRect = CGRect(x: x - chipWidth, y: y, width: chipWidth, height: chipHeight)

            ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            let path = CGPath(roundedRect: chipRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()

            // Draw the text via NSGraphicsContext bridge so we get attributed-string drawing
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            attributedString.draw(at: CGPoint(x: chipRect.minX + chipPadding,
                                              y: chipRect.minY + (chipHeight - textSize.height) / 2))
            NSGraphicsContext.restoreGraphicsState()

            x = chipRect.minX - chipGap
        }
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/KeystrokeTrackerTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Capture/Video/Overlay/KeystrokeTracker.swift JuiceScreen/Capture/Video/Overlay/KeystrokeOverlayRenderer.swift JuiceScreenTests/KeystrokeTrackerTests.swift
git commit -m "feat(video): KeystrokeTracker + KeystrokeOverlayRenderer (last-3 chips, bottom-right)"
```

---

## Task 8: `FrameCompositor` + tests

**Files:**
- Create: `JuiceScreen/Capture/Video/Composition/FrameCompositor.swift`
- Create: `JuiceScreenTests/FrameCompositorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AppKit
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FrameCompositor")
struct FrameCompositorTests {

    /// Draws into a fresh context and returns the resulting CGImage.
    private func renderToFixture(_ block: (CGContext, CGSize) -> Void, size: CGSize = CGSize(width: 200, height: 200)) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        // Fill with a known background
        ctx.setFillColor(NSColor.darkGray.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        block(ctx, size)
        return ctx.makeImage()
    }

    @Test("Empty options: composer draws no overlays")
    func emptyOptions() {
        let cursor = CursorTracker()
        let click = ClickTracker()
        let keys = KeystrokeTracker()
        cursor._setLocationForTesting(CGPoint(x: 100, y: 100))

        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = false
        options.showClickPulse = false
        options.showKeystrokes = false

        let composer = FrameCompositor(cursorTracker: cursor, clickTracker: click, keystrokeTracker: keys)

        let img = renderToFixture { ctx, size in
            composer.draw(options: options, frameSize: size, screenOrigin: .zero, in: ctx)
        }
        #expect(img != nil)
        // Pixel at center should still be the dark-gray background (no cursor ring drawn)
        // Spot-check by using NSBitmapImageRep
        let rep = NSBitmapImageRep(cgImage: img!)
        let color = rep.colorAt(x: 100, y: 100)
        #expect(color != nil)
        // dark gray rgb(85, 85, 85) approximately — alpha may be 1.0
        #expect((color?.redComponent ?? 1.0) < 0.5)
    }

    @Test("Cursor highlight enabled: ring is drawn around cursor location (in screen coords)")
    func cursorRing() {
        let cursor = CursorTracker()
        let click = ClickTracker()
        let keys = KeystrokeTracker()
        // Cursor is at screen point (100, 100); screenOrigin is (0,0) so frame point is also (100,100)
        cursor._setLocationForTesting(CGPoint(x: 100, y: 100))

        var options = VideoRecordingOptions.defaults
        options.showCursorHighlight = true
        options.showClickPulse = false
        options.showKeystrokes = false

        let composer = FrameCompositor(cursorTracker: cursor, clickTracker: click, keystrokeTracker: keys)

        let img = renderToFixture { ctx, size in
            composer.draw(options: options, frameSize: size, screenOrigin: .zero, in: ctx)
        }
        #expect(img != nil)
        // Check that a pixel on the ring perimeter shifted toward yellow
        let rep = NSBitmapImageRep(cgImage: img!)
        // 14pt right of cursor center is on the ring (radius 14, stroke 3)
        let onRing = rep.colorAt(x: 114, y: 100)
        #expect(onRing != nil)
        let r = onRing!.redComponent
        let g = onRing!.greenComponent
        // yellow → high R + high G + low B
        #expect(r > 0.6 && g > 0.6)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FrameCompositorTests 2>&1 | tail -8
```

Expected: compile failure (`FrameCompositor` undefined).

- [ ] **Step 3: Implement `FrameCompositor.swift`**

```swift
import AppKit
import CoreGraphics
import Foundation

/// Draws all enabled overlays onto a frame's CGContext. Pure per-frame composer:
/// reads from the trackers (which run on their own queues) and renders.
public final class FrameCompositor: @unchecked Sendable {

    private let cursorTracker: CursorTracker
    private let clickTracker: ClickTracker
    private let keystrokeTracker: KeystrokeTracker

    public init(cursorTracker: CursorTracker, clickTracker: ClickTracker, keystrokeTracker: KeystrokeTracker) {
        self.cursorTracker = cursorTracker
        self.clickTracker = clickTracker
        self.keystrokeTracker = keystrokeTracker
    }

    /// Draws enabled overlays onto `ctx`. `frameSize` is the pixel size of the frame.
    /// `screenOrigin` is the top-left of the recorded region in global screen coordinates;
    /// pass `.zero` for a full-screen recording starting at the primary display origin.
    public func draw(
        options: VideoRecordingOptions,
        frameSize: CGSize,
        screenOrigin: CGPoint,
        in ctx: CGContext
    ) {
        if options.showCursorHighlight {
            let screenLoc = cursorTracker.currentLocation
            let frameLoc = CGPoint(x: screenLoc.x - screenOrigin.x, y: screenLoc.y - screenOrigin.y)
            // Skip if outside frame
            if frameLoc.x >= 0, frameLoc.y >= 0,
               frameLoc.x <= frameSize.width, frameLoc.y <= frameSize.height {
                CursorHighlightRenderer.draw(at: frameLoc, in: ctx)
            }
        }

        if options.showClickPulse {
            let translated = clickTracker.recentClicks().map { c in
                ClickTracker.Click(
                    location: CGPoint(x: c.location.x - screenOrigin.x, y: c.location.y - screenOrigin.y),
                    timestamp: c.timestamp
                )
            }
            ClickPulseRenderer.draw(clicks: translated, in: ctx)
        }

        if options.showKeystrokes {
            KeystrokeOverlayRenderer.draw(keys: keystrokeTracker.recentKeys(), frameSize: frameSize, in: ctx)
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FrameCompositorTests 2>&1 | tail -10
```

Expected: 2/2 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Video/Composition/FrameCompositor.swift JuiceScreenTests/FrameCompositorTests.swift
git commit -m "feat(video): FrameCompositor — applies enabled overlays per-frame on CGContext"
```

---

## Task 9: `MicrophoneCapture` (AVCaptureSession wrapper)

**Files:**
- Create: `JuiceScreen/Capture/Video/Audio/MicrophoneCapture.swift`

(No automated tests — needs a real audio device. Smoke-tested via the recording flow in Task 22.)

- [ ] **Step 1: Implement `MicrophoneCapture.swift`**

```swift
import AVFoundation
import Foundation

/// Captures microphone audio via `AVCaptureSession` and forwards CMSampleBuffers
/// to a delegate. Started/stopped by the recorder when `captureMicrophone` is enabled.
public final class MicrophoneCapture: NSObject, @unchecked Sendable {

    public typealias SampleHandler = (CMSampleBuffer) -> Void

    private let session: AVCaptureSession
    private let output: AVCaptureAudioDataOutput
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.mic")
    private var handler: SampleHandler?
    private let log = AppLog.logger(category: "MicrophoneCapture")

    public override init() {
        self.session = AVCaptureSession()
        self.output = AVCaptureAudioDataOutput()
        super.init()
    }

    public func start(handler: @escaping SampleHandler) throws {
        self.handler = handler

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw VideoRecordingError.streamConfigurationFailed("No default audio input device")
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw VideoRecordingError.streamConfigurationFailed("\(error)")
        }

        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() {
        session.stopRunning()
        handler = nil
    }
}

extension MicrophoneCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        handler?(sampleBuffer)
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
git add JuiceScreen/Capture/Video/Audio/MicrophoneCapture.swift
git commit -m "feat(video): MicrophoneCapture (AVCaptureSession + AVCaptureAudioDataOutput)"
```

---

## Task 10: `VideoFileWriter` (AVAssetWriter wrapper)

**Files:**
- Create: `JuiceScreen/Capture/Video/Output/VideoFileWriter.swift`

(No automated tests — wraps AVAssetWriter which needs real CMSampleBuffers.)

- [ ] **Step 1: Implement `VideoFileWriter.swift`**

```swift
import AVFoundation
import CoreMedia
import Foundation

/// Wraps `AVAssetWriter` for H.264 MP4 video + AAC audio output.
/// Created once per recording. Caller appends sample buffers via the typed methods,
/// then calls `finish()` to flush + close the file.
public final class VideoFileWriter: @unchecked Sendable {

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let videoAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let log = AppLog.logger(category: "VideoFileWriter")

    private var sessionStarted = false
    private let queue = DispatchQueue(label: "com.bks-lab.juicescreen.video-writer")

    public init(outputURL: URL, frameSize: CGSize, includesAudio: Bool) throws {
        do {
            self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw VideoRecordingError.writerSetupFailed("\(error)")
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(frameSize.width),
            AVVideoHeightKey: Int(frameSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        self.videoInput.expectsMediaDataInRealTime = true

        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(frameSize.width),
            kCVPixelBufferHeightKey as String: Int(frameSize.height)
        ]
        self.videoAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: bufferAttrs
        )
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        if includesAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 192_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) { writer.add(audioInput) }
            self.audioInput = audioInput
        } else {
            self.audioInput = nil
        }

        guard writer.startWriting() else {
            throw VideoRecordingError.writerSetupFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    public func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        if !sessionStarted {
            writer.startSession(atSourceTime: presentationTime)
            sessionStarted = true
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        if !videoAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            log.error("Failed to append pixel buffer at \(presentationTime.seconds)")
        }
    }

    public func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted else { return }
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    public func finish() async throws -> CMTime {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error {
            throw VideoRecordingError.writeFailed("\(error)")
        }
        // Final duration = last sample time minus session start; AVAssetWriter exposes via tracks
        return writer.movieFragmentInterval == .invalid ? .zero : writer.movieFragmentInterval
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
git add JuiceScreen/Capture/Video/Output/VideoFileWriter.swift
git commit -m "feat(video): VideoFileWriter (AVAssetWriter H.264 MP4 + optional AAC audio)"
```

---

## Task 11: `VideoRecorder` protocol + `FakeVideoRecorder` + tests

**Files:**
- Create: `JuiceScreen/Capture/Video/Recording/VideoRecorder.swift`
- Create: `JuiceScreen/Capture/Video/Recording/FakeVideoRecorder.swift`
- Create: `JuiceScreenTests/FakeVideoRecorderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeVideoRecorder")
@MainActor
struct FakeVideoRecorderTests {

    @Test("Idle by default")
    func idle() {
        let r = FakeVideoRecorder()
        #expect(r.isRecording == false)
    }

    @Test("start switches to recording; stop returns the configured outcome")
    func startStop() async throws {
        let r = FakeVideoRecorder()
        let url = URL(fileURLWithPath: "/tmp/fake.mp4")
        let resultRecord = CaptureRecord(
            id: UUID(), fileURL: url, captureType: .fullScreen,
            capturedAt: Date(), pixelWidth: 1920, pixelHeight: 1080, sourceApp: nil
        )
        r.stopOutcome = .success(resultRecord)

        try await r.start(mode: .fullScreen, options: .defaults, outputURL: url)
        #expect(r.isRecording == true)

        let returned = try await r.stop()
        #expect(r.isRecording == false)
        #expect(returned.id == resultRecord.id)
    }

    @Test("stop throws the configured error")
    func stopError() async {
        let r = FakeVideoRecorder()
        try? await r.start(mode: .fullScreen, options: .defaults, outputURL: URL(fileURLWithPath: "/tmp/x.mp4"))
        r.stopOutcome = .failure(.streamFailed("boom"))
        await #expect(throws: VideoRecordingError.self) {
            _ = try await r.stop()
        }
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeVideoRecorderTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `VideoRecorder.swift`**

```swift
import Foundation

@MainActor
public protocol VideoRecorder: AnyObject {
    var isRecording: Bool { get }
    var elapsed: TimeInterval { get }

    func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws
    func stop() async throws -> CaptureRecord
    func toggleMicrophoneMute()
}
```

- [ ] **Step 4: Implement `FakeVideoRecorder.swift`**

```swift
import Foundation

@MainActor
public final class FakeVideoRecorder: VideoRecorder {

    public typealias Outcome = Result<CaptureRecord, VideoRecordingError>

    public private(set) var isRecording: Bool = false
    public var elapsed: TimeInterval = 0
    public var stopOutcome: Outcome = .failure(.streamFailed("not configured"))
    public private(set) var lastMode: VideoRecordingMode?
    public private(set) var lastOptions: VideoRecordingOptions?

    public init() {}

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        lastMode = mode
        lastOptions = options
        isRecording = true
    }

    public func stop() async throws -> CaptureRecord {
        isRecording = false
        switch stopOutcome {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    public func toggleMicrophoneMute() {
        // no-op for tests; can be observed via lastOptions in future
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeVideoRecorderTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Capture/Video/Recording/VideoRecorder.swift JuiceScreen/Capture/Video/Recording/FakeVideoRecorder.swift JuiceScreenTests/FakeVideoRecorderTests.swift
git commit -m "feat(video): VideoRecorder protocol + FakeVideoRecorder test double"
```

---

## Task 12: `VideoRecorderLive` (SCStream + AVAssetWriter integration)

**Files:**
- Create: `JuiceScreen/Capture/Video/Recording/VideoRecorderLive.swift`

(No automated tests — exercises real ScreenCaptureKit + AVAssetWriter. Manual smoke test in Task 22.)

- [ ] **Step 1: Implement `VideoRecorderLive.swift`**

```swift
import AVFoundation
import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
public final class VideoRecorderLive: NSObject, VideoRecorder {

    // MARK: - Public state

    public private(set) var isRecording: Bool = false
    public var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    // MARK: - Dependencies

    private let permissions: PermissionsService
    private let cursorTracker = CursorTracker()
    private let clickTracker = ClickTracker()
    private let keystrokeTracker = KeystrokeTracker()
    private lazy var compositor = FrameCompositor(
        cursorTracker: cursorTracker,
        clickTracker: clickTracker,
        keystrokeTracker: keystrokeTracker
    )
    private let microphone = MicrophoneCapture()
    private let log = AppLog.logger(category: "VideoRecorderLive")

    // MARK: - Recording state

    private var stream: SCStream?
    private var writer: VideoFileWriter?
    private var streamOutput: StreamOutput?
    private var startedAt: Date?
    private var options: VideoRecordingOptions = .defaults
    private var screenOrigin: CGPoint = .zero
    private var outputURL: URL?
    private var captureMode: VideoRecordingMode = .fullScreen

    public init(permissions: PermissionsService) {
        self.permissions = permissions
    }

    // MARK: - VideoRecorder

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        guard !isRecording else { return }

        self.options = options
        self.outputURL = outputURL
        self.captureMode = mode

        // Permissions
        guard permissions.status(for: .screenRecording) == .granted else {
            throw VideoRecordingError.missingScreenRecordingPermission
        }
        if options.captureMicrophone {
            let mic = await permissions.request(.microphone)
            if mic != .granted { throw VideoRecordingError.missingMicrophonePermission }
        }
        if options.requiresInputMonitoring {
            let im = await permissions.request(.inputMonitoring)
            if im != .granted { throw VideoRecordingError.missingInputMonitoringPermission }
        }

        // SCDisplay + filter + region rect
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw VideoRecordingError.noDisplaysAvailable
        }

        let pixelDensity = 2
        let regionInPoints: CGRect
        switch mode {
        case .fullScreen:
            regionInPoints = CGRect(x: 0, y: 0, width: display.width, height: display.height)
            screenOrigin = .zero
        case .region(let r):
            regionInPoints = r
            screenOrigin = r.origin
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.width = Int(regionInPoints.width) * pixelDensity
        cfg.height = Int(regionInPoints.height) * pixelDensity
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: Int32(options.targetFps))
        cfg.queueDepth = 6
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false   // we composite our own ring
        cfg.capturesAudio = options.captureSystemAudio
        cfg.sourceRect = regionInPoints

        // Writer
        let frameSize = CGSize(width: cfg.width, height: cfg.height)
        let writer = try VideoFileWriter(
            outputURL: outputURL,
            frameSize: frameSize,
            includesAudio: options.captureSystemAudio || options.captureMicrophone
        )
        self.writer = writer

        // Stream + output
        let output = StreamOutput(
            writer: writer,
            compositor: compositor,
            options: options,
            screenOrigin: screenOrigin,
            frameSize: frameSize,
            log: log
        )
        self.streamOutput = output
        let stream = SCStream(filter: filter, configuration: cfg, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        if options.captureSystemAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        }
        self.stream = stream

        // Trackers
        cursorTracker.start()
        if options.showClickPulse { clickTracker.start() }
        if options.showKeystrokes { keystrokeTracker.start() }

        // Microphone
        if options.captureMicrophone {
            try microphone.start { [weak self] sb in
                self?.streamOutput?.handleMicrophoneSampleBuffer(sb)
            }
        }

        try await stream.startCapture()
        startedAt = Date()
        isRecording = true
        log.info("Recording started — frame \(cfg.width)x\(cfg.height) @ \(options.targetFps)fps")
    }

    public func stop() async throws -> CaptureRecord {
        guard isRecording, let stream, let writer, let outputURL else {
            throw VideoRecordingError.streamFailed("stop() called without active recording")
        }

        try await stream.stopCapture()
        cursorTracker.stop()
        clickTracker.stop()
        keystrokeTracker.stop()
        if options.captureMicrophone { microphone.stop() }

        _ = try await writer.finish()

        let duration = elapsed
        let pw: Int
        let ph: Int
        switch captureMode {
        case .fullScreen:
            pw = streamOutput?.frameSize.width.intValue ?? 0
            ph = streamOutput?.frameSize.height.intValue ?? 0
        case .region(let r):
            pw = Int(r.width * 2)
            ph = Int(r.height * 2)
        }

        let record = CaptureRecord(
            id: UUID(),
            fileURL: outputURL,
            captureType: .fullScreen,   // semantics: video; library tags it via mediaType in CaptureRow
            capturedAt: startedAt ?? Date(),
            pixelWidth: pw,
            pixelHeight: ph,
            sourceApp: nil
        )
        // We can't fully express duration in CaptureRecord (it has no durationMs);
        // CaptureLibraryRecorder will include duration via fileSize and sidecar later.
        log.info("Recording stopped — duration \(duration)s, file \(outputURL.path)")

        // Reset
        self.stream = nil
        self.writer = nil
        self.streamOutput = nil
        self.startedAt = nil
        self.outputURL = nil
        self.isRecording = false

        return record
    }

    public func toggleMicrophoneMute() {
        // For v0.6.0 we treat mic toggle at start time only; mid-recording mute is a v1.1 polish.
    }
}

// MARK: - Stream output

private final class StreamOutput: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {

    let queue = DispatchQueue(label: "com.bks-lab.juicescreen.video-output")
    let writer: VideoFileWriter
    let compositor: FrameCompositor
    let options: VideoRecordingOptions
    let screenOrigin: CGPoint
    let frameSize: CGSize
    let log: Logger

    init(writer: VideoFileWriter, compositor: FrameCompositor, options: VideoRecordingOptions,
         screenOrigin: CGPoint, frameSize: CGSize, log: Logger) {
        self.writer = writer
        self.compositor = compositor
        self.options = options
        self.screenOrigin = screenOrigin
        self.frameSize = frameSize
        self.log = log
    }

    // SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            handleVideoSample(sampleBuffer)
        case .audio:
            writer.appendAudio(sampleBuffer)
        @unknown default:
            break
        }
    }

    func handleMicrophoneSampleBuffer(_ buffer: CMSampleBuffer) {
        writer.appendAudio(buffer)
    }

    private func handleVideoSample(_ sb: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sb), CMSampleBufferGetNumSamples(sb) > 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sb) else { return }

        // Lock + draw overlays into the pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let ctx = makeContext(for: pixelBuffer) {
            compositor.draw(options: options, frameSize: frameSize, screenOrigin: screenOrigin, in: ctx)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        writer.appendVideo(pixelBuffer: pixelBuffer, presentationTime: pts)
    }

    private func makeContext(for pixelBuffer: CVPixelBuffer) -> CGContext? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)

        let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    }
}

// Helper accessor used by stop() above
private extension CGFloat {
    var intValue: Int { Int(self) }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Some Swift 6 concurrency warnings are acceptable.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Capture/Video/Recording/VideoRecorderLive.swift
git commit -m "feat(video): VideoRecorderLive — SCStream + AVAssetWriter + per-frame overlay composition"
```

---

## Task 13: `RecordingControlBarView` (SwiftUI)

**Files:**
- Create: `JuiceScreen/Capture/Video/UI/RecordingControlBarView.swift`

- [ ] **Step 1: Implement `RecordingControlBarView.swift`**

```swift
import SwiftUI

struct RecordingControlBarView: View {

    let elapsed: TimeInterval
    let micEnabled: Bool
    let onStop: () -> Void
    let onToggleMic: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
            .help("Stop Recording")

            Text(formattedElapsed)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            Divider().frame(height: 16)

            Button(action: onToggleMic) {
                Image(systemName: micEnabled ? "mic.fill" : "mic.slash.fill")
                    .foregroundStyle(micEnabled ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(micEnabled ? "Mute microphone" : "Microphone is muted")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private var formattedElapsed: String {
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
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
git add JuiceScreen/Capture/Video/UI/RecordingControlBarView.swift
git commit -m "feat(video): RecordingControlBarView (capsule with stop + duration + mic toggle)"
```

---

## Task 14: `RecordingControlWindow` (NSWindow wrapper, always-on-top, draggable)

**Files:**
- Create: `JuiceScreen/Capture/Video/UI/RecordingControlWindow.swift`

- [ ] **Step 1: Implement `RecordingControlWindow.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class RecordingControlWindow {

    let window: NSWindow
    private var hostingView: NSHostingView<RecordingControlBarView>?
    private var elapsed: TimeInterval = 0
    private var micEnabled: Bool = false

    init(initialMicEnabled: Bool, onStop: @escaping () -> Void, onToggleMic: @escaping () -> Void) {
        let frame = NSRect(x: 0, y: 0, width: 220, height: 48)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        // Position: bottom-center of primary screen, 64pt above bottom
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: screenFrame.midX - frame.width / 2,
                y: screenFrame.minY + 64
            ))
        }

        self.window = window
        self.micEnabled = initialMicEnabled

        let view = RecordingControlBarView(
            elapsed: elapsed,
            micEnabled: initialMicEnabled,
            onStop: onStop,
            onToggleMic: onToggleMic
        )
        let host = NSHostingView(rootView: view)
        window.contentView = host
        self.hostingView = host
    }

    func show() {
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }

    func update(elapsed: TimeInterval, micEnabled: Bool, onStop: @escaping () -> Void, onToggleMic: @escaping () -> Void) {
        self.elapsed = elapsed
        self.micEnabled = micEnabled
        hostingView?.rootView = RecordingControlBarView(
            elapsed: elapsed,
            micEnabled: micEnabled,
            onStop: onStop,
            onToggleMic: onToggleMic
        )
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
git add JuiceScreen/Capture/Video/UI/RecordingControlWindow.swift
git commit -m "feat(video): RecordingControlWindow — borderless floating panel, bottom-center"
```

---

## Task 15: `RecordingSession` (coordinator) + tests

**Files:**
- Create: `JuiceScreen/Capture/Video/Session/RecordingSession.swift`
- Create: `JuiceScreenTests/RecordingSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("RecordingSession")
@MainActor
struct RecordingSessionTests {

    @Test("start kicks off recorder and creates UI")
    func start() async throws {
        let recorder = FakeVideoRecorder()
        let session = RecordingSession(recorder: recorder, onStopComplete: { _ in })
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        try await session.start(mode: .fullScreen, options: .defaults, outputURL: url)
        #expect(recorder.isRecording == true)
        #expect(session.isActive == true)
    }

    @Test("stop returns recorder result and calls completion handler")
    func stop() async throws {
        let recorder = FakeVideoRecorder()
        var receivedRecord: CaptureRecord?
        let url = URL(fileURLWithPath: "/tmp/x.mp4")
        let expected = CaptureRecord(
            id: UUID(), fileURL: url, captureType: .fullScreen,
            capturedAt: Date(), pixelWidth: 1920, pixelHeight: 1080, sourceApp: nil
        )
        recorder.stopOutcome = .success(expected)

        let session = RecordingSession(recorder: recorder) { receivedRecord = $0 }
        try await session.start(mode: .fullScreen, options: .defaults, outputURL: url)
        try await session.stop()

        #expect(recorder.isRecording == false)
        #expect(session.isActive == false)
        #expect(receivedRecord?.id == expected.id)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/RecordingSessionTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `RecordingSession.swift`**

```swift
import AppKit
import Foundation

@MainActor
public final class RecordingSession {

    private let recorder: VideoRecorder
    private let onStopComplete: (CaptureRecord) -> Void
    private var controlWindow: RecordingControlWindow?
    private var elapsedTimer: Timer?
    private var options: VideoRecordingOptions = .defaults
    private let log = AppLog.logger(category: "RecordingSession")

    public init(recorder: VideoRecorder, onStopComplete: @escaping (CaptureRecord) -> Void) {
        self.recorder = recorder
        self.onStopComplete = onStopComplete
    }

    public var isActive: Bool { recorder.isRecording }

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        self.options = options

        let micEnabled = options.captureMicrophone
        let onStopHandler: () -> Void = { [weak self] in
            Task { @MainActor [weak self] in try? await self?.stop() }
        }
        let onToggleMic: () -> Void = { [weak self] in
            self?.recorder.toggleMicrophoneMute()
        }

        let win = RecordingControlWindow(
            initialMicEnabled: micEnabled,
            onStop: onStopHandler,
            onToggleMic: onToggleMic
        )
        self.controlWindow = win
        win.show()

        try await recorder.start(mode: mode, options: options, outputURL: outputURL)

        // Tick UI every 200ms to update the elapsed counter
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.controlWindow?.update(
                    elapsed: self.recorder.elapsed,
                    micEnabled: self.options.captureMicrophone,
                    onStop: onStopHandler,
                    onToggleMic: onToggleMic
                )
            }
        }
    }

    public func stop() async throws {
        guard recorder.isRecording else { return }
        let record = try await recorder.stop()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        controlWindow?.close()
        controlWindow = nil
        onStopComplete(record)
        log.info("Session ended → \(record.fileURL.path)")
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/RecordingSessionTests 2>&1 | tail -10
```

Expected: 2/2 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Capture/Video/Session/RecordingSession.swift JuiceScreenTests/RecordingSessionTests.swift
git commit -m "feat(video): RecordingSession coordinator (recorder + control window + elapsed timer)"
```

---

## Task 16: `RecordingSessionManager` (singleton)

**Files:**
- Create: `JuiceScreen/Capture/Video/Session/RecordingSessionManager.swift`

- [ ] **Step 1: Implement `RecordingSessionManager.swift`**

```swift
import Foundation

@MainActor
public final class RecordingSessionManager {

    private let recorderFactory: () -> VideoRecorder
    private let onStopComplete: (CaptureRecord) -> Void
    private var session: RecordingSession?

    public init(
        recorderFactory: @escaping () -> VideoRecorder,
        onStopComplete: @escaping (CaptureRecord) -> Void
    ) {
        self.recorderFactory = recorderFactory
        self.onStopComplete = onStopComplete
    }

    public var isActive: Bool { session?.isActive == true }

    public func start(mode: VideoRecordingMode, options: VideoRecordingOptions, outputURL: URL) async throws {
        if isActive { return }
        let recorder = recorderFactory()
        let session = RecordingSession(recorder: recorder) { [weak self] record in
            self?.session = nil
            self?.onStopComplete(record)
        }
        self.session = session
        try await session.start(mode: mode, options: options, outputURL: outputURL)
    }

    public func stop() async throws {
        guard let session else { return }
        try await session.stop()
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
git add JuiceScreen/Capture/Video/Session/RecordingSessionManager.swift
git commit -m "feat(video): RecordingSessionManager — single-session lifecycle owner"
```

---

## Task 17: Wire video recording into `AppDelegate`

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Add lazy properties + recordScreen action**

In `JuiceScreen/App/AppDelegate.swift`:

1. Add new lazy property after `editorWindowManager`:

```swift
    private lazy var recordingSessionManager: RecordingSessionManager = {
        RecordingSessionManager(
            recorderFactory: { [permissions] in VideoRecorderLive(permissions: permissions) },
            onStopComplete: { [weak self] record in
                guard let self else { return }
                self.menuBar?.setRecordingIndicator(false)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try await self.captureLibraryRecorder.record(record)
                    } catch {
                        AppLog.logger(category: "App").error("Library recording failed: \(String(describing: error))")
                    }
                }
            }
        )
    }()
```

2. Add a private method to start recording (handles region picking when needed):

```swift
    private func startRecording() {
        Task { @MainActor in
            // Decide mode: full-screen by default for v0.6.0; region-record can be added by holding ⌥
            // when pressing the hotkey (future polish). For now, full-screen of primary display.
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
                try await recordingSessionManager.start(
                    mode: mode,
                    options: .defaults,
                    outputURL: outputURL
                )
            } catch {
                AppLog.logger(category: "App").error("Recording failed to start: \(String(describing: error))")
                menuBar?.setRecordingIndicator(false)
            }
        }
    }

    private func stopRecording() {
        Task { @MainActor in
            do {
                try await recordingSessionManager.stop()
            } catch {
                AppLog.logger(category: "App").error("Stop failed: \(String(describing: error))")
            }
        }
    }
```

3. In `applicationDidFinishLaunching`, replace the `recordScreen` MenuBarActions closure:

```swift
            recordScreen:      { [weak self] in self?.handleRecordScreen() },
```

(Previously: `{ [weak self] in self?.todoLog("recordScreen") }`)

4. Add the helper method:

```swift
    private func handleRecordScreen() {
        if recordingSessionManager.isActive {
            stopRecording()
        } else {
            startRecording()
        }
    }
```

5. Wire the global Stop Recording hotkey. Find the `registerHotkeys` method and add an additional registration for `.stopRecording`:

```swift
        hotkeyService.register(prefs.recordScreenHotkey, for: .stopRecording) { [weak self] in
            self?.stopRecording()
        }
```

Note: Plan 1's `Hotkey` registration uses `HotkeyAction.stopRecording = 7` already defined. We map it to the same key combo as recordScreen for v0.6.0 — pressing the record key while a recording is active stops it. The `handleRecordScreen()` method already handles this via the start/stop branch, so the explicit `stopRecording` registration is for cases where the menu bar's "Record Screen" item triggers it directly. (The duplicate registration is intentional: HotkeyService.register will overwrite the previous binding for `.recordScreen`, and `.stopRecording` is a separate enum case that we register additionally.)

Actually for v0.6.0 simplification: the recordScreen hotkey already toggles via `handleRecordScreen()`. We do NOT additionally register `.stopRecording` — that's a polish for when we want a separate hotkey for stopping. Skip that registration in this task. Plan 9 (settings completion) will add the optional dedicated stop hotkey.

- [ ] **Step 2: Verify build + tests**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: build succeeds, all unit tests still pass (~205 tests).

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): wire RecordingSessionManager into recordScreen action (toggle start/stop)"
```

---

## Task 18: `RecordingTab` settings (toggles for cursor / click pulse / keystrokes / mic default)

**Files:**
- Modify: `JuiceScreen/MainWindow/Settings/RecordingTab.swift`

- [ ] **Step 1: Replace placeholder content with toggles backed by preferences**

For v0.6.0 we wire UI toggles that surface the `VideoRecordingOptions.defaults` for the user to inspect. Persisting custom defaults to `Preferences` is part of Plan 9 — for now, the toggles read static defaults and explain that user-configurable persistence is coming.

Replace the existing `RecordingTab` body content with:

```swift
import SwiftUI

struct RecordingTab: View {

    @State private var captureSystemAudio = VideoRecordingOptions.defaults.captureSystemAudio
    @State private var captureMicrophone = VideoRecordingOptions.defaults.captureMicrophone
    @State private var showCursorHighlight = VideoRecordingOptions.defaults.showCursorHighlight
    @State private var showClickPulse = VideoRecordingOptions.defaults.showClickPulse
    @State private var showKeystrokes = VideoRecordingOptions.defaults.showKeystrokes

    var body: some View {
        Form {
            Section {
                Toggle("Capture system audio", isOn: $captureSystemAudio)
                    .help("Mix system audio (anything macOS routes through speakers/headphones) into the recording.")

                Toggle("Capture microphone", isOn: $captureMicrophone)
                    .help("Adds a separate microphone track. macOS will prompt for Microphone permission the first time you record with this enabled.")
            } header: { Text("Audio") }

            Section {
                Toggle("Cursor highlight ring", isOn: $showCursorHighlight)
                    .help("Yellow ring around the cursor in the output video. No extra permissions required.")

                Toggle("Click pulse", isOn: $showClickPulse)
                    .help("Animated pulse at every click. Requires macOS Input Monitoring permission — will prompt the first time you enable.")

                Toggle("Show keystrokes", isOn: $showKeystrokes)
                    .help("Last 3 keys typed appear in the bottom-right corner. Requires Input Monitoring.")
            } header: { Text("Overlays") }

            Section {
                Text("Defaults shown above. User-configurable persistence is wired in v0.9 (settings completion). v0.6 always uses these defaults.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } footer: { EmptyView() }
        }
        .formStyle(.grouped)
        .padding()
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
git add JuiceScreen/MainWindow/Settings/RecordingTab.swift
git commit -m "feat(settings): RecordingTab toggles (audio/mic/cursor/click pulse/keystrokes)"
```

---

## Task 19: Library — write video row after recording

**Files:**
- Modify: `JuiceScreen/Library/CaptureLibraryRecorder.swift`

- [ ] **Step 1: Detect mp4 extension and write video row**

The existing `record(_:)` method writes an image-typed row regardless of file type. Add a fork: if the file extension is `.mp4`, build a video row instead with thumbnail derived from the first frame.

Replace the body of `record(_:)`:

```swift
    public func record(_ record: CaptureRecord) async throws {
        let isVideo = record.fileURL.pathExtension.lowercased() == "mp4"

        // Choose source image for thumbnail
        let sourceImage: NSImage?
        if isVideo {
            sourceImage = await Self.firstFrameThumbnail(for: record.fileURL)
        } else {
            sourceImage = NSImage(contentsOf: record.fileURL)
        }

        guard let image = sourceImage else {
            log.error("Could not derive thumbnail for \(record.fileURL.path)")
            return
        }

        let thumbnailPath = try thumbnailStore.write(image: image, for: record.id)

        let attrs = try? FileManager.default.attributesOfItem(atPath: record.fileURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        let row: CaptureRow
        if isVideo {
            row = CaptureRow(
                uuid: record.id,
                filePath: record.fileURL.path,
                annotationPath: nil,
                thumbnailPath: thumbnailPath,
                mediaType: .video,
                capturedAt: record.capturedAt,
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                durationMs: nil,    // populated when AVAsset duration is read in a later plan
                fileSizeBytes: fileSize,
                sourceApp: record.sourceApp,
                deletedAt: nil
            )
        } else {
            row = CaptureRow(record: record, fileSizeBytes: fileSize, thumbnailPath: thumbnailPath)
        }

        try await store.insert(row)
        log.info("Indexed capture \(record.id) (\(fileSize) bytes, \(isVideo ? "video" : "image"))")

        // OCR pipeline only for images (per spec — video frames are deferred)
        if let pipeline = ocrPipeline, !isVideo {
            Task.detached { [pipeline, captureID = record.id, fileURL = record.fileURL] in
                try? await pipeline.process(captureID: captureID, fileURL: fileURL)
            }
        }
    }

    /// Extracts the first frame of a video as an NSImage for thumbnail use.
    private static func firstFrameThumbnail(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)

        do {
            let cg = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }
```

Add `import AVFoundation` at the top of the file.

- [ ] **Step 2: Verify build + existing tests still pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureLibraryRecorderTests 2>&1 | tail -8
```

Expected: build succeeds, the existing image-path test still passes (we added a video branch but didn't break image flow).

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Library/CaptureLibraryRecorder.swift
git commit -m "feat(library): CaptureLibraryRecorder writes .video rows for .mp4 files (first-frame thumbnail)"
```

---

## Task 20: README — note v0.6 video recording

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append a paragraph after the v0.5 OCR paragraph**

```markdown
**v0.6 update — local video recording.** Press ⌘⇧5 to start a full-screen recording. ScreenCaptureKit captures the primary display at 60fps, system audio mixes in by default, and a yellow ring follows the cursor in every frame. Optional microphone capture and Input-Monitoring-gated overlays (click pulse, last-3-keystrokes chip in the corner) are available in Settings → Recording. A small floating control bar shows duration + a stop button. MP4 H.264 files land at `~/Pictures/JuiceScreen/<date>/JuiceScreen_<timestamp>.mp4` and appear as `.video` rows in the library. Trim handles + post-record editing arrive in v0.7.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README — note v0.6 video recording"
```

---

## Task 21: Bump VERSION to 0.6.0, tag

**Files:**
- Modify: `VERSION` — `0.6.0`
- Modify: `project.yml` — `MARKETING_VERSION: "0.6.0"`

- [ ] **Step 1: Update VERSION + project.yml**

Replace `VERSION` contents with:

```
0.6.0
```

In `project.yml`, change `MARKETING_VERSION: "0.5.0"` to `MARKETING_VERSION: "0.6.0"`.

- [ ] **Step 2: Clean build + full test**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
rm -rf ~/Library/Developer/Xcode/DerivedData/JuiceScreen-*
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
```

Expected: build + tests succeed (~205 tests).

- [ ] **Step 3: Manual smoke test (HUMAN STEP)**

| # | Action | Expected |
|---|---|---|
| 1 | Launch app, press ⌘⇧5 | Floating control bar appears bottom-center; menu bar icon switches to red record.circle |
| 2 | Move the cursor around for 5–10s | Cursor highlight ring visible to user but ALSO in the eventual output |
| 3 | Click the floating bar's red Stop button | Recording ends; control bar disappears; menu bar icon returns to camera.viewfinder |
| 4 | Open `~/Pictures/JuiceScreen/<today>/` in Finder | A `.mp4` file is there |
| 5 | Open the MP4 in QuickTime / VLC | Plays back; cursor highlight ring is composited into the video at the right positions; system audio (if anything was playing) is in the file |
| 6 | Press ⌘⇧L → library | The new video appears as a tile with thumbnail of the first frame and "MP4" badge |
| 7 | Settings → Recording, enable "Click pulse" | (For v0.6 the toggle is informational only — Input Monitoring prompt fires on first recording with clicks enabled) |
| 8 | Stop a recording via the menu bar's "Record Screen" item (the same item triggers stop via `handleRecordScreen()` toggle) | Recording ends |

If any step fails, do **not** tag.

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION project.yml
git commit -m "chore: bump VERSION to 0.6.0"
git tag -a v0.6.0 -m "Video Recording milestone: SCStream + AVAssetWriter MP4 with cursor overlay"
git tag -l v0.6.0
```

- [ ] **Step 5: Verify clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Task 22: Update spec doc with Plan 6 status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Update Plan 6 line**

Replace `⬜ Plan 6: Video recording` with:

```
- ✅ **Plan 6: Video recording** (v0.6.0, 2026-05-05) — Press ⌘⇧5 to record the primary display at 60fps. SCStream → per-frame composition (CGContext) → AVAssetWriter H.264 MP4 at `~/Pictures/JuiceScreen/<date>/`. System audio captured by default via SCStreamConfiguration.capturesAudio; microphone via separate AVCaptureSession (opt-in). Cursor highlight ring composited into output (default ON, NSEvent.mouseLocation 50Hz polling, no extra TCC). Click pulse + keystroke overlay (default OFF, opt-in via Input Monitoring TCC). Floating recording control bar with Stop button, duration counter, mic toggle. Menu bar icon switches to red record.circle during recording. Recording row written to library as .video with first-frame thumbnail. Region-record + multi-display + trim handles deferred (Plan 7+). 205 unit tests
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 6 (Video recording) complete in implementation status"
```

---

## Plan completion checklist

- [ ] `git tag -l` shows v0.1.0 → v0.6.0
- [ ] `xcodebuild test -only-testing:JuiceScreenTests` is green (~205 tests)
- [ ] All 8 manual smoke-test items pass
- [ ] An MP4 file plays back with cursor highlight ring composited on top
- [ ] Library window shows the recording with first-frame thumbnail + "MP4" badge

When everything checks out: ship v0.6.0 alpha. Plan 7 is next — trim handles + AVAssetExportSession for post-record editing.
