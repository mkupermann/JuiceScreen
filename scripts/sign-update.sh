#!/usr/bin/env bash
# Signs build/JuiceScreen-<VERSION>.dmg with the maintainer's Sparkle EdDSA private key.
#
# The private key is read from environment variable SPARKLE_ED_KEY (base64-encoded).
# Generate it once with Sparkle's `generate_keys` and store it in a password manager —
# never commit it, never put it in CI secrets.
#
# Usage: SPARKLE_ED_KEY="…" scripts/sign-update.sh build/JuiceScreen-1.0.0.dmg
# Output: prints "edSignature=<base64>" and "length=<bytes>" on stdout for update-appcast.sh to consume
set -euo pipefail

if [[ -z "${SPARKLE_ED_KEY:-}" ]]; then
    echo "❌ SPARKLE_ED_KEY env var not set — see docs/RELEASE.md for setup"
    exit 1
fi

DMG_PATH="${1:-}"
if [[ -z "$DMG_PATH" ]] || [[ ! -f "$DMG_PATH" ]]; then
    echo "❌ Usage: scripts/sign-update.sh <path-to-dmg>"
    exit 1
fi

# Locate Sparkle's sign_update binary inside the SPM-resolved package.
SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -type f -path '*/Sparkle.*' 2>/dev/null | head -1 || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
    echo "❌ sign_update binary not found in DerivedData. Run scripts/build-release.sh once to resolve packages."
    exit 1
fi

# sign_update reads the private key from stdin in base64 form.
SIGNATURE_LINE="$(echo "$SPARKLE_ED_KEY" | "$SIGN_UPDATE" --ed-key-stdin "$DMG_PATH")"
# Output looks like:  sparkle:edSignature="<sig>" length="<bytes>"
EDSIG="$(echo "$SIGNATURE_LINE" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')"
LEN="$(echo "$SIGNATURE_LINE" | sed -E 's/.*length="([^"]+)".*/\1/')"

echo "edSignature=${EDSIG}"
echo "length=${LEN}"
