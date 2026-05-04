# JuiceScreen

Open-source, 100% local screen capture for macOS. Region / window / full-screen / scroll capture, video recording with audio, annotation, OCR-indexed library search.

**Status:** Pre-alpha (Foundation milestone in progress). Not yet usable for capture.

## Installing

_Not yet — first usable build will ship at the end of Plan 2 (Image Capture)._

## Developing

Requires:
- macOS 14 Sonoma or newer
- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

Setup:

```bash
git clone https://github.com/mkupermann/JuiceScreen.git
cd JuiceScreen
xcodegen generate
open JuiceScreen.xcodeproj
```

Run tests:

```bash
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS'
```

## License

MIT. See `LICENSE`.

## Design

See `docs/superpowers/specs/2026-05-04-juicescreen-design.md` for the full design spec.
