# Changelog

All notable changes to JuiceScreen are documented here. This project follows [Semantic Versioning](https://semver.org/) and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [1.0.6] — 2026-05-06

### Fixed
- Region selection rendered mirrored relative to the cursor after the app had been quit and relaunched once Screen Recording permission was registered. Cause: AppKit/SwiftUI coordinate translation in the NSEvent-driven picker drifted whenever macOS adjusted safe-area insets between launches. Rewrote the picker to drive the drag entirely from SwiftUI's `DragGesture` inside a `GeometryReader` — gesture coords and rendering coords are guaranteed to share the same `proxy.size` rectangle, so the selection always tracks the cursor regardless of permission state, launch number, or screen.

## [1.0.5] — 2026-05-06

### Fixed
- Editor canvas was visibly too tall on Macs with displays whose backing scale isn't exactly 2×. The capture engine constructed `NSImage` with a hardcoded `/2` divisor, which is correct for typical Retina but wrong on 1×, 1.5×, or 3× displays. Now reads the captured `SCDisplay`'s matching `NSScreen.backingScaleFactor` and divides by the actual value.

## [1.0.4] — 2026-05-06

### Fixed
- Region picker only worked on one display in multi-monitor setups. macOS does not reliably draw or accept events in a single window that spans multiple displays — the overlay was being anchored to one screen and the others were dark. `RegionPickerController` now creates one overlay per `NSScreen`, shares a single selection state in global screen coordinates, and renders per-screen-local coords. Drag from any display, and the selection follows the cursor across display boundaries.
- Settings window still opened blank on some macOS configurations even after the v1.0.3 `NavigationSplitView` rewrite. Replaced with a plain `HStack` (List-style sidebar on the left, selected tab's body on the right) — avoids both `TabView` and `NavigationSplitView` and renders consistently.

## [1.0.3] — 2026-05-06

### Fixed
- Settings window opened with a blank content area on macOS where SwiftUI's `TabView` outside the `Settings` scene renders empty. Rewritten as a `NavigationSplitView` (sidebar listing the six tabs, content in the detail pane) — matches the modern macOS Settings layout.
- Editor canvas size formula assumed a 2× backing scale and rendered too small on Macs with different display densities. Now reads `NSImage.size` directly (point-size, already accounts for the capture's backing scale) so the same image displays correctly across MacBook models.
- No way to delete a selected layer in the editor — `.onKeyPress(.delete)` requires view focus, which the editor doesn't always have. Added a Delete (`⌫`) button in the toolbar's right action group, bound via `Button.keyboardShortcut(.delete)` so it fires window-wide.
- No way to duplicate a selected layer either; added a Duplicate (`⌘D`) button next to Delete with the same focus-independent shortcut.

## [1.0.2] — 2026-05-06

### Fixed
- Drag-to-create and drag-to-move pushed one undo entry per drag tick, so a 30-pixel drag produced ~30 undo states. `⌘Z` undid one pixel of movement instead of the whole gesture. Drags now run as a single session: snapshot the document on first onChanged, mutate `current` directly during the drag, push exactly one undo entry on gesture end. Side benefit: the redo tail isn't cleared mid-drag any more.
- `⌘Z` / `⌘⇧Z` were not reaching the editor in the new top-toolbar layout. `.onKeyPress` requires view focus, which the editor doesn't always have. Bound the shortcuts to the visible Undo / Redo toolbar buttons via `Button.keyboardShortcut`, which fires at window level.
- Gaussian blur layers couldn't be selected — clicking on the visible soft halo missed the strict-rect hit-test. `HitTest.contains` now expands the hit region by `intensity` for gaussian blur; pixelate keeps the strict rect (sharp edges).
- Captured image rendered in the upper-left of the editor with a sea of grey filling the rest of the window. The canvas now centres inside its parent frame.
- Editor window chrome math was stale (assumed the old left-rail palette + single contextual row). Updated to match the two-row top toolbar plus 20pt canvas padding. Initial size capped at visible screen size minus 40pt margin so a 5K capture doesn't open offscreen.

## [1.0.1] — 2026-05-06

### Fixed
- App failed to launch on first install with `Library not loaded: @rpath/Sparkle.framework`. `xcodebuild`'s archive-export step preserved Sparkle.framework's upstream code signature, which carries a different team identifier than the ad-hoc-signed host app. macOS 14.4+ refuses to load mismatched frameworks into the host process. The release build script now runs `codesign --force --deep --sign -` after export so every embedded framework shares the host's ad-hoc identity. v1.0.0 DMGs are install-broken and superseded by this release.

### Changed (release pipeline only — no app behaviour change)
- `scripts/sign-update.sh` reads the EdDSA private key from the macOS keychain by default; `SPARKLE_ED_KEY` is now an optional override.
- `scripts/update-appcast.sh` passes the new `<item>` block via tmp file so macOS BSD `awk` accepts it (the previous `-v` form silently dropped the item).
- Appcast moved from `appcast/appcast.xml` to `docs/appcast.xml` so GitHub Pages can serve it (Pages allows only `/` or `/docs` source paths).
- `release.yml` declares `permissions: contents: write` so the workflow's `GITHUB_TOKEN` can create the draft release.

## [1.0.0] — 2026-05-06 — install-broken, superseded by 1.0.1

First public release.

### Capture
- Region capture (⌘⇧4), full-screen capture (⌘⇧3), last-region (⌘⇧R)
- Window capture via the macOS picker
- Scroll capture (⌘⇧6) — works cleanly on most native apps + simple web pages; ~30% of complex pages with sticky/lazy-load content produce visible artifacts. Documented honestly.

### Recording
- Full-screen video recording (⌘⇧5) at 30 or 60 fps
- System audio + microphone (separate tracks)
- Cursor highlight ring; optional click-pulse + last-3-keystrokes overlays (Input Monitoring required)
- Post-record trim editor for video files

### Annotation
- 11 tools: select/move, arrow, line, rectangle, ellipse, text, highlight, blur, freehand, redact, crop
- Layer model with undo/redo
- Save as PNG, JPG (with quality slider), or rasterized PDF
- Copy to clipboard, Save, Save As

### Library
- All captures and recordings indexed in a local SQLite database
- Local OCR via Apple's Vision framework (English + German), free-text + filter search (`from:Safari error after:2026-04-15 type:image`)
- Smart filters (All, Images, Videos, Trash); soft-delete with 30-day GC; Restore from inspector

### Settings
- Real Settings panel: General (start at login, save folder, default format, JPG quality), Capture (image scale, include cursor), Recording (every toggle persists), Hotkeys (read-only display), Storage (usage stats, Empty trash now), About (Sparkle Check for Updates)

### Privacy
- Zero telemetry, zero analytics, zero crash reporter, zero third-party SDKs except Sparkle (update checks only)
- Two and only two network calls: appcast XML fetch + DMG download. Verifiable with Little Snitch / Lulu.

### Distribution
- Unsigned DMG (no Apple Developer ID) — first launch requires right-click → Open
- Sparkle 2.x EdDSA-signed updates from GitHub Releases
- macOS 14 Sonoma minimum
