# Changelog

All notable changes to JuiceScreen are documented here. This project follows [Semantic Versioning](https://semver.org/) and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [1.0.0] — 2026-05-06

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
