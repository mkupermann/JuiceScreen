# JuiceScreen

Open-source, 100% local screen capture for macOS. Region / window / full-screen / scroll capture, video recording with audio, annotation, OCR-indexed library search.

**Status:** v0.1.0 — Foundation milestone. Menu-bar shell, permissions flow, and Settings stub work. Capture functionality lands in subsequent milestones.

## Why

CleanShot X is excellent but proprietary. JuiceScreen aims to be the lean open-source alternative:

- **Open source** (MIT licensed)
- **100% local** — zero network calls except optional Sparkle update checks. No telemetry. No analytics. No crash reporter
- **Lean feature set** — only what's actually used
- **Modern minimal UI**

See `docs/superpowers/specs/2026-05-04-juicescreen-design.md` for the full design.

## Installing

JuiceScreen is currently pre-alpha. Once v1.0.0 ships:

1. Download `JuiceScreen-X.Y.Z.dmg` from [Releases](https://github.com/mkupermann/JuiceScreen/releases)
2. Open the DMG and drag `JuiceScreen.app` to `/Applications`
3. **First launch will be blocked** because the app is not code-signed. Right-click `JuiceScreen.app` in `/Applications` → **Open** → confirm. On macOS 15+, also visit **System Settings → Privacy & Security → "Open Anyway"** if needed
4. Grant Screen Recording permission when prompted
5. The first-run wizard will explain the rest

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

Scroll capture, vector PDF export, and additional limitations will be documented as those features ship.

## License

MIT. See `LICENSE`.

## Roadmap

Implementation proceeds via 10 plans, each shipping a working artifact. Foundation (this milestone) is Plan 1 of 10. Subsequent plans add image capture (Plan 2), annotation (Plan 3), library + storage (Plan 4), OCR + search (Plan 5), video recording (Plan 6), trim (Plan 7), scroll capture (Plan 8), settings + Sparkle (Plan 9), build pipeline + ship (Plan 10).
