# JuiceScreen Release Runbook

This document is for the maintainer (Michael). It covers the one-time setup, the steps to ship a new version, and what to do when a step fails.

## One-time setup (do this once, ever)

### Generate the Sparkle EdDSA keypair

JuiceScreen's auto-update requires every released DMG to be signed with an EdDSA key the app trusts. The public half is bundled in `Info.plist`; the private half lives only on your machine + a password manager backup.

1. After Plan 9 ships, the Sparkle SPM dependency is resolved at `~/Library/Developer/Xcode/DerivedData/JuiceScreen-*/SourcePackages/checkouts/Sparkle/`.
2. Find the `generate_keys` binary inside that checkout: `find ~/Library/Developer/Xcode/DerivedData -name generate_keys -type f -path '*/Sparkle/*'`.
3. Run it: `<path>/generate_keys`. It prints something like:
   ```
   ed25519 keypair generated.
   Public  key: U7uKzN...
   Private key: aBc12...
   ```
4. Copy the **public key** into `JuiceScreen/Resources/Info.plist`'s `SUPublicEDKey` value, replacing the literal placeholder `PLACEHOLDER_GENERATE_IN_PLAN_10`. (Also update the `properties:` block in `project.yml` so future `xcodegen generate` runs preserve it.) Commit + push: `feat: bind production Sparkle public key`.
5. Save the **private key** to your password manager (Bitwarden / 1Password) under entry name `JuiceScreen — Sparkle EdDSA private key`. **Never commit it. Never paste it into CI secrets. Never share it.**
6. Add the private key to your shell environment for release sessions:
   ```bash
   # in your password manager, or in a file you keep in ~/.local/secrets/ that is gitignored AND outside any repo
   export SPARKLE_ED_KEY="aBc12..."
   ```

### Set up GitHub Pages for the appcast

1. In the GitHub repo settings → Pages, choose source branch `main`, folder `/docs`. Save. (GitHub Pages only allows `/` or `/docs` as source paths; the appcast lives at `docs/appcast.xml` for that reason.)
2. Verify the URL: `https://mkupermann.github.io/JuiceScreen/appcast.xml`. The empty template should render.
3. Confirm `Info.plist` has `SUFeedURL = https://mkupermann.github.io/JuiceScreen/appcast.xml`.

## Per-release flow

For every new version (1.0.1, 1.1.0, etc.):

### 1. Sanity check

```bash
bash scripts/check-tools.sh         # all green
git status                          # clean working tree
git pull                            # up to date with main
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests   # passes
```

### 2. Bump version + changelog

1. Edit `VERSION` (e.g., `1.0.1`).
2. Edit `project.yml`'s `MARKETING_VERSION`. Run `xcodegen generate`.
3. Edit `docs/CHANGELOG.md`: add a new `## [1.0.1] — YYYY-MM-DD` section at the top with bullets for each user-visible change.
4. Run the QA checklist: `docs/QA-CHECKLIST.md`. Don't skip it.
5. Commit: `chore: bump VERSION to 1.0.1 + changelog`.

### 3. Tag and push

```bash
git tag v1.0.1
git push origin main
git push origin v1.0.1
```

The push triggers `.github/workflows/release.yml`. Wait ~10 minutes for it to build the DMG.

### 4. Sign + appcast (local)

After the workflow finishes:

```bash
# Download the draft DMG from the Releases page → "Assets"
DMG=~/Downloads/JuiceScreen-1.0.1.dmg

# Sign it with the private key (must be in env)
SIGOUT="$(scripts/sign-update.sh "$DMG")"
SIG="$(echo "$SIGOUT" | grep edSignature | cut -d= -f2)"
LEN="$(echo "$SIGOUT" | grep length      | cut -d= -f2)"

# The download URL on GitHub Releases follows this pattern:
URL="https://github.com/mkupermann/JuiceScreen/releases/download/v1.0.1/JuiceScreen-1.0.1.dmg"

scripts/update-appcast.sh "$SIG" "$LEN" "$URL"

git add docs/appcast.xml
git commit -m "chore(appcast): publish v1.0.1"
git push origin main
```

GitHub Pages picks up the new appcast within ~60 seconds.

### 5. Publish the GitHub Release

1. Open the draft release on GitHub.
2. Paste the changelog section under "Release notes".
3. Click **Publish release**.

### 6. Smoke

1. On a different Mac (or a fresh user account on yours), launch JuiceScreen 1.0.0.
2. Wait for the auto-update prompt, OR Settings → About → Check for Updates Now.
3. The 1.0.1 prompt should appear with the changelog. Install. Verify version after restart.

## Recovery

| Problem | Fix |
|---|---|
| `release.yml` failed at "Verify VERSION matches tag" | The `VERSION` file and the tag disagree. Fix one and re-tag locally; force-push is fine since the release isn't published yet. |
| `sign-update.sh` says `sign_update binary not found` | Run `scripts/build-release.sh` once locally to populate DerivedData. The Sparkle SPM checkout is what the script searches. |
| `update-appcast.sh` says "appcast already has an entry for X" | You ran it twice. Either revert with `git restore docs/appcast.xml` and re-run, or hand-edit if you intentionally want to re-publish. |
| Users on 1.0.0 never see the 1.0.1 prompt | Check `Info.plist`'s `SUFeedURL`, browse it in a browser, validate XML, and confirm GitHub Pages is serving the latest commit (it can take ~60s). |
| `Check for Updates` says "verification failed" | The `SUPublicEDKey` in `Info.plist` doesn't match the private key used to sign. Either you rotated keys (don't, unless compromised) or the wrong key was used. Re-sign with the correct one. |
| `release.yml` failed at "Guard against placeholder Sparkle public key" | `Info.plist` still contains the literal `PLACEHOLDER_GENERATE_IN_PLAN_10`. Run the one-time keypair generation in the setup section above, commit the real public key into `Info.plist` (and `project.yml` so `xcodegen` preserves it), push, then re-tag. |
| Bad release shipped — need to retract from auto-update | Edit `docs/appcast.xml`: set the bad version's `<enclosure url="...">` to an empty string, and add `<sparkle:minimumAutoupdateVersion>X.Y.Z</sparkle:minimumAutoupdateVersion>` (where `X.Y.Z` is the bad version) to the next published `<item>` to force a skip past it. Commit and push the appcast change. Sparkle will stop offering the bad version on the next update check. |
