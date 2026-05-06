# JuiceScreen

Screen capture for macOS — region, window, full-screen, and scrolling-area capture; video recording with audio; annotation; a local library indexed by on-device OCR.

**Status:** v1.0.0 — first public release. See `docs/CHANGELOG.md` for what's in this version.

## What it does

- Capture region (`⌘⇧4`), full-screen (`⌘⇧3`), window, last region (`⌘⇧R`), or a scrolling area (`⌘⇧6`).
- Record full-screen video (`⌘⇧5`) at 30 or 60 fps. System audio plus microphone on separate tracks. Optional cursor highlight ring, click pulse, and keystroke overlay (the latter two need Input Monitoring).
- Trim recordings post-record. Two-handle scrubber; exports a new MP4 at the chosen range.
- Annotate with 11 tools and undo/redo. Save as PNG, JPG, or rasterized PDF.
- Every capture and recording is indexed in a local SQLite database. Free-text search runs over on-device OCR with filters: `aws error from:Safari after:2026-04-15 type:image`. Soft-delete with 30-day garbage collection; restore from the inspector.

## Why it exists

CleanShot X already does most of this, well, and is proprietary. JuiceScreen runs locally, has no network surface beyond Sparkle update checks, and has source you can read. There is no Apple Developer ID behind the project, so the DMG is unsigned — first launch needs a right-click → Open.

## Installing

1. Download `JuiceScreen-X.Y.Z.dmg` from [Releases](https://github.com/mkupermann/JuiceScreen/releases).
2. Open the DMG and drag `JuiceScreen.app` to `/Applications`.
3. Right-click `JuiceScreen.app` → **Open** → confirm. macOS 15 sometimes needs a follow-up via **System Settings → Privacy & Security → Open Anyway**.
4. Grant Screen Recording permission when the first capture is triggered.
5. The first-run wizard covers the rest.

Notarization needs a paid Apple Developer account; the project does not have one. Updates after the first install are verified via Sparkle's EdDSA signing.

## Privacy

Two and only two network calls:

1. Sparkle fetches the appcast XML from `https://mkupermann.github.io/JuiceScreen/appcast.xml` on launch and every 24 hours. Disable in Settings.
2. Sparkle downloads a new DMG from `github.com` when the user accepts an update.

That is the entire network surface. No telemetry, no analytics, no crash reporter, no third-party SDKs. Verifiable with [Little Snitch](https://obdev.at/products/littlesnitch/) or [Lulu](https://objective-see.org/products/lulu.html).

## Developing

Requirements: macOS 14 or newer, Xcode 16 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/mkupermann/JuiceScreen.git
cd JuiceScreen
xcodegen generate
open JuiceScreen.xcodeproj
```

The `.xcodeproj` is regenerated from `project.yml` and is not committed. Edit `project.yml`, not the generated project.

Tests:

```bash
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS'
```

Build and run from CLI:

```bash
xcodebuild -scheme JuiceScreen -destination 'platform=macOS' build
open "$(xcodebuild -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
```

## Known limitations

- The DMG is unsigned. First launch needs the right-click → Open step above.
- macOS 14 minimum.
- No iCloud sync. By design — the library stays on the local machine.
- macOS 15 may re-prompt for Screen Recording permission roughly weekly. Apple's behaviour, not configurable from inside the app.
- Scroll capture works on most native macOS apps and simple web pages. It produces ghosting or torn frames on pages with sticky headers, lazy-loaded content, or parallax — about 30% of complex web pages in testing.
- Scroll capture handles vertical scroll only in v1.0.
- PDF export is rasterized. Vector PDF is on the v1.1 list.
- The auto-update feed is served from GitHub Pages and can lag a new release by ~60 seconds.

## License

MIT — see `LICENSE`.

## Roadmap

All 10 implementation milestones complete. v1.0.0 is the first public release. Per-version detail in `docs/CHANGELOG.md`.
