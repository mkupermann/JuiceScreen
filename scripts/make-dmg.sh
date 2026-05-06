#!/usr/bin/env bash
# Wraps build/JuiceScreen.app in a DMG with a /Applications symlink.
# Usage: scripts/make-dmg.sh
# Output: build/JuiceScreen-<VERSION>.dmg
#
# Prerequisites: brew install create-dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "❌ create-dmg not installed. Run: brew install create-dmg"
    exit 1
fi

if [[ ! -d "build/JuiceScreen.app" ]]; then
    echo "❌ build/JuiceScreen.app missing — run scripts/build-release.sh first"
    exit 1
fi

VERSION="$(cat VERSION)"
DMG_PATH="build/JuiceScreen-${VERSION}.dmg"
rm -f "$DMG_PATH"

create-dmg \
    --volname "JuiceScreen ${VERSION}" \
    --window-pos 200 120 \
    --window-size 600 380 \
    --icon-size 96 \
    --icon "JuiceScreen.app" 175 190 \
    --hide-extension "JuiceScreen.app" \
    --app-drop-link 425 190 \
    --no-internet-enable \
    "$DMG_PATH" \
    "build/JuiceScreen.app"

# Print SHA256 for the appcast script to consume.
SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE="$(stat -f %z "$DMG_PATH")"

echo "✅ DMG: $DMG_PATH"
echo "   size=${SIZE} sha256=${SHA}"
