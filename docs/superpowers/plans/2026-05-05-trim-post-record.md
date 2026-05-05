# JuiceScreen — Trim + Post-Record Implementation Plan (Plan 7 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.7.0` — double-clicking a video tile in the library opens a dedicated **Trim Editor** window. The window contains an `AVPlayer` view with the video, a custom scrubber underneath with two draggable handles (start + end), a transport toolbar (Play/Pause, Reset, **Save Trim** / **Save Trim As…**), and a duration label that updates while you drag. Saving runs `AVAssetExportSession` to write a new H.264 MP4 with the chosen `[start, end]` range. The library's `CaptureRow.durationMs` field (defined in Plan 4 but never populated) is now filled in for every video on import via `AVAsset.duration`.

**Architecture:** New `Trim/` module split into `Model/` (pure value types: `TrimRange` with CMTime bounds), `Service/` (`TrimmerService` protocol + `Live` impl wrapping `AVAssetExportSession` + `Fake` for tests), `UI/` (SwiftUI: AVPlayer wrapper, scrubber with two handles, toolbar, top-level `TrimEditorView`), and `Window/` (`TrimEditorWindow` per video, `TrimEditorWindowManager` singleton). Library integration: `LibraryViewModel` already invokes `onOpen(row)` on double-click; `AppDelegate` routes that callback by `mediaType` — image rows go to the existing `EditorWindowManager` (Plan 3), video rows go to the new `TrimEditorWindowManager`. `CaptureLibraryRecorder` is extended to call `AVAsset.duration` on `.mp4` files and store the value in `durationMs`.

**Tech Stack:** AVFoundation (`AVPlayer`, `AVPlayerLayer`, `AVURLAsset`, `AVAssetExportSession`, `AVAssetExportPresetHighestQuality`, `CMTime`/`CMTimeRange`), AppKit (`NSView`-backed `AVPlayerLayer` host via `NSViewRepresentable`), SwiftUI for everything else, existing `EditorWindowManager` pattern from Plan 3.

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — section "Video recording → Trim handles" (post-record).

**Plan 6 prerequisite:** v0.6.0 tagged. MP4 video files exist at `~/Pictures/JuiceScreen/<date>/`. Library inserts `.video` rows with first-frame thumbnail. `CaptureRow.durationMs` exists in the schema (Plan 4) but is currently always `nil` for videos.

**Scope deferred to later plans:**

- **Audio waveform display in the scrubber** — v0.7 ships a simple gradient strip; waveform rendering is a v1.1 polish (requires reading audio samples and drawing peaks)
- **Multiple trim regions / split** — v0.7 supports a single `[start, end]` range; multi-region split is YAGNI for v1
- **Frame-stepping with arrow keys** — Play/Pause + scrubber drag is enough for v0.7
- **Live preview while dragging the trim handles** — handles update the player time on drag end; updating the player on every drag tick adds complexity for marginal gain. Drag-and-release is sufficient
- **Re-encoding settings** — uses `AVAssetExportPresetHighestQuality` always; codec/bitrate picker is a v1.1 setting

---

## File Structure

```
JuiceScreen/
├── Trim/
│   ├── Model/
│   │   └── TrimRange.swift                     NEW — value type: start/end CMTime + isValid + duration
│   ├── Service/
│   │   ├── TrimmerService.swift                NEW — protocol + TrimmerError
│   │   ├── TrimmerServiceLive.swift            NEW — AVAssetExportSession impl
│   │   └── FakeTrimmerService.swift            NEW — test double
│   ├── UI/
│   │   ├── AVPlayerView.swift                  NEW — NSViewRepresentable wrapping AVPlayerLayer
│   │   ├── TrimViewModel.swift                 NEW — @Observable: player + range + transport state
│   │   ├── TrimScrubberView.swift              NEW — track + two draggable handles
│   │   ├── TrimToolbarView.swift               NEW — Play/Pause + Reset + Save Trim + Save Trim As
│   │   └── TrimEditorView.swift                NEW — top-level: AVPlayer + scrubber + toolbar
│   └── Window/
│       ├── TrimEditorWindow.swift              NEW — NSWindow per video
│       └── TrimEditorWindowManager.swift       NEW — singleton mapping CaptureRow → TrimEditorWindow
├── App/
│   └── AppDelegate.swift                       MODIFY — route library tile onOpen by mediaType
├── Library/
│   └── CaptureLibraryRecorder.swift            MODIFY — populate durationMs for videos via AVAsset.duration

VERSION                                          MODIFY — bump to 0.7.0 (Task 14)
project.yml                                      MODIFY — MARKETING_VERSION 0.7.0 (Task 14)
docs/superpowers/specs/2026-05-04-juicescreen-design.md  MODIFY — implementation status (Task 15)

JuiceScreenTests/
├── TrimRangeTests.swift                         NEW
├── FakeTrimmerServiceTests.swift                NEW
└── TrimViewModelTests.swift                     NEW
```

