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

# 1. Regenerate the .xcodeproj from project.yml so the build matches source-of-truth.
xcodegen generate

# 2. Archive — Release config, ad-hoc signing (no Apple Developer ID).
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

# 3. Write export options plist (developer-id-style export with no team).
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

# 5. Deep ad-hoc re-sign. xcodebuild's export step preserves Sparkle.framework's
#    upstream signature, which has a different team identifier than the ad-hoc
#    signed app. macOS's dyld then refuses to load the framework into the app
#    process ("mapping process and mapped file have different Team IDs"), and
#    the app fails to launch on first install.
#
#    `codesign --force --deep --sign -` walks the bundle bottom-up and re-signs
#    every embedded framework / dylib / xpc with the same ad-hoc identity, so
#    the team-ID match check passes uniformly.
codesign --force --deep --sign - "$EXPORT_DIR/JuiceScreen.app"
codesign --verify --deep --strict "$EXPORT_DIR/JuiceScreen.app"

echo "✅ Built JuiceScreen $VERSION → $EXPORT_DIR/JuiceScreen.app"
