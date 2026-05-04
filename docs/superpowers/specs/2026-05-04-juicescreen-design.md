# JuiceScreen — Design Spec

**Date:** 2026-05-04
**Status:** Brainstorming approved → ready for implementation plan
**Owner:** mkupermann

---

## Wedge

An open-source, 100% local, modern-but-minimal screen capture app for macOS. Differentiates from CleanShot X on four axes:

1. **Open source** (MIT licensed)
2. **100% local** — zero network calls except Sparkle update checks; no telemetry, no cloud, no analytics, no crash reporter
3. **Lean feature set** — only what's actually used: capture (region/window/full/last + scroll), record video (with audio + cursor polish), annotate, OCR, export
4. **Modern minimal UI** — no AI slop, no feature bloat, no dated chrome

Explicitly NOT goals: cloud sync, team sharing, integrations with third-party services, AI features beyond local OCR, GIF export, webcam overlay, multi-monitor recording orchestration.

## Out of scope for v1 (deferred to v1.1+)

- Vector PDF export (v1 rasterizes annotations into the PDF)
- Webcam picture-in-picture overlay during recording
- Multi-monitor recording (region/window only span one display in v1)
- App-window capture mode (the "pick this Safari window" picker)
- Step counter / callout / drop shadow / magnifier annotations (CleanShot's "power" annotation set)
- OCR on video frames
- Tags / collections / manual organization
- iCloud/Dropbox sync of library
- Sparkle "beta" update channel (single stable channel only)

---

## Tech stack

| Concern | Choice |
|---|---|
| Language | Swift 5.10+ / Swift 6 |
| UI framework | SwiftUI (with AppKit where needed: capture overlay, menu bar) |
| Screen capture | ScreenCaptureKit (macOS 14+) |
| OCR | Vision framework (`VNRecognizeTextRequest`) |
| Storage | SQLite + FTS5 via `GRDB.swift` (handles WAL, FTS5, migrations, async/await) |
| Hotkeys | Carbon `RegisterEventHotKey` (only working API for global shortcuts) |
| Auto-update | Sparkle 2.x with EdDSA-signed updates (works on unsigned apps) |
| Min macOS | macOS 14 Sonoma |
| Bundle ID | `com.bks-lab.juicescreen` |
| App name | JuiceScreen |
| Repo | `github.com/mkupermann/JuiceScreen` |
| License | MIT |
| Distribution | Unsigned ad-hoc DMG via GitHub Releases |

---

## Architecture

### Process model

Single macOS app, single binary, runs as a menu-bar accessory (`LSUIElement = true`). When the main window is open, app temporarily switches to `.regular` activation policy so it shows in the Dock and ⌘-Tab; reverts to `.accessory` when the last window closes (Things/Bear pattern).

### Module layout (Approach 1: monolithic single-target with disciplined folder boundaries)

```
JuiceScreen.app
├── App/                  // App entry, lifecycle, dependency wiring
├── MenuBar/              // NSStatusItem, dropdown menu, hotkey registration
├── Capture/              // ScreenCaptureKit wrappers, region picker overlay
│   ├── Image/            //   region/window/full-screen/last-region still capture
│   ├── Video/            //   screen recording with audio + cursor overlay
│   └── Scroll/           //   scroll-capture frame stitcher (highest-risk module)
├── Annotation/           // Editor view, tools, undo, export to PNG/JPG/PDF
├── OCR/                  // Vision framework wrapper, runs async on capture
├── Library/              // SQLite + FTS5 index, capture records, search
├── MainWindow/           // SwiftUI library browser (two-pane), settings, OCR results
├── Preferences/          // UserDefaults wrapper, settings model
├── Permissions/          // TCC checks, first-run wizard, deep-links to Settings
└── Shared/               // Value types (CaptureRecord, etc.), utilities
```

### Communication rules

The discipline that prevents Approach 1 from rotting:

- Modules talk through **value types only** (`struct CaptureRecord`, `struct AnnotationDocument`)
- No module imports another module's view code
- Library is the only module that touches SQLite; everyone else hands it `CaptureRecord` values
- Capture is the only module that touches ScreenCaptureKit; everyone else gets `NSImage` / `URL` back
- All side effects (file IO, DB writes, hotkey registration) at the edges; pure logic in the middle
- Code is written as if modules were going to be extracted into Swift Packages later — keeps that refactor path open

### Data flow for a typical capture

```
hotkey → MenuBar → Capture.Image → NSImage + metadata
                              ↓
                   Annotation editor opens (sync, dedicated NSWindow)
                              ↓
        OCR runs in background (Vision) ──┐
                              ↓            │
   user clicks Save → export to disk      │
                              ↓            ↓
                   Library inserts row + FTS5 OCR text
```

---

## Capture pipeline

### Image capture (region / window / full / last-region)

All four modes use ScreenCaptureKit:
- One-shots via `SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14+)
- Live preview overlays via `SCStream`

**Region:** custom `NSWindow` overlay covering all displays (transparent, mouse-capturing). User drags a rectangle, we exclude our own overlay window from `SCContentFilter`. Magnifier loupe at the cursor for pixel-precision. Snaps to detected window edges within 8px (uses ScreenCaptureKit window list — no AX needed).

**Window:** `SCContentSharingPicker` (macOS 14+) — Apple-provided, gets the window list with TCC consent already wired.

**Full screen:** if multi-display, tiny picker; else direct.

**Last region:** persist last `CGRect` to UserDefaults; hotkey re-fires same coordinates without overlay UI.

### Video recording

`SCStream` with `SCStreamConfiguration` (60fps target, BGRA). Output to `AVAssetWriter` (H.264 MP4).

- **System audio:** `SCStreamConfiguration.capturesAudio = true` (macOS 13+), mixed into asset writer's audio track
- **Microphone:** separate `AVCaptureSession` feeding the same writer (or second track mixed at finalize). Toggle in start panel
- **Cursor highlight ring (default ON, no extra permission):** `NSEvent.mouseLocation()` polled at 50Hz returns cursor position from public API and does not require Input Monitoring. CALayer-rendered ring drawn onto each captured frame in `SCStreamOutput` callback before frame hits the asset writer
- **Click pulse (default OFF, opt-in):** click event detection requires `CGEventTap` (or `NSEvent.addGlobalMonitorForEvents`), which triggers macOS Input Monitoring permission on macOS 10.15+. To preserve the "no extra permission needed by default" promise, click pulse is OFF by default. First time user enables it in Settings, app prompts for Input Monitoring and explains why
- **Keystroke display (default OFF, opt-in):** `CGEventTap` for key events, render last 3 keystrokes as translucent corner overlay. Same Input Monitoring prompt as click pulse. Off by default
- **Trim handles (post-record):** `AVPlayer` + start/end handles, then `AVAssetExportSession` to write trimmed copy
- No GIF export. No webcam overlay. No multi-monitor.

### Scroll capture (highest-risk module)

Capture-during-scroll with overlap stitching:

1. User initiates scroll capture
2. Prompt: "scroll the window slowly"
3. `SCStream` captures frames at ~10fps while user scrolls
4. Between consecutive frames, run normalized cross-correlation on a horizontal mid-strip to find vertical displacement
5. Stitch by overlaying with detected offset
6. User presses Esc to finish

**Honest known failure modes (documented in README, not papered over):**

- Sticky headers/footers → ghosting at the seam (mitigation: user-marked sticky region mask, v1.1 feature)
- Parallax / lazy-loaded content that changes during scroll → torn images
- Web pages with infinite scroll → no clean stop signal; user manually presses Esc

**Honest scope statement:** scroll capture in v1 will work cleanly on ~70% of real-world cases (most native macOS apps, simple web pages). It will visibly fail on the other 30%. That's what CleanShot ships too.

### Region picker overlay details

- Dimming: 35% black on excluded area, full transparency on selected rectangle
- Live pixel dimensions near cursor (`1024 × 768`)
- Snaps to window edges within 8px
- Esc cancels; Enter or release captures
- Arrow keys nudge by 1px (Shift+arrow by 10px) after initial drag

---

## Annotation editor

### Window model

Each capture opens a **dedicated `NSWindow`** (not a tab in the main window). Allows multiple captures open simultaneously.

### Canvas

SwiftUI `Canvas` for rendering (GPU-backed via Metal). Underlying model is a stack of `AnnotationLayer` value types — pure data, easy to undo/redo by snapshotting the stack.

### Tool palette (left rail, single column)

| Tool | Behavior |
|---|---|
| Select | Click selects existing annotation; drag handles to resize/reposition |
| Arrow | Click-drag, single-headed arrow with adjustable thickness |
| Double arrow | Same, both ends |
| Line | Same, no arrow head |
| Rectangle | Hollow or filled (toggle in top bar) |
| Ellipse | Same |
| Pen (freehand) | Smoothed curves, configurable thickness |
| Highlighter | Translucent yellow/configurable, draws over content |
| Text | Click to drop, type, choose font/size/color |
| Blur / Pixelate | Drag region, Gaussian blur or pixelate (toggle). **Destructive at export** — pixels actually replaced before encoding so recipients cannot un-blur |
| Crop | Drag rectangle, exports only that region |

### Top bar (context-sensitive)

Color picker, thickness slider, fill toggle, font size — only shows controls relevant to selected tool or selected annotation.

### Canvas interactions

- Selected annotations show 8-point handles + rotation handle above
- Click empty space → deselect
- ⌘Z / ⌘⇧Z undo/redo (snapshot-based, unlimited within session, dropped on close)
- Delete / Backspace removes selected annotation
- ⌘D duplicates selected annotation
- Shift while drawing → constrain to perpendicular / 45° / square / circle
- Option while resizing → resize from center

### Layer model

```swift
struct AnnotationDocument {
    let baseImage: NSImage          // original capture, never mutated
    var layers: [AnnotationLayer]   // ordered, drawn bottom-to-top
    var canvasCrop: CGRect?         // nil = no crop, set = export only this rect
}

enum AnnotationLayer {
    case arrow(ArrowProps)
    case line(LineProps)
    case rect(RectProps)
    case ellipse(EllipseProps)
    case freehand(FreehandProps)
    case text(TextProps)
    case blur(BlurProps)            // destructive at export
}
```

Serializable to JSON for future "edit a saved capture later" (not in v1).

### Export pipeline

Toolbar primary button: **Save** (defaults to PNG; cmd-click for format menu).

- **PNG:** `NSBitmapImageRep` → `representation(using: .png, properties:)`
- **JPG:** same with `.jpeg`, quality slider in settings (default 0.9)
- **PDF:** rasterize flattened image into single-page `PDFKit.PDFDocument`. True vector PDF deferred to v1.1.

Save destination defaults to configured save folder with timestamp filename. "Save As..." opens `NSSavePanel`.

### Quick actions (top-right of editor)

- Copy to clipboard (always PNG, ⌘C)
- Save (⌘S)
- Save As (⌘⇧S)
- Show in Finder
- Discard (⌘W with confirmation if edited)

---

## Library, storage, OCR

### File layout on disk

```
~/Pictures/JuiceScreen/                    ← user-configurable
├── 2026-05-04/
│   ├── JuiceScreen_2026-05-04_at_14.32.18.png
│   ├── JuiceScreen_2026-05-04_at_14.32.18.json    ← annotation document (optional)
│   └── JuiceScreen_2026-05-04_at_15.10.44.mp4
└── 2026-05-05/
    └── ...

~/Pictures/JuiceScreen/.trash/             ← soft-deleted captures, GC'd after 30 days

~/Library/Application Support/JuiceScreen/
├── library.sqlite                ← FTS5 index, capture metadata
├── library.sqlite-wal            ← WAL mode (safe concurrent reads)
└── thumbnails/                   ← 256x256 JPG thumbnails for grid view
    └── <capture_uuid>.jpg
```

**Storage split rationale:** content in `~/Pictures` so users can browse in Finder, sync via iCloud Drive if they choose, back up trivially. SQLite index in Application Support because it's app state — deleting it never loses captures (app rebuilds index by re-OCR'ing files on disk; runs on demand on first launch after corruption).

### SQLite schema

```sql
CREATE TABLE captures (
    uuid TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,            -- absolute path to PNG/MP4
    annotation_path TEXT,               -- nullable, JSON sidecar
    thumbnail_path TEXT NOT NULL,
    media_type TEXT NOT NULL,           -- 'image' | 'video'
    captured_at INTEGER NOT NULL,       -- unix epoch
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    duration_ms INTEGER,                -- nullable, video only
    file_size_bytes INTEGER NOT NULL,
    source_app TEXT,                    -- nullable, e.g., "Safari"
    deleted_at INTEGER                  -- soft delete; nullable
);

CREATE VIRTUAL TABLE captures_fts USING fts5(
    uuid UNINDEXED,
    ocr_text,
    source_app,
    content='',
    tokenize='porter unicode61'
);

CREATE INDEX idx_captures_captured_at ON captures(captured_at DESC);
CREATE INDEX idx_captures_deleted_at ON captures(deleted_at) WHERE deleted_at IS NULL;
```

`captures` and `captures_fts` updated in a single transaction after OCR completes.

### OCR pipeline

- Async after every still capture (NOT videos — deferred)
- `VNRecognizeTextRequest` (Vision framework):
  - `recognitionLevel = .accurate`
  - `usesLanguageCorrection = true`
  - `recognitionLanguages = ["en-US", "de-DE"]` (configurable; defaults match user's system languages)
  - `automaticallyDetectsLanguage = true` if available (runtime check)
- Background `DispatchQueue` (QoS `.utility`) — never blocks UI or annotation
- Result: concatenated string written to `captures_fts.ocr_text`. Per-region bounding boxes kept in sidecar JSON for OCR-results panel
- **Fallback:** if OCR fails (truly blank image, all-icon shot), write `null` to `ocr_text`. Capture still searchable by date / source app / filename

### Search UX (main window search bar)

Auto-detected query types:

- `aws error` → FTS5 match against `ocr_text`
- `from:safari` → filter `source_app = 'Safari'`
- `before:2026-04-01`, `after:2026-04-15` → date range filter
- `type:video` → only videos
- Combined: `aws error from:safari after:2026-04-15` works as expected

Ranked by FTS5 BM25 + recency boost.

### Library window UI (two-pane)

```
┌──────────────┬─────────────────────────────────────────────────┐
│              │                                                 │
│   Sidebar    │          Library Grid                           │
│              │                                                 │
│  • All       │  [search bar                                ]   │
│  • Today     │                                                 │
│  • This Wk   │  [responsive thumbnail grid, ~150px tiles]      │
│  • Videos    │                                                 │
│  • Images    │  Each tile: thumbnail, time-ago label,          │
│  • Trash     │  format badge (PNG/MP4), ⋯ menu                 │
│              │                                                 │
│  ───────     │  Click → opens annotation editor (or video      │
│              │  player for MP4)                                │
│  Settings    │                                                 │
│              │  Right-click → Reveal in Finder, Copy file,     │
│              │  Copy OCR text, Move to Trash (30-day grace)    │
│              │                                                 │
│              │  Inspector slides in from right when tile       │
│              │  selected (collapsible)                         │
│              │                                                 │
└──────────────┴─────────────────────────────────────────────────┘
   ~180pt              flexible
```

**Inspector (slide-in from right when capture selected):**
- Capture metadata (dimensions, file size, source app, captured at)
- OCR text with click-to-copy per region, plus "Copy all"
- Action buttons (Open in Editor, Reveal in Finder, Copy, Delete)
- Highlights search-matching regions when arrived from a search query

### Soft delete

Move-to-trash sends file to `~/Pictures/JuiceScreen/.trash/`. Garbage-collected after 30 days. "Empty trash now" button in Settings → Storage.

---

## Menu bar, hotkeys, main window

### Menu bar item (`NSStatusItem`)

Custom monochrome SF-Symbol-style template image (no impersonating system UI). Click → dropdown:

```
Capture Region              ⌘⇧4
Capture Window              ⌘⇧2
Capture Full Screen         ⌘⇧3
Capture Last Region         ⌘⇧R
─────────────────────────────────
Record Screen               ⌘⇧5
─────────────────────────────────
Open Library                ⌘⇧L
─────────────────────────────────
Recent Captures           ▶  (submenu of last 5)
─────────────────────────────────
Preferences…                ⌘,
Quit JuiceScreen            ⌘Q
```

- Right-click → quick toggle: "Pause hotkeys" (useful when sharing screen)
- During active recording: red dot on icon, first menu item becomes "Stop Recording" (also globally hotkey'able)

### Hotkey registration

- Wrapper around Carbon `RegisterEventHotKey` (only working API for global shortcuts; AppKit has no replacement)
- Persisted in UserDefaults as keycode + modifier mask
- Settings UI: each row has a "Record" button — click, press combo, validate (must include modifier; warn on conflicts with known macOS shortcuts)

### First-run wizard for hotkey conflicts

Strategy B (replace macOS defaults):

1. Detect whether ⌘⇧3/4/5 are still bound to system screenshots
2. Show panel: *"JuiceScreen wants to use ⌘⇧3, ⌘⇧4, and ⌘⇧5 for its capture shortcuts. macOS currently uses these for the built-in screenshot tool. To let JuiceScreen claim these, open Keyboard Settings and uncheck 'Save picture of screen as a file', etc."*
3. Buttons: `[Open Keyboard Settings]` (deep-link via `x-apple.systempreferences:com.apple.Keyboard-Settings.extension`) `[Use alternative defaults instead]` `[Skip]`
4. Skippable — user can keep alternative defaults if they don't want to disable system shortcuts

### Main window — settings panel (standalone window, tabs)

- **General** — start at login, default save folder, default file format, JPG quality
- **Capture** — annotation tool defaults, image scale (1× retina vs 2×), include cursor in stills (yes/no)
- **Recording** — codec/bitrate, fps target (30/60), audio defaults, cursor highlight ring color/size (default ON, no extra permission), click pulse toggle (default OFF, prompts for Input Monitoring on enable), keystroke display toggle (default OFF, prompts for Input Monitoring on enable)
- **Hotkeys** — full table of bindings, record-to-set
- **Storage** — current usage stats, "Open save folder", "Empty trash now", OCR language list
- **About** — version, GitHub link, license, "Check for updates"

### Welcome panel (first run, brutal-minimal, dismissible once)

```
Press ⌘⇧4 to capture a region
Press ⌘⇧5 to record your screen
Open the Library with ⌘⇧L

[Got it]
```

---

## Permissions & first-run flow

### TCC permissions

| Permission | Required for | Requested when |
|---|---|---|
| Screen Recording (`kTCCServiceScreenCapture`) | Every capture | First launch, blocking — app cannot function without it |
| Microphone (`kTCCServiceMicrophone`) | Recording with mic enabled | First time user toggles mic on during recording |
| Input Monitoring (`kTCCServiceListenEvent`) | Click pulse during recording, keystroke display overlay | First time user enables either feature in Settings (both default OFF) |
| Accessibility (`kTCCServiceAccessibility`) | NOT NEEDED in v1 — Input Monitoring is sufficient for the listen-only event taps we use | n/a |

### Honest macOS 15+ note

Apple added a weekly prompt asking users to re-confirm screen recording permission. We can't suppress this. README documents it: *"If macOS asks weekly to confirm screen recording, this is Apple's choice, not ours."*

### First-run flow

```
1. App launches → check if screen recording permission granted
   ├─ Granted → continue to step 2
   └─ Not granted → show modal with grant button + relaunch instruction

2. Hotkey conflict check (see "First-run wizard" above)

3. Welcome panel (brutal minimal, dismissible)

4. App ready. Menu bar icon visible. Hotkeys live.
```

### Permission revocation handling

ScreenCaptureKit returns authorization error → non-modal banner in menu bar dropdown: *"Screen recording was disabled. [Re-enable]"* → opens Privacy settings deep link. Never silently re-prompt or pop modals during other work.

### Permissions module API

```swift
enum PermissionStatus { case granted, denied, notDetermined }

protocol PermissionsService {
    func screenRecording() -> PermissionStatus
    func microphone() -> PermissionStatus
    func inputMonitoring() -> PermissionStatus
    func requestScreenRecording() async -> PermissionStatus
    func requestMicrophone() async -> PermissionStatus
    func requestInputMonitoring() async -> PermissionStatus
    func openSettingsFor(_ permission: PermissionType)
}
```

Concrete impl + a fake for tests. Capture/Recording modules depend only on the protocol.

---

## Build, DMG packaging, Sparkle

### Repository layout

```
JuiceScreen/
├── JuiceScreen.xcodeproj/
├── JuiceScreen/                    ← app source (mirrors module folders)
├── JuiceScreenTests/
├── JuiceScreenUITests/
├── Resources/
│   ├── Assets.xcassets
│   └── Info.plist
├── scripts/
│   ├── build-release.sh            ← xcodebuild → archive → export
│   ├── make-dmg.sh                 ← creates .dmg from .app
│   ├── sign-update.sh              ← signs DMG with Sparkle EdDSA private key
│   └── update-appcast.sh           ← regenerates appcast.xml
├── appcast/
│   └── appcast.xml                 ← Sparkle update feed (committed, served via GitHub Pages)
├── docs/
│   ├── README.md                   ← installation, "right-click → Open" instructions
│   ├── CHANGELOG.md
│   ├── QA-CHECKLIST.md             ← manual test checklist for each release
│   └── superpowers/specs/          ← design docs (this file)
├── .github/
│   └── workflows/
│       ├── ci.yml                  ← runs tests on every PR
│       └── release.yml             ← on tag push: build, DMG, draft GitHub Release
├── VERSION                         ← single source of truth for version number
├── LICENSE                         ← MIT
└── README.md
```

### Release build chain

```
xcodebuild archive
    → exports JuiceScreen.app (Release config, optimized, debug symbols stripped)
    → scripts/make-dmg.sh wraps it in JuiceScreen-1.2.3.dmg
        (uses `create-dmg` Homebrew tool)
        Adds: background image with arrow pointing at /Applications,
              custom volume icon, eject script
    → scripts/sign-update.sh signs the DMG with Sparkle EdDSA private key
        Output: signature string
    → scripts/update-appcast.sh appends a new <item> to appcast.xml with:
        version, release date, download URL (GitHub Releases),
        file size, EdDSA signature, release notes (from CHANGELOG.md latest entry)
    → commits appcast.xml change (NOT the DMG — DMG goes to GitHub Release)
```

### Sparkle setup

- Sparkle 2.x via Swift Package Manager
- EdDSA keypair generated locally with `generate_keys` (Sparkle's tool); private key stored encrypted in user's password manager (not in repo, not in CI), public key bundled in app's Info.plist as `SUPublicEDKey`
- Appcast URL: `https://mkupermann.github.io/JuiceScreen/appcast.xml`
- Single "stable" channel for v1
- Update check policy: on launch + every 24h while running, user-configurable in Settings (or fully disable)
- Settings UI: "Check for Updates Now" button, "Auto-check" toggle, "Last checked: …"

### GitHub Actions CI

```yaml
# ci.yml — runs on every PR
- macos-15 runner
- xcodebuild test (unit + UI tests)
- swiftlint (cosmetic only — warnings, not failures)

# release.yml — runs on git tag push (vX.Y.Z)
- macos-15 runner
- xcodebuild archive + export
- scripts/make-dmg.sh
- Upload DMG to GitHub Release as draft (manual publish step)
- ❗ EdDSA signing happens LOCALLY, not in CI — private key never touches GitHub
- Manual step after CI: maintainer downloads DMG, runs sign-update.sh locally,
  commits appcast.xml, pushes
```

**Local-signing rationale:** putting the EdDSA private key in GitHub Secrets means anyone with repo admin access can sign updates. For a one-maintainer OSS project, keeping the key local and doing sign+appcast manually after each release is more secure and adds 2 minutes per release.

### Versioning

Semantic versioning (MAJOR.MINOR.PATCH). Tags as `v1.0.0`. `CFBundleShortVersionString` driven from a single `VERSION` file at repo root, read by both the build and `update-appcast.sh`.

### README installation section (verbatim)

```
## Installing
1. Download JuiceScreen-X.Y.Z.dmg from Releases.
2. Open the DMG, drag JuiceScreen.app to /Applications.
3. First launch: macOS will block it because it's not signed.
   Right-click JuiceScreen.app in /Applications → Open → confirm.
   On macOS 15+: System Settings → Privacy & Security → "Open Anyway".
4. Grant Screen Recording permission when prompted.
5. Done.
```

### Privacy guarantee — enforced architecturally

The app links no networking framework beyond what Sparkle requires. The **only** outbound network calls JuiceScreen ever makes are:

1. Sparkle fetching the appcast XML from `https://mkupermann.github.io/JuiceScreen/appcast.xml` (default: on launch + every 24h; user can fully disable in Settings)
2. Sparkle downloading a new DMG from `github.com` when the user clicks "Install Update"

That's the entire network surface. No telemetry. No analytics. No crash reporter. No third-party SDKs. A user who disables auto-update in Settings has an app that makes zero network calls — verifiable with Little Snitch / Lulu.

---

## Testing strategy & error handling

### Testing layers

| Layer | What | Tools | Coverage target |
|---|---|---|---|
| Pure unit tests | Annotation layer math, search query parser, filename pattern formatter, image stitching algorithms | XCTest | High (~85%+) |
| Module integration tests | Library DB writes + FTS5 search round-trips, OCR result parsing, hotkey persistence | XCTest with in-memory SQLite + fixture images | Medium |
| UI tests | Smoke tests only — app launches, menu bar icon appears, main window opens, settings tabs reachable | XCUITest | Low (canary, not coverage) |
| Manual checklist | Capture flows, recording, annotation tools, exports, permission flows, first-run wizard, hotkey conflict wizard, Sparkle install | `docs/QA-CHECKLIST.md`, run before every release | Manual |

### Explicitly NOT tested automatically

- ScreenCaptureKit itself (system framework, can't reliably stub in CI)
- Pixel-level capture content comparison (brittle on CI runners)
- Sparkle update flow end-to-end (CI can't simulate "user clicks Install Update and app relaunches")

These get the manual checklist treatment. CONTRIBUTING.md documents this so contributors know which changes need manual verification.

### Test fakes

- `PermissionsService` → `FakePermissionsService` (configurable status responses)
- `CaptureEngine` protocol → `FakeCaptureEngine` returning fixture `NSImage`s
- `OCREngine` protocol → `FakeOCREngine` returning canned text
- `LibraryStore` → real SQLite, in-memory connection (`:memory:`)

### Error handling philosophy

| Error class | Behavior |
|---|---|
| Recoverable user errors (no permission, hotkey collision, disk full, file in use) | Inline non-modal banner in relevant UI surface; clear next-action button. NEVER a sheet that blocks workflow |
| Recoverable system errors (transient SCK failure, OCR timeout) | Retry once, then log + small toast. Don't fail loudly for transient issues |
| Programmer errors (preconditions violated, impossible state) | `assertionFailure` in debug builds, `os_log(.error)` in release (degrades gracefully) |
| Fatal errors (corrupted SQLite, FS unwritable) | Modal: "JuiceScreen couldn't open its library. [Reset Library] [Reveal in Finder] [Quit]". Reset rebuilds from disk |

### No crash reporter / no telemetry

Per the no-network promise. Users report crashes via GitHub issue with the macOS crash log (auto-saved to `~/Library/Logs/DiagnosticReports/`).

### Logging

- `os_log` with subsystem `com.bks-lab.juicescreen`, categorized per module
- Default level: `.info`; `.debug` only when user enables "Verbose logging" in Settings (off by default)
- Logs viewable via Console.app — standard macOS pattern
- Log rotation handled by OS

### Performance budgets

- Region capture overlay → first paint: < 50ms (must feel instant)
- Capture → annotation editor open: < 200ms for typical 4K screenshot
- OCR completion: best-effort, ~1–3s typical, runs in background
- Library grid: 60fps scroll with 1000 items (LazyVGrid + thumbnail cache)
- App cold launch → menu bar icon visible: < 500ms

### Honest known-limitations list (in README)

- Scroll capture fails on ~30% of complex web pages (sticky headers, lazy-load, parallax)
- macOS 15+ may re-prompt for Screen Recording permission weekly (Apple's behavior)
- No iCloud sync of library (by design — local-only)
- No support for macOS < 14
- Vector PDF export rasterized in v1
- App is unsigned — first launch requires right-click → Open

---

## Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Scroll capture quality below user expectations | High | Medium | Document failure modes in README; ship anyway; iterate based on real-world reports |
| ScreenCaptureKit API changes between macOS releases | Medium | High | Pin to documented API surface; gate new APIs behind `#available` checks |
| macOS 15+ weekly TCC re-prompt erodes trust | High | Low | Document Apple's behavior in README; provide one-click re-grant flow |
| EdDSA private key leaks | Low | Catastrophic (attackers can ship signed updates) | Local-only signing; encrypted password manager storage; key rotation plan documented |
| Unsigned DMG scares off non-technical users | Certain | Medium | Clear README install steps with screenshots; consider $99/yr Apple Developer account if user base grows |
| Sparkle appcast tampering | Low | High | EdDSA signature verification; HTTPS-only via GitHub Pages |
| OCR misses text in low-contrast / unusual fonts | Medium | Low | Vision framework limitation; not blocking; users still get filename + date search |
| SQLite corruption | Low | Medium | WAL mode, transaction discipline, "Reset Library" recovery path that rebuilds from disk |
| Annotation editor performance on 8K screenshots | Medium | Low | Canvas/Metal-backed rendering should handle this; benchmark in QA |

---

## Implementation milestones (rough sequencing for the plan)

The implementation plan will detail tasks per milestone. Rough phasing:

1. **Foundation** — Xcode project, module folders, dependency wiring, Permissions service, menu bar shell
2. **Image capture** — region/window/full-screen/last-region, region picker overlay, save to disk
3. **Annotation editor** — canvas, tool palette, undo/redo, PNG/JPG export
4. **Library + storage** — SQLite schema, FTS5, thumbnail generation, library window
5. **OCR** — Vision integration, async pipeline, search query parser
6. **Video recording** — SCStream + AVAssetWriter, audio, cursor highlight composite, click pulse
7. **Trim + post-record** — AVPlayer trim handles, AVAssetExportSession
8. **Scroll capture** — frame stitcher, the highest-risk module
9. **PDF export** — rasterized PDF via PDFKit
10. **Settings UI + first-run wizard + Sparkle integration**
11. **Build pipeline** — xcodebuild scripts, create-dmg, signing, appcast generator, GitHub Actions
12. **QA pass + README + ship v1.0.0**

---

## Open questions for v1.1+

(Documented here so they don't get lost; explicitly NOT in scope for v1.)

- True vector PDF export (annotations as PDF paths, text as selectable text)
- App-window-by-name capture mode
- Step counter / callout / drop shadow / magnifier annotations
- Webcam picture-in-picture during recording
- Multi-monitor recording
- OCR on video frames (transcribe what's on screen during a video)
- Tags / collections / manual organization in library
- Sticky-region masks for scroll capture (mitigation for the 30% failure case)
- Beta update channel
- Code signing + notarization (if user base grows enough to warrant $99/yr)

---

## Implementation status (updated as plans complete)

- ✅ **Plan 1: Foundation** (v0.1.0, 2026-05-05) — XcodeGen project, menu-bar accessory app, Permissions service (Live + Fake), Carbon hotkey wrapper, ActivationPolicyController, MenuBarController + dropdown builder, Preferences value type + UserDefaults-backed store, first-run flow (4-state coordinator + 3 SwiftUI views + window host), Settings stub with 6 tabs, GitHub Actions CI, README, UI smoke test scaffolding. 26 unit tests passing across 6 suites. UI tests deferred until Apple Developer ID is available (ad-hoc signing causes team-ID mismatch on macOS 26 UI test runner)
- ⬜ Plan 2: Image capture
- ⬜ Plan 3: Annotation editor
- ⬜ Plan 4: Library + storage
- ⬜ Plan 5: OCR + search
- ⬜ Plan 6: Video recording
- ⬜ Plan 7: Trim + post-record
- ⬜ Plan 8: Scroll capture
- ⬜ Plan 9: PDF export + Sparkle + Settings completion
- ⬜ Plan 10: Build pipeline + ship v1.0.0
