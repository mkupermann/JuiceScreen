#!/usr/bin/env bash
# Appends a new <item> entry to docs/appcast.xml for the current VERSION.
#
# Usage:
#   scripts/update-appcast.sh <ed-signature> <length-bytes> <download-url>
#
# Example:
#   scripts/update-appcast.sh "abc123==" 9876543 \
#     "https://github.com/mkupermann/JuiceScreen/releases/download/v1.0.0/JuiceScreen-1.0.0.dmg"
#
# Output: prepends a new <item>…</item> block as the FIRST item in the channel.
# Idempotent: if an <item> for this version already exists, the script aborts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

EDSIG="${1:-}"
LEN="${2:-}"
URL="${3:-}"
if [[ -z "$EDSIG" ]] || [[ -z "$LEN" ]] || [[ -z "$URL" ]]; then
    echo "❌ Usage: scripts/update-appcast.sh <ed-signature> <length-bytes> <download-url>"
    exit 1
fi

VERSION="$(cat VERSION)"
APPCAST="docs/appcast.xml"
DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
MIN_OS="14.0"

if grep -q "<sparkle:version>${VERSION}</sparkle:version>" "$APPCAST"; then
    echo "❌ appcast already has an entry for ${VERSION} — refusing to duplicate"
    exit 1
fi

# Pull the latest CHANGELOG.md entry as the description.
# CHANGELOG format: "## [<version>] — <date>" headers; we take everything between the first two ## headers.
DESCRIPTION="$(awk '/^## \[/{n++; if (n==2) exit; next} n==1' docs/CHANGELOG.md | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
if [[ -z "$DESCRIPTION" ]]; then
    DESCRIPTION="See <a href=\"https://github.com/mkupermann/JuiceScreen/blob/main/docs/CHANGELOG.md\">CHANGELOG.md</a>."
fi

ITEM="$(cat <<EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
            <description><![CDATA[${DESCRIPTION}]]></description>
            <enclosure
                url="${URL}"
                length="${LEN}"
                type="application/octet-stream"
                sparkle:edSignature="${EDSIG}" />
        </item>
EOF
)"

# Insert the new <item> immediately before the first existing <item>, or before
# </channel> if there are no items yet. macOS BSD awk does not accept newlines
# inside `-v var=...`, so the item is written to a tmp file and pulled in via
# getline from BEGIN.
TMP="$(mktemp)"
ITEM_FILE="$(mktemp)"
printf '%s\n' "$ITEM" > "$ITEM_FILE"
trap 'rm -f "$ITEM_FILE" "$TMP"' EXIT

if grep -q "<item>" "$APPCAST"; then
    awk -v itemfile="$ITEM_FILE" '
        BEGIN {
            while ((getline line < itemfile) > 0) item = item ? item ORS line : line
            close(itemfile)
        }
        /^[[:space:]]*<item>/ && !p { print item; p = 1 }
        { print }
    ' "$APPCAST" > "$TMP"
else
    awk -v itemfile="$ITEM_FILE" '
        BEGIN {
            while ((getline line < itemfile) > 0) item = item ? item ORS line : line
            close(itemfile)
        }
        /<\/channel>/ { print item }
        { print }
    ' "$APPCAST" > "$TMP"
fi
mv "$TMP" "$APPCAST"
trap - EXIT
rm -f "$ITEM_FILE"

echo "✅ Appended ${VERSION} to ${APPCAST}"
