#!/usr/bin/env bash
# Signs a DMG with the maintainer's Sparkle EdDSA private key.
#
# By default Sparkle's sign_update reads the private key from the macOS keychain
# (the entry that `generate_keys` created). No env var is required for the
# normal case — your keychain is the source of truth.
#
# To override (e.g. for a CI run on a fresh machine, which we don't actually
# do — see docs/RELEASE.md for the local-only signing rationale), set
# SPARKLE_ED_KEY to the base64-encoded private key and the script will pass
# it on stdin instead.
#
# Usage:   scripts/sign-update.sh <path-to-dmg>
# Output:  prints "edSignature=<base64>" and "length=<bytes>" on stdout for
#          update-appcast.sh to consume.
set -euo pipefail

DMG_PATH="${1:-}"
if [[ -z "$DMG_PATH" ]] || [[ ! -f "$DMG_PATH" ]]; then
    echo "❌ Usage: scripts/sign-update.sh <path-to-dmg>" >&2
    exit 1
fi

# Locate Sparkle's sign_update binary inside the SPM-resolved package artifact.
# Skip the legacy DSA copy that lives under old_dsa_scripts/.
SIGN_UPDATE="$(
    find ~/Library/Developer/Xcode/DerivedData \
        -type f -name sign_update -not -path '*old_dsa_scripts*' \
        2>/dev/null | head -1
)"
if [[ -z "$SIGN_UPDATE" ]]; then
    echo "❌ sign_update binary not found in DerivedData." >&2
    echo "   Run scripts/build-release.sh once locally so Sparkle resolves." >&2
    exit 1
fi

# Sign. Keychain mode by default; stdin override when SPARKLE_ED_KEY is set.
if [[ -n "${SPARKLE_ED_KEY:-}" ]]; then
    SIGNATURE_LINE="$(printf '%s' "$SPARKLE_ED_KEY" | "$SIGN_UPDATE" --ed-key-stdin "$DMG_PATH")"
else
    SIGNATURE_LINE="$("$SIGN_UPDATE" "$DMG_PATH")"
fi

# sign_update prints:  sparkle:edSignature="<sig>" length="<bytes>"
EDSIG="$(echo "$SIGNATURE_LINE" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
LEN="$(echo "$SIGNATURE_LINE" | sed -nE 's/.*length="([^"]+)".*/\1/p')"

if [[ -z "$EDSIG" ]] || [[ -z "$LEN" ]]; then
    echo "❌ Could not parse sign_update output:" >&2
    echo "$SIGNATURE_LINE" >&2
    exit 1
fi

echo "edSignature=${EDSIG}"
echo "length=${LEN}"
