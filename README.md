# JuiceScreen

Open-source, 100% local screen capture for macOS. Region / window / full-screen / scroll capture, video recording with audio, annotation, OCR-indexed library search.

**Status:** v0.1.0 — Foundation milestone. Menu-bar shell, permissions flow, and Settings stub work. Capture functionality lands in subsequent milestones.

## Why

CleanShot X is excellent but proprietary. JuiceScreen aims to be the lean open-source alternative:

- **Open source** (MIT licensed)
- **100% local** — zero network calls except optional Sparkle update checks. No telemetry. No analytics. No crash reporter
- **Lean feature set** — only what's actually used
- **Modern minimal UI**

**v0.5 update — local OCR + search.** Every screenshot now runs through Apple's Vision framework on a background queue: extracted text and per-region bounding boxes land in a JSON sidecar at `~/Library/Application Support/JuiceScreen/ocr/<uuid>.json`, and the concatenated text is indexed in an FTS5 SQLite table. The library window's search bar accepts free text plus filters: `aws error from:Safari after:2026-04-15 type:image`. Vision runs entirely on-device — no text ever leaves the machine.

**v0.6 update — local video recording.** Press `⌘⇧5` to start a full-screen recording. ScreenCaptureKit captures the primary display at 60fps, system audio mixes in by default, and a yellow ring follows the cursor in every frame. Optional microphone capture and Input-Monitoring-gated overlays (click pulse, last-3-keystrokes chip in the corner) are available in Settings → Recording. A small floating control bar shows duration + a stop button. MP4 H.264 files land at `~/Pictures/JuiceScreen/<date>/JuiceScreen_<timestamp>.mp4` and appear as `.video` rows in the library. Trim handles + post-record editing arrive in v0.7.

**v0.7 update — trim post-record.** Double-click a video tile in the library to open the Trim Editor: AVPlayer-backed preview, custom scrubber with two draggable handles for the start and end of the keep-range, and Save Trim / Save Trim As buttons. AVAssetExportSession writes a new MP4 H.264 with the chosen range at highest quality. The library now stores per-video duration (`durationMs`), shown in the inspector.

**v0.8 update — scroll capture (with honest limits).** Press `⌘⇧6` to capture a scrolling area: pick a region, scroll slowly, press Esc. JuiceScreen captures frames at 10fps, stitches them into a tall PNG, and opens it in the editor. The stitcher uses brute-force sum-of-squared-differences over a horizontal mid-strip — works cleanly on most native macOS apps and simple web pages (~70% of cases). It will visibly fail on the other ~30%: pages with sticky headers/footers, lazy-loaded content, or parallax effects produce ghosting or torn images. Tools that hide this limitation are tools that lie. We list it here.

**v0.9 update — settings, PDF export, Sparkle wired.** The Settings panel is now real: General (start at login, save folder, default format, JPG quality), Capture (image scale, include cursor in stills), Recording (every toggle persists — fps, audio, cursor highlight, click pulse, keystrokes), Storage (usage stats, Open save folder, Empty trash now). The annotation editor's Save As dialog now offers PDF (rasterized — true vector PDF still v1.1). Sparkle 2.x is wired with `SUFeedURL` and an Info.plist `SUPublicEDKey` placeholder; the real EdDSA key, signed DMG, and the appcast at `https://mkupermann.github.io/JuiceScreen/appcast.xml` arrive in v1.0 (Plan 10). Until then the "Check for Updates Now" button will fail to find a feed — that is expected.

See `docs/superpowers/specs/2026-05-04-juicescreen-design.md` for the full design.

## Installing

1. Download `JuiceScreen-X.Y.Z.dmg` from [Releases](https://github.com/mkupermann/JuiceScreen/releases).
2. Open the DMG, drag `JuiceScreen.app` to `/Applications`.
3. **First launch will be blocked** because the app is not code-signed. Right-click `JuiceScreen.app` in `/Applications` → **Open** → confirm. On macOS 15+, also visit **System Settings → Privacy & Security → "Open Anyway"** if needed.
4. Grant Screen Recording permission when prompted.
5. The first-run wizard explains the rest.

**Why unsigned?** A signed/notarized DMG requires a $99/year Apple Developer account. JuiceScreen is free and open source — the trade-off is the one-time right-click prompt above. The DMG is EdDSA-signed via Sparkle for safe in-app updates after the first install.

## Developing

**Requirements:**

- macOS 14 Sonoma or newer
- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

**Setup:**

```bash
git clone https://github.com/mkupermann/JuiceScreen.git
cd JuiceScreen
xcodegen generate
open JuiceScreen.xcodeproj
```

The `.xcodeproj` is regenerated from `project.yml` and not committed. Edit `project.yml` (not the `.xcodeproj`) to add files or change build settings.

**Run tests:**

```bash
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS'
```

**Run from CLI:**

```bash
xcodebuild -scheme JuiceScreen -destination 'platform=macOS' build
open "$(xcodebuild -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
```

## Privacy

JuiceScreen makes **two** kinds of network calls and no others:

1. Sparkle fetching the appcast XML from `https://mkupermann.github.io/JuiceScreen/appcast.xml` (default: on launch + every 24h; user can fully disable in Settings)
2. Sparkle downloading a new DMG from `github.com` when the user clicks **Install Update**

That is the entire network surface. No telemetry. No analytics. No crash reporter. No third-party SDKs. Verifiable with [Little Snitch](https://obdev.at/products/littlesnitch/) or [Lulu](https://objective-see.org/products/lulu.html).

## Known limitations

(These will be expanded as the app gains features.)

- App is unsigned — first launch requires right-click → Open
- No support for macOS < 14
- No iCloud sync of library (by design — local-only)
- macOS 15+ may re-prompt for Screen Recording permission weekly (Apple's behavior, not ours)
- Scroll capture (v0.8): ~30% of complex web pages (sticky headers, lazy-load, parallax) produce ghosting or torn images. Native macOS apps and simple web pages stitch cleanly.
- Scroll capture only handles vertical scroll in v0.8.
- v1.0.0 is the first public release; the auto-update flow is functional but `mkupermann.github.io/JuiceScreen/appcast.xml` may take ~60 seconds after a release to reflect new versions (GitHub Pages cache).

Vector PDF export and additional limitations will be documented as those features ship.

## License

MIT. See `LICENSE`.

## Roadmap

All 10 plans shipped. v1.0.0 is the first public release. See `docs/CHANGELOG.md` for what landed in each milestone.