---

## Task 1: `TrimRange` value type + tests

**Files:**
- Create: `JuiceScreen/Trim/Model/TrimRange.swift`
- Create: `JuiceScreenTests/TrimRangeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import CoreMedia
import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrimRange")
struct TrimRangeTests {

    private func t(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    @Test("Constructor stores start and end")
    func storage() {
        let range = TrimRange(start: t(2), end: t(10))
        #expect(range.start == t(2))
        #expect(range.end == t(10))
    }

    @Test("durationSeconds == end - start")
    func duration() {
        let range = TrimRange(start: t(2), end: t(10.5))
        #expect(abs(range.durationSeconds - 8.5) < 0.001)
    }

    @Test("isValid: end > start AND duration >= minimum (0.1s)")
    func validity() {
        #expect(TrimRange(start: t(0), end: t(1)).isValid)
        #expect(TrimRange(start: t(2), end: t(10)).isValid)
        #expect(!TrimRange(start: t(5), end: t(5)).isValid)        // zero-duration
        #expect(!TrimRange(start: t(5), end: t(4)).isValid)        // inverted
        #expect(!TrimRange(start: t(0), end: t(0.05)).isValid)     // below minimum
    }

    @Test("clamped(toAssetDuration:) returns range bounded by asset")
    func clamping() {
        let assetDuration = t(20)
        let range = TrimRange(start: t(-5), end: t(30)).clamped(toAssetDuration: assetDuration)
        #expect(range.start == .zero)
        #expect(range.end == t(20))
    }

    @Test("Equatable")
    func equality() {
        let a = TrimRange(start: t(1), end: t(5))
        let b = TrimRange(start: t(1), end: t(5))
        let c = TrimRange(start: t(1), end: t(6))
        #expect(a == b)
        #expect(a != c)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrimRangeTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `TrimRange.swift`**

```swift
import CoreMedia
import Foundation

public struct TrimRange: Equatable, Sendable {
    public var start: CMTime
    public var end: CMTime

    public static let minimumDurationSeconds: Double = 0.1

    public init(start: CMTime, end: CMTime) {
        self.start = start
        self.end = end
    }

    public var durationSeconds: Double {
        let s = CMTimeGetSeconds(start)
        let e = CMTimeGetSeconds(end)
        guard s.isFinite, e.isFinite else { return 0 }
        return max(0, e - s)
    }

    public var isValid: Bool {
        durationSeconds >= TrimRange.minimumDurationSeconds
    }

    public var asCMTimeRange: CMTimeRange {
        CMTimeRange(start: start, end: end)
    }

