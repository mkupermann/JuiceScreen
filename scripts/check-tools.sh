#!/usr/bin/env bash
# Preflight check for tools needed to run a JuiceScreen release locally.
# Usage: scripts/check-tools.sh
set -euo pipefail

missing=0
check() {
    if command -v "$1" >/dev/null 2>&1; then
        printf "  ✅ %-20s %s\n" "$1" "$(command -v "$1")"
    else
        printf "  ❌ %-20s MISSING — %s\n" "$1" "$2"
        missing=$((missing + 1))
    fi
}

echo "JuiceScreen release tooling check:"
check xcodebuild   "Install Xcode from the App Store."
check xcodegen     "brew install xcodegen"
check xcbeautify   "brew install xcbeautify"
check create-dmg   "brew install create-dmg"
check gh           "brew install gh"
check shasum       "Standard macOS tool — no install needed."
check xmllint      "Comes with the Xcode Command Line Tools."

if [[ "${missing}" -gt 0 ]]; then
    echo ""
    echo "${missing} tool(s) missing. Install them and re-run this script."
    exit 1
fi

echo ""
echo "All release tools present. Ready to ship."
