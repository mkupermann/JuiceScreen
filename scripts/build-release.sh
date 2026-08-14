#!/usr/bin/env bash
# Archives JuiceScreen in Release config and exports JuiceScreen.app to build/.
# Idempotent — wipes build/ before running.
#
# Usage: scripts/build-release.sh
# Output: build/JuiceScreen.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION)"
ARCHIVE_DIR="build/archive"
EXPORT_DIR="build"
EXPORT_OPTIONS="build/exportOptions.plist"

rm -rf build
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR"

# 0. Pick a signing identity.
#
#    A Developer ID identity in the keychain is used when present, ad-hoc
#    otherwise. Two reasons this is not just cosmetic:
#
#    * TCC (Screen Recording, Microphone) remembers a grant by the signature's
#      designated requirement. Developer ID gives a stable one — team ID plus
#      bundle ID — so the grant survives every rebuild. An ad-hoc signature has
#      no stable identity, so TCC falls back to the binary's cdhash, which
#      changes on every build: macOS then treats each build as a brand-new app
#      and re-prompts, leaving a trail of stale entries in System Settings.
#    * An ad-hoc DMG is blocked by Gatekeeper on other people's Macs. Only the
#      signed variant is fit to ship.
#
#    The ad-hoc fallback exists so a fork without the maintainer's certificate
#    can still build and run the app locally.
DEVELOPER_ID="$(
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -nE 's/.*"(Developer ID Application: .*)".*/\1/p' \
        | head -1
)"
TEAM_ID="$(printf '%s' "$DEVELOPER_ID" | sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p')"

if [[ -n "$DEVELOPER_ID" ]]; then
    echo "🔏 Signing with: $DEVELOPER_ID"
else
    echo "⚠️  No Developer ID Application identity found — falling back to ad-hoc."
    echo "   The result runs locally but is NOT fit to distribute, and macOS will"
    echo "   ask for Screen Recording permission again after every rebuild."
fi

# 1. Regenerate the .xcodeproj from project.yml so the build matches source-of-truth.
xcodegen generate

# 2. Archive — Release config.
if [[ -n "$DEVELOPER_ID" ]]; then
    xcodebuild archive \
        -project JuiceScreen.xcodeproj \
        -scheme JuiceScreen \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_DIR/JuiceScreen.xcarchive" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        ENABLE_HARDENED_RUNTIME=YES \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        | xcbeautify
else
    xcodebuild archive \
        -project JuiceScreen.xcodeproj \
        -scheme JuiceScreen \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_DIR/JuiceScreen.xcarchive" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM="" \
        | xcbeautify
fi

# 3. Write export options plist.
if [[ -n "$DEVELOPER_ID" ]]; then
    cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF
else
    cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF
fi

# 4. Export the .app from the archive.
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_DIR/JuiceScreen.xcarchive" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    | xcbeautify

if [[ ! -d "$EXPORT_DIR/JuiceScreen.app" ]]; then
    echo "❌ Export failed — JuiceScreen.app not found in $EXPORT_DIR"
    exit 1
fi

# 5. Signature hygiene.
if [[ -n "$DEVELOPER_ID" ]]; then
    # The developer-id export re-signs every embedded framework, dylib and XPC
    # service with the same identity, so Sparkle.framework carries the app's
    # team ID and dyld loads it. Nothing to re-sign — only verify.
    codesign --verify --deep --strict "$EXPORT_DIR/JuiceScreen.app"
else
    # Deep ad-hoc re-sign. xcodebuild's export step preserves Sparkle.framework's
    # upstream signature, which has a different team identifier than the ad-hoc
    # signed app. macOS's dyld then refuses to load the framework into the app
    # process ("mapping process and mapped file have different Team IDs"), and
    # the app fails to launch on first install.
    #
    # `codesign --force --deep --sign -` walks the bundle bottom-up and re-signs
    # every embedded framework / dylib / xpc with the same ad-hoc identity, so
    # the team-ID match check passes uniformly.
    codesign --force --deep --sign - "$EXPORT_DIR/JuiceScreen.app"
    codesign --verify --deep --strict "$EXPORT_DIR/JuiceScreen.app"
fi

echo "✅ Built JuiceScreen $VERSION → $EXPORT_DIR/JuiceScreen.app"
if [[ -n "$DEVELOPER_ID" ]]; then
    echo "   Developer ID signed, Hardened Runtime on, secure timestamp."
    echo "   Still NOT distributable until notarised and stapled — see docs/RELEASE.md."
else
    echo "   Ad-hoc signed — local use only."
fi