    public func clamped(toAssetDuration assetDuration: CMTime) -> TrimRange {
        let zero = CMTime.zero
        let clampedStart = CMTimeMaximum(start, zero)
        let clampedEnd = CMTimeMinimum(end, assetDuration)
        return TrimRange(start: clampedStart, end: clampedEnd)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrimRangeTests 2>&1 | tail -10
```

Expected: 5/5 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Trim/Model/TrimRange.swift JuiceScreenTests/TrimRangeTests.swift
git commit -m "feat(trim): TrimRange value type (CMTime start/end + clamping + validity)"
```

---

## Task 2: `TrimmerService` protocol + `FakeTrimmerService` + tests

**Files:**
- Create: `JuiceScreen/Trim/Service/TrimmerService.swift`
- Create: `JuiceScreen/Trim/Service/FakeTrimmerService.swift`
- Create: `JuiceScreenTests/FakeTrimmerServiceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import CoreMedia
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeTrimmerService")
struct FakeTrimmerServiceTests {

    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    @Test("Returns the configured destination URL")
    func returnsConfigured() async throws {
        let svc = FakeTrimmerService()
        let dest = URL(fileURLWithPath: "/tmp/out.mp4")
        svc.nextResult = .success(dest)

        let result = try await svc.trim(
            sourceURL: URL(fileURLWithPath: "/tmp/in.mp4"),
            range: TrimRange(start: t(0), end: t(5)),
            destinationURL: dest
        )
        #expect(result == dest)
    }

    @Test("Throws the configured error")
    func throwsConfigured() async {
        let svc = FakeTrimmerService()
        svc.nextResult = .failure(.exportFailed("boom"))
        await #expect(throws: TrimmerError.self) {
            _ = try await svc.trim(
                sourceURL: URL(fileURLWithPath: "/tmp/in.mp4"),
                range: TrimRange(start: t(0), end: t(5)),
                destinationURL: URL(fileURLWithPath: "/tmp/out.mp4")
            )
        }
    }

    @Test("Records calls so tests can inspect inputs")
    func recordsCall() async throws {
        let svc = FakeTrimmerService()
        let source = URL(fileURLWithPath: "/tmp/in.mp4")
        let dest = URL(fileURLWithPath: "/tmp/out.mp4")
        let range = TrimRange(start: t(2), end: t(7))
        svc.nextResult = .success(dest)

        _ = try await svc.trim(sourceURL: source, range: range, destinationURL: dest)

        #expect(svc.calls.count == 1)
        #expect(svc.calls[0].sourceURL == source)
        #expect(svc.calls[0].destinationURL == dest)
        #expect(svc.calls[0].range == range)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeTrimmerServiceTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `TrimmerService.swift`**

```swift
import Foundation

public enum TrimmerError: Error, Equatable {
    case invalidRange
    case sourceUnreadable
    case destinationUnwritable(String)
    case exportFailed(String)
    case userCancelled
}

public protocol TrimmerService: Sendable {
    /// Writes a trimmed copy of `sourceURL` covering `range` to `destinationURL`.
    /// Returns the URL of the written file.
    func trim(sourceURL: URL, range: TrimRange, destinationURL: URL) async throws -> URL
}
```

- [ ] **Step 4: Implement `FakeTrimmerService.swift`**

```swift
import Foundation

public final class FakeTrimmerService: TrimmerService, @unchecked Sendable {

    public typealias Outcome = Result<URL, TrimmerError>

    public struct Call: Equatable, Sendable {
        public let sourceURL: URL
        public let range: TrimRange
        public let destinationURL: URL
    }

    private let lock = NSLock()
    public var nextResult: Outcome?
    public private(set) var calls: [Call] = []

    public init() {}

    public func trim(sourceURL: URL, range: TrimRange, destinationURL: URL) async throws -> URL {
        lock.lock()
        calls.append(Call(sourceURL: sourceURL, range: range, destinationURL: destinationURL))
        let outcome = nextResult
        lock.unlock()

        switch outcome {
        case .success(let url): return url
        case .failure(let err): throw err
        case nil:               return destinationURL
        }
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakeTrimmerServiceTests 2>&1 | tail -10
```

Expected: 3/3 pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Trim/Service/TrimmerService.swift JuiceScreen/Trim/Service/FakeTrimmerService.swift JuiceScreenTests/FakeTrimmerServiceTests.swift
git commit -m "feat(trim): TrimmerService protocol + FakeTrimmerService test double"
```

---

## Task 3: `TrimmerServiceLive` (`AVAssetExportSession`)

**Files:**
- Create: `JuiceScreen/Trim/Service/TrimmerServiceLive.swift`

(No automated tests — `AVAssetExportSession` requires real video files.)

- [ ] **Step 1: Implement `TrimmerServiceLive.swift`**

```swift
import AVFoundation
import Foundation

public final class TrimmerServiceLive: TrimmerService {

    private let log = AppLog.logger(category: "TrimmerServiceLive")

    public init() {}

    public func trim(sourceURL: URL, range: TrimRange, destinationURL: URL) async throws -> URL {
        guard range.isValid else {
            throw TrimmerError.invalidRange
        }
        let asset = AVURLAsset(url: sourceURL)

        // Validate readability
        do {
            _ = try await asset.load(.duration)
        } catch {
            throw TrimmerError.sourceUnreadable
        }

        // Remove any existing file at destination
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            do {
                try FileManager.default.removeItem(at: destinationURL)
            } catch {
                throw TrimmerError.destinationUnwritable("\(error)")
            }
        }

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimmerError.exportFailed("Could not create export session")
        }

        session.outputURL = destinationURL
        session.outputFileType = .mp4
        session.timeRange = range.asCMTimeRange
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        switch session.status {
        case .completed:
            log.info("Trim complete → \(destinationURL.path)")
            return destinationURL
        case .cancelled:
            throw TrimmerError.userCancelled
        case .failed:
            let message = session.error?.localizedDescription ?? "unknown"
            throw TrimmerError.exportFailed(message)
        default:
            throw TrimmerError.exportFailed("Unexpected status: \(String(describing: session.status))")
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (The `await session.export()` is the new async API on macOS 14+.)

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Trim/Service/TrimmerServiceLive.swift
git commit -m "feat(trim): TrimmerServiceLive (AVAssetExportSession highest-quality MP4)"
```

---

## Task 4: `AVPlayerView` (`NSViewRepresentable`)

**Files:**
- Create: `JuiceScreen/Trim/UI/AVPlayerView.swift`

(No automated tests — wraps an AppKit view for SwiftUI.)

- [ ] **Step 1: Implement `AVPlayerView.swift`**

```swift
import AVFoundation
import AppKit
import SwiftUI

/// Hosts an `AVPlayerLayer` in a SwiftUI view.
struct AVPlayerView: NSViewRepresentable {

    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        nsView.player = player
    }
}

/// AppKit-backed view that owns an `AVPlayerLayer`. Auto-resizes the layer with the view.
final class PlayerHostView: NSView {

    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
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
git add JuiceScreen/Trim/UI/AVPlayerView.swift
git commit -m "feat(trim): AVPlayerView — NSViewRepresentable wrapping AVPlayerLayer"
```

---

## Task 5: `TrimViewModel` (`@Observable`) + tests

**Files:**
- Create: `JuiceScreen/Trim/UI/TrimViewModel.swift`
- Create: `JuiceScreenTests/TrimViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import JuiceScreen

@Suite("TrimViewModel")
@MainActor
struct TrimViewModelTests {

    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    @Test("Initial state: full range, isPlaying false, currentTime zero")
    func initial() {
        let player = AVPlayer()
        let vm = TrimViewModel(player: player, sourceURL: URL(fileURLWithPath: "/tmp/x.mp4"), assetDuration: t(20))
        #expect(vm.range == TrimRange(start: .zero, end: t(20)))
        #expect(vm.isPlaying == false)
        #expect(vm.assetDurationSeconds == 20)
    }

    @Test("setStart clamps to [0, end - minimum]")
    func setStartClamps() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(10))
        vm.setStart(seconds: -5)
        #expect(vm.range.start == .zero)
        vm.setStart(seconds: 9.99)
        #expect(vm.range.start.seconds < vm.range.end.seconds - TrimRange.minimumDurationSeconds + 0.01)
    }

    @Test("setEnd clamps to [start + minimum, assetDuration]")
    func setEndClamps() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(10))
        vm.setEnd(seconds: 100)
        #expect(abs(vm.range.end.seconds - 10) < 0.001)
        vm.setStart(seconds: 5)
        vm.setEnd(seconds: 5)
        #expect(vm.range.end.seconds >= 5 + TrimRange.minimumDurationSeconds)
    }

    @Test("resetRange returns range to [0, assetDuration]")
    func resetRange() {
        let vm = TrimViewModel(player: AVPlayer(), sourceURL: URL(fileURLWithPath: "/x.mp4"), assetDuration: t(10))
        vm.setStart(seconds: 3)
        vm.setEnd(seconds: 7)
        vm.resetRange()
        #expect(vm.range == TrimRange(start: .zero, end: t(10)))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrimViewModelTests 2>&1 | tail -8
```

Expected: compile failure.

- [ ] **Step 3: Implement `TrimViewModel.swift`**

```swift
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class TrimViewModel {

    public let player: AVPlayer
    public let sourceURL: URL
    public let assetDuration: CMTime

    public private(set) var range: TrimRange
    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: CMTime = .zero
    public var trimErrorMessage: String? = nil
    public var isExporting: Bool = false

    private var timeObserver: Any?
    private let log = AppLog.logger(category: "TrimViewModel")

    public init(player: AVPlayer, sourceURL: URL, assetDuration: CMTime) {
        self.player = player
        self.sourceURL = sourceURL
        self.assetDuration = assetDuration
        self.range = TrimRange(start: .zero, end: assetDuration)
        installTimeObserver()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    public var assetDurationSeconds: Double {
        CMTimeGetSeconds(assetDuration)
    }

    // MARK: - Range mutations

    public func setStart(seconds: Double) {
        let target = max(0, min(seconds, assetDurationSeconds - TrimRange.minimumDurationSeconds))
        let endSeconds = max(target + TrimRange.minimumDurationSeconds, range.end.seconds)
        range = TrimRange(
            start: CMTime(seconds: target, preferredTimescale: 600),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )
        seek(toSeconds: target)
    }

    public func setEnd(seconds: Double) {
        let minEnd = range.start.seconds + TrimRange.minimumDurationSeconds
        let target = min(max(seconds, minEnd), assetDurationSeconds)
        range = TrimRange(
            start: range.start,
            end: CMTime(seconds: target, preferredTimescale: 600)
        )
        seek(toSeconds: target)
    }

    public func resetRange() {
        range = TrimRange(start: .zero, end: assetDuration)
    }

    // MARK: - Playback

    public func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            // Loop within trim range: seek to start if currentTime is outside it
            if currentTime < range.start || currentTime >= range.end {
                seek(toSeconds: range.start.seconds)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    public func seek(toSeconds seconds: Double) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Helpers

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time
                // Stop at end of trim range
                if self.isPlaying, time >= self.range.end {
                    self.player.pause()
                    self.isPlaying = false
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/TrimViewModelTests 2>&1 | tail -10
```

Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Trim/UI/TrimViewModel.swift JuiceScreenTests/TrimViewModelTests.swift
git commit -m "feat(trim): TrimViewModel — observable player + range + transport state"
```

---

## Task 6: `TrimScrubberView` (custom track + two handles)

**Files:**
- Create: `JuiceScreen/Trim/UI/TrimScrubberView.swift`

(No automated tests — gesture-driven SwiftUI view. Smoke-tested manually in Task 14.)

- [ ] **Step 1: Implement `TrimScrubberView.swift`**

```swift
import SwiftUI

struct TrimScrubberView: View {

    @Bindable var vm: TrimViewModel

    private let trackHeight: CGFloat = 40
    private let handleWidth: CGFloat = 14
    private let trackBackground = Color.secondary.opacity(0.18)
    private let trackSelected = Color.accentColor.opacity(0.35)
    private let handleColor = Color.accentColor

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let totalSec = max(vm.assetDurationSeconds, 0.001)
            let startX = CGFloat(vm.range.start.seconds / totalSec) * width
            let endX = CGFloat(vm.range.end.seconds / totalSec) * width
            let playheadX = CGFloat(vm.currentTime.seconds / totalSec) * width

            ZStack(alignment: .leading) {
                // Background track (full asset)
                RoundedRectangle(cornerRadius: 8)
                    .fill(trackBackground)
                    .frame(height: trackHeight)

                // Selected sub-range
                RoundedRectangle(cornerRadius: 8)
                    .fill(trackSelected)
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)

                // Playhead
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: trackHeight)
                    .offset(x: max(0, min(width - 2, playheadX)))
                    .opacity(0.85)

                // Start handle
                handle(x: startX, width: width) { newX in
                    vm.setStart(seconds: Double(newX / width) * totalSec)
                }

                // End handle
                handle(x: endX - handleWidth, width: width) { newX in
                    let edge = newX + handleWidth
                    vm.setEnd(seconds: Double(edge / width) * totalSec)
                }
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }

    @ViewBuilder
    private func handle(x: CGFloat, width: CGFloat, onChanged: @escaping (CGFloat) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(handleColor)
            .frame(width: handleWidth, height: trackHeight + 12)
            .overlay(
                Rectangle().fill(Color.white).frame(width: 2, height: 16)
            )
            .offset(x: max(0, min(width - handleWidth, x)), y: -6)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let candidate = max(0, min(width - handleWidth, value.location.x - handleWidth / 2))
                        onChanged(candidate)
                    }
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
git add JuiceScreen/Trim/UI/TrimScrubberView.swift
git commit -m "feat(trim): TrimScrubberView (track + selected sub-range + 2 draggable handles + playhead)"
```

---

## Task 7: `TrimToolbarView`

**Files:**
- Create: `JuiceScreen/Trim/UI/TrimToolbarView.swift`

- [ ] **Step 1: Implement `TrimToolbarView.swift`**

```swift
import SwiftUI

struct TrimToolbarView: View {

    @Bindable var vm: TrimViewModel
    let onSaveTrim: () -> Void
    let onSaveTrimAs: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { vm.togglePlay() }) {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help(vm.isPlaying ? "Pause" : "Play")

            Button(action: { vm.resetRange() }) {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .help("Reset trim handles to full duration")

            Spacer()

            Text(rangeLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onSaveTrim) {
                Label("Save Trim", systemImage: "scissors")
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(vm.isExporting || !vm.range.isValid)

            Button(action: onSaveTrimAs) {
                Label("Save Trim As…", systemImage: "scissors.badge.ellipsis")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .buttonStyle(.bordered)
            .disabled(vm.isExporting || !vm.range.isValid)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rangeLabel: String {
        let start = formatTime(vm.range.start.seconds)
        let end = formatTime(vm.range.end.seconds)
        let dur = formatTime(vm.range.durationSeconds)
        return "\(start) → \(end)  •  \(dur)"
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        let ms = Int((seconds - Double(total)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, max(0, min(99, ms)))
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
git add JuiceScreen/Trim/UI/TrimToolbarView.swift
git commit -m "feat(trim): TrimToolbarView (Play/Pause + Reset + range label + Save Trim/As)"
```

---

## Task 8: `TrimEditorView` (top-level layout)

**Files:**
- Create: `JuiceScreen/Trim/UI/TrimEditorView.swift`

- [ ] **Step 1: Implement `TrimEditorView.swift`**

```swift
import SwiftUI

struct TrimEditorView: View {

    @Bindable var vm: TrimViewModel
    let onSaveTrim: () -> Void
    let onSaveTrimAs: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AVPlayerView(player: vm.player)
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 6) {
                TrimScrubberView(vm: vm)
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                if let message = vm.trimErrorMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                }

                if vm.isExporting {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 14)
                }

                TrimToolbarView(vm: vm, onSaveTrim: onSaveTrim, onSaveTrimAs: onSaveTrimAs)
            }
            .background(.regularMaterial)
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
git add JuiceScreen/Trim/UI/TrimEditorView.swift
git commit -m "feat(trim): TrimEditorView (player + scrubber + toolbar + progress + error)"
```

---

## Task 9: `TrimEditorWindow` + `TrimEditorWindowManager`

**Files:**
- Create: `JuiceScreen/Trim/Window/TrimEditorWindow.swift`
- Create: `JuiceScreen/Trim/Window/TrimEditorWindowManager.swift`

- [ ] **Step 1: Implement `TrimEditorWindow.swift`**

```swift
import AVFoundation
import AppKit
import SwiftUI

@MainActor
final class TrimEditorWindow {

    let window: NSWindow
    private let vm: TrimViewModel
    private let trimmer: TrimmerService
    private let captureRecord: CaptureRow
    private let onClose: () -> Void
    private var closeObserver: NSObjectProtocol?
    private let log = AppLog.logger(category: "TrimEditorWindow")

    init(captureRecord: CaptureRow, trimmer: TrimmerService, onClose: @escaping () -> Void) async throws {
        self.captureRecord = captureRecord
        self.trimmer = trimmer
        self.onClose = onClose

        let url = URL(fileURLWithPath: captureRecord.filePath)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)

        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        let vm = TrimViewModel(player: player, sourceURL: url, assetDuration: duration)
        self.vm = vm

        let frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Trim — \(url.lastPathComponent)"
        win.minSize = NSSize(width: 700, height: 480)
        win.center()
        win.isReleasedWhenClosed = false

        self.window = win

        let onSaveTrim: () -> Void = { [weak self] in
            self?.performTrim(saveAs: false)
        }
        let onSaveTrimAs: () -> Void = { [weak self] in
            self?.performTrim(saveAs: true)
        }

        win.contentView = NSHostingView(
            rootView: TrimEditorView(vm: vm, onSaveTrim: onSaveTrim, onSaveTrimAs: onSaveTrimAs)
        )

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

    private func performTrim(saveAs: Bool) {
        guard vm.range.isValid, !vm.isExporting else { return }
        Task { @MainActor in
            var destination: URL
            if saveAs {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.mpeg4Movie]
                panel.nameFieldStringValue = vm.sourceURL.deletingPathExtension().lastPathComponent + "-trimmed"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                destination = url
            } else {
                destination = vm.sourceURL
                    .deletingPathExtension()
                    .appendingPathExtension("trimmed.mp4")
                let parent = destination.deletingLastPathComponent()
                let baseName = destination.deletingPathExtension().lastPathComponent
                var candidate = destination
                var n = 1
                while FileManager.default.fileExists(atPath: candidate.path) {
                    candidate = parent.appendingPathComponent("\(baseName)-\(n).mp4")
                    n += 1
                }
                destination = candidate
            }

            vm.isExporting = true
            vm.trimErrorMessage = nil
            do {
                let written = try await trimmer.trim(
                    sourceURL: vm.sourceURL,
                    range: vm.range,
                    destinationURL: destination
                )
                vm.isExporting = false
                log.info("Trim wrote → \(written.path)")
                NSWorkspace.shared.activateFileViewerSelecting([written])
            } catch {
                vm.isExporting = false
                vm.trimErrorMessage = "Trim failed: \(String(describing: error))"
                log.error("Trim failed: \(String(describing: error))")
            }
        }
    }
}
```

- [ ] **Step 2: Implement `TrimEditorWindowManager.swift`**

```swift
import Foundation

@MainActor
public final class TrimEditorWindowManager {

    private var openWindows: [UUID: TrimEditorWindow] = [:]
    private let trimmer: TrimmerService
    private let log = AppLog.logger(category: "TrimEditorWindowManager")

    public init(trimmer: TrimmerService = TrimmerServiceLive()) {
        self.trimmer = trimmer
    }

    public func show(for row: CaptureRow) {
        if let existing = openWindows[row.uuid] {
            existing.show()
            return
        }
        Task { @MainActor in
            do {
                let win = try await TrimEditorWindow(
                    captureRecord: row,
                    trimmer: trimmer,
                    onClose: { [weak self] in
                        self?.openWindows.removeValue(forKey: row.uuid)
                    }
                )
                openWindows[row.uuid] = win
                win.show()
            } catch {
                log.error("Failed to open trim window for \(row.uuid): \(String(describing: error))")
            }
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
git add JuiceScreen/Trim/Window/TrimEditorWindow.swift JuiceScreen/Trim/Window/TrimEditorWindowManager.swift
git commit -m "feat(trim): TrimEditorWindow per video + TrimEditorWindowManager singleton"
```

---

## Task 10: Wire `TrimEditorWindowManager` into `AppDelegate` (route by mediaType)

**Files:**
- Modify: `JuiceScreen/App/AppDelegate.swift`

- [ ] **Step 1: Add lazy `trimEditorWindowManager` and route library tile open by media type**

In `JuiceScreen/App/AppDelegate.swift`:

1. Add a new lazy property after `editorWindowManager`:

```swift
    private lazy var trimEditorWindowManager: TrimEditorWindowManager = {
        TrimEditorWindowManager()
    }()
```

2. Find the existing `libraryWindowManager` lazy property's `onOpenCapture` closure (introduced in Plan 4 Task 21). Today it always builds a `CaptureRecord` and routes to `editorWindowManager.show(for:)`. Replace its body with media-type routing:

```swift
    private lazy var libraryWindowManager: LibraryWindowManager = {
        LibraryWindowManager(
            store: libraryStore,
            thumbnailStore: thumbnailStore,
            onOpenCapture: { [weak self] row in
                guard let self else { return }
                switch row.mediaType {
                case .video:
                    self.trimEditorWindowManager.show(for: row)
                case .image:
                    let record = CaptureRecord(
                        id: row.uuid,
                        fileURL: URL(fileURLWithPath: row.filePath),
                        captureType: .region,
                        capturedAt: row.capturedAt,
                        pixelWidth: row.pixelWidth,
                        pixelHeight: row.pixelHeight,
                        sourceApp: row.sourceApp
                    )
                    self.editorWindowManager.show(for: record)
                }
            },
            onOpenSettings: { SettingsWindow.show() }
        )
    }()
```

- [ ] **Step 2: Verify build + tests**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED" | tail -2
```

Expected: build succeeds, all unit tests still pass.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift
git commit -m "feat(app): route library tile open by mediaType — videos go to TrimEditor, images to AnnotationEditor"
```

---

## Task 11: Populate `CaptureRow.durationMs` for videos

**Files:**
- Modify: `JuiceScreen/Library/CaptureLibraryRecorder.swift`

- [ ] **Step 1: Extract duration via `AVAsset.duration`**

In `JuiceScreen/Library/CaptureLibraryRecorder.swift`, find the section in `record(_:)` where the video `CaptureRow` is built (currently `durationMs: nil`). Add a duration-extraction step before building the row.

Replace the `if isVideo { ... }` branch in the row construction with:

```swift
        let row: CaptureRow
        if isVideo {
            let durationMs = await Self.videoDurationMs(for: record.fileURL)
            row = CaptureRow(
                uuid: record.id,
                filePath: record.fileURL.path,
                annotationPath: nil,
                thumbnailPath: thumbnailPath,
                mediaType: .video,
                capturedAt: record.capturedAt,
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                durationMs: durationMs,
                fileSizeBytes: fileSize,
                sourceApp: record.sourceApp,
                deletedAt: nil
            )
        } else {
            row = CaptureRow(record: record, fileSizeBytes: fileSize, thumbnailPath: thumbnailPath)
        }
```

Add the helper after `firstFrameThumbnail`:

```swift
    /// Reads the duration of a video file via AVAsset and converts to milliseconds.
    /// Returns nil if the asset cannot be loaded.
    private static func videoDurationMs(for url: URL) async -> Int? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds >= 0 else { return nil }
            return Int((seconds * 1000).rounded())
        } catch {
            return nil
        }
    }
```

- [ ] **Step 2: Verify build + existing test still passes**

```bash
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/CaptureLibraryRecorderTests 2>&1 | tail -8
```

Expected: build succeeds; the existing image-path test still passes (image branch is unchanged).

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Library/CaptureLibraryRecorder.swift
git commit -m "feat(library): populate CaptureRow.durationMs for video imports via AVAsset.duration"
```

---

## Task 12: Show duration in InspectorView for videos

**Files:**
- Modify: `JuiceScreen/MainWindow/Library/InspectorView.swift`

- [ ] **Step 1: Add a Duration metadata row when row.durationMs is non-nil**

In `JuiceScreen/MainWindow/Library/InspectorView.swift`, find the metadata block (the `VStack` containing the existing `metaRow(...)` calls). Add a new row immediately after the "Type" row:

```swift
                if let ms = row.durationMs {
                    metaRow("Duration", value: formattedDuration(ms))
                }
```

Add the helper method below `metaRow(_:value:)`:

```swift
    private func formattedDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let millis = ms % 1000
        if minutes > 0 {
            return String(format: "%dm %02d.%03ds", minutes, seconds, millis)
        }
        return String(format: "%d.%03ds", seconds, millis)
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
git commit -m "feat(library): InspectorView shows Duration row for video captures"
```

---

## Task 13: README — note v0.7 trim editor

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append a paragraph after the v0.6 video paragraph**

```markdown
**v0.7 update — trim post-record.** Double-click a video tile in the library to open the Trim Editor: AVPlayer-backed preview, custom scrubber with two draggable handles for the start and end of the keep-range, and Save Trim / Save Trim As buttons. AVAssetExportSession writes a new MP4 H.264 with the chosen range at highest quality. The library now stores per-video duration (`durationMs`), shown in the inspector.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README — note v0.7 trim editor"
```

---

## Task 14: Bump VERSION to 0.7.0 + tag

**Files:**
- Modify: `VERSION` — `0.7.0`
- Modify: `project.yml` — `MARKETING_VERSION: "0.7.0"`

- [ ] **Step 1: Update VERSION + project.yml**

Replace `VERSION` contents with:

```
0.7.0
```

In `project.yml`, change `MARKETING_VERSION: "0.6.0"` to `MARKETING_VERSION: "0.7.0"`.

- [ ] **Step 2: Clean build + full test**

```bash
cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation
rm -rf ~/Library/Developer/Xcode/DerivedData/JuiceScreen-*
xcodegen generate >/dev/null 2>&1
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build 2>&1 | tail -3
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST SUCCEEDED|TEST FAILED" | tail -2
```

Expected: build + tests succeed (~218 unit tests).

- [ ] **Step 3: Manual smoke test (HUMAN STEP)**

| # | Action | Expected |
|---|---|---|
| 1 | Launch app, record a 10–15s video via ⌘⇧5 | MP4 saved to ~/Pictures/JuiceScreen/<today>/ |
| 2 | Press ⌘⇧L → library window | Tile shows "MP4" badge + first-frame thumbnail |
| 3 | Click tile | Inspector slides in; **Duration** field shows the recording length (e.g. "12.345s") |
| 4 | Double-click tile | Trim Editor window opens; AVPlayer shows the video paused on the first frame |
| 5 | Click Play | Video plays; playhead advances on the scrubber |
| 6 | Drag the left handle right by ~25% | Start of trim range moves; player jumps to new start |
| 7 | Drag the right handle left | Same for end |
| 8 | Click Play | Plays only the trimmed sub-range, then stops at the end handle |
| 9 | Click Save Trim (⌘S) | Progress bar appears briefly; on completion, Finder reveals the new `<original>-trimmed.mp4` |
| 10 | Open the trimmed file in QuickTime | Plays back the chosen sub-range only |
| 11 | Trim the same source again with Save Trim As… | Save panel opens; choose new location, file written there |
| 12 | Refresh library window (close + reopen) | The trimmed-output file does NOT auto-import as a new library row in v0.7 (it's a separate file in Pictures/ but won't get a CaptureRow until the user re-captures or until v0.9 adds "Re-import from disk") |

If any step fails, do **not** tag.

- [ ] **Step 4: Commit + tag**

```bash
git add VERSION project.yml
git commit -m "chore: bump VERSION to 0.7.0"
git tag -a v0.7.0 -m "Trim + post-record milestone: AVPlayer scrubber + AVAssetExportSession"
git tag -l v0.7.0
```

- [ ] **Step 5: Verify clean tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Task 15: Update spec doc with Plan 7 status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Update Plan 7 line**

Replace `⬜ Plan 7: Trim + post-record` with:

```
- ✅ **Plan 7: Trim + post-record** (v0.7.0, 2026-05-05) — Double-click a video tile in the library to open the Trim Editor: AVPlayer preview + custom SwiftUI scrubber (background track + selected sub-range fill + 2 draggable handles + playhead) + transport toolbar (Play/Pause / Reset / Save Trim / Save Trim As). TrimRange value type with CMTime bounds + minimum-duration validation + clamping. TrimViewModel @Observable with periodic time observer. AVAssetExportSession at AVAssetExportPresetHighestQuality writes the trimmed MP4 H.264. Save Trim writes alongside as `<basename>-trimmed.mp4` (with -1, -2 suffix on collision); Save Trim As opens NSSavePanel. CaptureRow.durationMs now populated for all video imports via AVAsset.duration; InspectorView shows the Duration metadata row. Audio waveform display + multi-region split + frame-stepping deferred to v1.1. ~218 unit tests
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 7 (Trim + post-record) complete in implementation status"
```

---

## Plan completion checklist

- [ ] `git tag -l` shows v0.1.0 → v0.7.0
- [ ] `xcodebuild test -only-testing:JuiceScreenTests` is green (~218 tests)
- [ ] All 12 manual smoke-test items pass
- [ ] A `<basename>-trimmed.mp4` file plays back the chosen sub-range only

When everything checks out: ship v0.7.0 alpha. Plan 8 is next — the highest-risk module: scroll capture with frame stitching.
