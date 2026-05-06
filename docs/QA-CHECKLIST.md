# Pre-release QA checklist

Run through this before every tag push. Don't skip — the unsigned-DMG distribution model means we only get one shot to make a good first impression on each user.

## Build

- [ ] `git status` is clean
- [ ] `bash scripts/check-tools.sh` is all green
- [ ] `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests` is all green
- [ ] `bash scripts/build-release.sh` produces `build/JuiceScreen.app`
- [ ] `bash scripts/make-dmg.sh` produces `build/JuiceScreen-<VERSION>.dmg`, mounts cleanly, the icon + /Applications symlink look correct

## Smoke (manual, on a clean macOS user account)

- [ ] First launch: right-click → Open → confirm. App opens with the menu bar icon visible.
- [ ] First-run wizard appears, explains Screen Recording permission, opens System Settings on click.
- [ ] After granting Screen Recording: ⌘⇧4 → drag → editor opens with the captured image.
- [ ] Annotate: arrow, text, blur. Save (⌘S) — file written to ~/Pictures/JuiceScreen/<date>/.
- [ ] Save As (⌘⇧S) — PNG / JPG / PDF appear in the format dropdown.
- [ ] ⌘⇧5 → record 5 seconds → ⏹ → file appears in library.
- [ ] Library window (⌘⇧L) → search "test" → no error. Switch to Trash filter → empty (or shows recent deletes).
- [ ] Settings → toggle every checkbox. Close and reopen Settings. Toggles persisted.
- [ ] Settings → About → Check for Updates Now. Sparkle dialog appears; either reports "up-to-date" (if appcast was already updated) or "no updates available" / network error if the appcast hasn't been published yet (acceptable for the first release).
- [ ] Settings → Storage → Empty trash now → confirmation dialog → empties.
- [ ] Quit via menu bar.

## Auto-update (only after the appcast is published)

- [ ] Install previous version DMG, launch.
- [ ] Wait for auto-check (or Force-check). Update prompt appears with correct version + changelog.
- [ ] Install. App restarts at new version.

## Post-release

- [ ] Tagged commit is on `main`.
- [ ] GitHub Release published (not draft).
- [ ] `appcast.xml` on GitHub Pages serves the new entry (curl https://mkupermann.github.io/JuiceScreen/appcast.xml | grep <new-version>).
- [ ] CHANGELOG entry is on `main`.
