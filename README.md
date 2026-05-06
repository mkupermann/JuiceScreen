# JuiceScreen

CleanShot X already does most of this, well, and is proprietary. JuiceScreen is the open-source alternative — screen capture for macOS, running locally, with source you can read.

Region, window, full-screen, and scrolling-area capture. Video recording with audio. Annotation. A local library indexed by on-device OCR.

The DMG is unsigned — there is no Apple Developer ID behind the project, so first launch needs a right-click → Open.

**Status:** v1.0.0 — first public release. See `docs/CHANGELOG.md` for what's in this version.

## What it does

- Capture region (`⌘⇧4`), full-screen (`⌘⇧3`), window, last region (`⌘⇧R`), or a scrolling area (`⌘⇧6`).
- Record full-screen video (`⌘⇧5`) at 30 or 60 fps. System audio plus microphone on separate tracks. Optional cursor highlight ring, click pulse, and keystroke overlay (the latter two require Input Monitoring — see Privacy below for what is read and where it goes).
- Trim recordings post-record. Two-handle scrubber; exports a new MP4 at the chosen range.
- Annotate with 11 tools and undo/redo. Save as PNG, JPG, or rasterized PDF.
- Every capture and recording is indexed in a local SQLite database. Free-text search runs over on-device OCR with filters: `aws error from:Safari after:2026-04-15 type:image`. Soft-delete with 30-day garbage collection; restore from the inspector.

## Known limitations

- The DMG is unsigned. First launch needs the right-click → Open step in the Installing section. On macOS 14.4 and later, this redirects you to **System Settings → Privacy & Security → Open Anyway** — that step is required, not optional.
- macOS 14 minimum.
- No iCloud sync. By design — the library stays on the local machine.
- macOS 15 may re-prompt for Screen Recording permission roughly weekly. Apple's behaviour, not configurable from inside the app.
- Scroll capture works on most native macOS apps and simple web pages. It produces ghosting or torn frames on pages with sticky headers, lazy-loaded content, or parallax — about 30% of complex web pages in testing.
- Scroll capture handles vertical scroll only in v1.0.
- PDF export is rasterized. Vector PDF is on the v1.1 list.
- The auto-update feed is served from GitHub Pages and can lag a new release by ~60 seconds.

## Installing

1. Download `JuiceScreen-X.Y.Z.dmg` from [Releases](https://github.com/mkupermann/JuiceScreen/releases).
2. Open the DMG and drag `JuiceScreen.app` to `/Applications`.
3. Right-click `JuiceScreen.app` → **Open** → confirm. On macOS 14.4 and later, macOS will redirect you to **System Settings → Privacy & Security → Open Anyway** — that confirmation is required for every unsigned app.
4. Grant Screen Recording permission when the first capture is triggered.
5. The first-run wizard covers the rest.

Notarization needs a paid Apple Developer account; the project does not have one. Updates after the first install are verified via Sparkle's EdDSA signing.

## Privacy

Two network calls:

1. Sparkle fetches the appcast XML from `https://mkupermann.github.io/JuiceScreen/appcast.xml` on launch and every 24 hours. Disable in Settings.
2. Sparkle downloads a new DMG from `github.com` when you accept an update.

No telemetry, no analytics, no crash reporter, no third-party SDKs. Verifiable with [Little Snitch](https://obdev.at/products/littlesnitch/) or [Lulu](https://objective-see.org/products/lulu.html) — filter on process name `JuiceScreen`; Sparkle traffic comes from the same process, not a helper.

What the three TCC permissions do:

- **Screen Recording** — frame data goes to local PNG / MP4 / PDF files in your save folder and to a local SQLite library at `~/Library/Application Support/JuiceScreen/`. Never transmitted.
- **Microphone** — only requested when microphone capture is enabled in Settings → Recording. PCM audio is multiplexed into the recording's MP4 container. Microphone capture only runs while a recording is active.
- **Input Monitoring** — only requested when click pulse or keystroke overlay is enabled in Settings → Recording. Pointer-click locations and the last three keys pressed are read so the recorder can draw the overlay into the video frames. Held in process memory only, discarded when the recording session ends — nothing leaves the process.

## Developing

Requirements: macOS 14 or newer, Xcode 16 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/mkupermann/JuiceScreen.git
cd JuiceScreen
xcodegen generate
open JuiceScreen.xcodeproj
```

The `.xcodeproj` is regenerated from `project.yml` and is not committed. Edit `project.yml`, not the generated project.

Tests (~257 unit tests in 62 suites; runs in ~2 seconds on M-series):

```bash
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS'
```

Build and run from CLI:

```bash
xcodebuild -scheme JuiceScreen -destination 'platform=macOS' build
open "$(xcodebuild -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
```

## License

MIT — see `LICENSE`.

## Roadmap

v1.1 targets — no committed dates:

- Vector PDF export (the v1.0 PDF is rasterized).
- Horizontal scroll capture; sticky-header masking for the cases v1.0 ghosts on.
- Optional iCloud library backup, off by default. The local-first model stays.
- Notarization once an Apple Developer account is in place.

Per-version detail in `docs/CHANGELOG.md`.
