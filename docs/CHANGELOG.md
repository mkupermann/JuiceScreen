# Changelog

All notable changes to JuiceScreen are documented here. This project follows [Semantic Versioning](https://semver.org/) and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

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
