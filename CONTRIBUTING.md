# Contributing to JuiceScreen

Thanks for looking. JuiceScreen is a one-person, no-paid-maintainer project, so
the aim here is to make contributions easy to review and land, not to impose
process for its own sake.

## Before you start

- **Small fixes** (bugs, a new annotation tool, an additional capture/export
  format): just open a PR.
- **Larger changes** (new windows, database schema migrations, anything that
  touches the capture pipeline): open an issue first so we can agree on the
  shape before you spend time on it.

## Development setup

Requirements: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone https://github.com/mkupermann/JuiceScreen.git
cd JuiceScreen
xcodegen generate
open JuiceScreen.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and is **not** committed. Edit
`project.yml`, never the generated project. New source files under `JuiceScreen/`
and `JuiceScreenTests/` are picked up automatically on the next `xcodegen generate`.

## Tests

The suite is fast (~2s on Apple Silicon) and CI keeps it green — a PR needs to
as well.

```bash
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests
```

Add a test with any behaviour change. The codebase leans on protocol + `Fake…`
doubles (see `FakeCaptureEngine`, `FakeLibraryStore`, etc.) so most logic is
testable without hitting the screen, disk, or network. Anything privacy-relevant
(what leaves the process, what a delete actually removes) should have a test that
pins the behaviour.

## Style

- Match the surrounding code: folder-per-feature boundaries (`Capture/`,
  `Library/`, `Annotation/`, …), value types where practical, `AppLog` for
  logging, no `print`.
- `SWIFT_STRICT_CONCURRENCY: complete` is on — keep it warning-clean.
- Keep the local-first, no-telemetry model intact. A change that adds a network
  call or a hosted destination will not be merged; that is a deliberate product
  boundary, documented in the README.

## Security

For anything exploitable, do not open a public issue — see
[SECURITY.md](SECURITY.md).

## License

By contributing you agree your work is licensed under the project's
[MIT license](LICENSE).
