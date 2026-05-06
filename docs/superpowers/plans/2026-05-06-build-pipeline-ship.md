# Build Pipeline + Ship v1.0.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver everything needed to ship v1.0.0 — schema cleanup left over from Plan 9, local build/sign/appcast scripts, GitHub Actions release workflow that uploads draft DMGs, maintainer release runbook, and the v1.0.0 tag itself.

**Architecture:** Three concerns:
1. **Schema cleanup** — the lazily-created `captures_ocr_cache` table moves into a versioned `v2` migration in `LibrarySchema`. The `emptyTrash()` FTS5 delete is rewritten to use the actual FTS column names (`uuid, ocr_text, source_app`) so trashed-row cleanup also clears FTS5 entries.
2. **Build & release scripts** — local-only bash. `build-release.sh` archives + exports the app. `make-dmg.sh` wraps it via `create-dmg`. `sign-update.sh` calls Sparkle's `sign_update` against a private key the maintainer provides via `SPARKLE_ED_KEY` env var (never committed). `update-appcast.sh` appends a new `<item>` to `appcast/appcast.xml`. EdDSA private key never touches CI by design — the maintainer runs sign+appcast locally.
3. **CI release flow** — `release.yml` runs on tag push, builds the DMG on `macos-15`, uploads it as a draft GitHub Release. The maintainer downloads the draft DMG, runs the local sign/appcast scripts, commits + pushes `appcast.xml`, and clicks Publish in the GitHub UI. Initial `appcast.xml` template ships with the v1.0.0 entry already filled in (everything except the EdDSA signature, which the maintainer runbook explains how to fill).

**Tech Stack:** GRDB.swift (existing, for the v2 migration), bash, `xcodebuild`, `xcodebuild -exportArchive`, Homebrew `create-dmg`, Sparkle's `sign_update` and `generate_keys` binaries (shipped inside the SPM-resolved Sparkle package), GitHub Actions `actions/checkout`, `softprops/action-gh-release`, GitHub Pages (for serving `appcast.xml` from the `docs/` or `gh-pages` branch — runbook covers the choice).

---

## File structure

**New files:**

- `JuiceScreenTests/LibrarySchemaV2Tests.swift` — verifies the v2 migration creates `captures_ocr_cache` correctly
- `scripts/build-release.sh`
- `scripts/make-dmg.sh`
- `scripts/sign-update.sh`
- `scripts/update-appcast.sh`
- `scripts/check-tools.sh` — preflight script that verifies xcodebuild, xcodegen, create-dmg, gh, jq, etc. are installed
- `appcast/appcast.xml` — initial template with v1.0.0 entry
- `.github/workflows/release.yml`
- `docs/RELEASE.md` — maintainer release runbook
- `docs/CHANGELOG.md` — changelog (Keep-a-Changelog format)
- `docs/QA-CHECKLIST.md` — manual QA checklist run before publishing each release

**Modified files:**

- `JuiceScreen/Library/Storage/LibrarySchema.swift` — add `v2` migration for `captures_ocr_cache`
- `JuiceScreen/Library/Storage/LibraryStoreLive.swift` — remove lazy `CREATE TABLE IF NOT EXISTS captures_ocr_cache`; fix `emptyTrash()` FTS5 delete column names
- `JuiceScreenTests/LibraryStoreLiveTests.swift` — add a test that emptyTrash also clears the FTS5 + cache for a row that had OCR text indexed
- `README.md` — refresh "Installing" section per the spec's verbatim copy
- `VERSION` — bump to `1.0.0`
- `project.yml` — bump `MARKETING_VERSION` to `"1.0.0"`
- `docs/superpowers/specs/2026-05-04-juicescreen-design.md` — mark Plan 10 complete

---

### Task 1: LibrarySchema v2 — captures_ocr_cache migration

**Files:**
- Modify: `JuiceScreen/Library/Storage/LibrarySchema.swift`
- Create: `JuiceScreenTests/LibrarySchemaV2Tests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/LibrarySchemaV2Tests.swift`:

```swift
import Foundation
import GRDB
import Testing
@testable import JuiceScreen

@Suite("LibrarySchema v2")
struct LibrarySchemaV2Tests {

    private func makeMemoryQueue() throws -> DatabaseQueue {
        try DatabaseQueue()
    }

    @Test("v2 migration creates captures_ocr_cache table with uuid PK + ocr_text column")
    func v2CreatesCacheTable() throws {
        let q = try makeMemoryQueue()
        try LibrarySchema.migrator().migrate(q)

        try q.read { db in
            // Table exists
            let exists = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type='table' AND name='captures_ocr_cache'
            """) ?? 0
            #expect(exists == 1)

            // Schema columns: uuid TEXT PRIMARY KEY, ocr_text TEXT NOT NULL
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(captures_ocr_cache)")
            #expect(cols.count == 2)
            let names: [String] = cols.compactMap { $0["name"] }
            #expect(names.sorted() == ["ocr_text", "uuid"])
        }
    }

    @Test("Migrator is idempotent — running twice does not error")
    func idempotent() throws {
        let q = try makeMemoryQueue()
        try LibrarySchema.migrator().migrate(q)
        try LibrarySchema.migrator().migrate(q)
        // No throw = pass.
    }

    @Test("Both migrations are applied in order")
    func bothMigrationsApplied() throws {
        let q = try makeMemoryQueue()
        try LibrarySchema.migrator().migrate(q)
        try q.read { db in
            let captures = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='captures'
            """) ?? 0
            let cache = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='captures_ocr_cache'
            """) ?? 0
            #expect(captures == 1)
            #expect(cache == 1)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation && xcodegen generate && xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | grep -E "v2 migration|fail" | head -10`

Expected: `v2 migration creates captures_ocr_cache table…` FAILS — `captures_ocr_cache` does not exist (it is currently lazily created at runtime, not by a migration).

- [ ] **Step 3: Add the v2 migration**

In `JuiceScreen/Library/Storage/LibrarySchema.swift`, replace the file with:

```swift
import Foundation
import GRDB

/// Versioned schema migrations for the JuiceScreen library database.
///
/// v1: Creates the `captures` table, the `captures_fts` FTS5 virtual table, and
///     two indexes for common query paths.
/// v2: Adds the `captures_ocr_cache` side table that mirrors FTS5 content (the
///     FTS5 table uses content='' so it cannot reproduce its own rows; the cache
///     enables `delete` operations to clear FTS5 tokens correctly).
public enum LibrarySchema {

    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE captures (
                    uuid TEXT PRIMARY KEY,
                    file_path TEXT NOT NULL,
                    annotation_path TEXT,
                    thumbnail_path TEXT NOT NULL,
                    media_type TEXT NOT NULL,
                    captured_at INTEGER NOT NULL,
                    width INTEGER NOT NULL,
                    height INTEGER NOT NULL,
                    duration_ms INTEGER,
                    file_size_bytes INTEGER NOT NULL,
                    source_app TEXT,
                    deleted_at INTEGER
                )
            """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE captures_fts USING fts5(
                    uuid UNINDEXED,
                    ocr_text,
                    source_app,
                    content='',
                    tokenize='porter unicode61'
                )
            """)

            try db.execute(sql: """
                CREATE INDEX idx_captures_captured_at
                    ON captures(captured_at DESC)
            """)

            try db.execute(sql: """
                CREATE INDEX idx_captures_deleted_at
                    ON captures(deleted_at) WHERE deleted_at IS NULL
            """)
        }

        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                CREATE TABLE captures_ocr_cache (
                    uuid TEXT PRIMARY KEY,
                    ocr_text TEXT NOT NULL
                )
            """)
        }

        return migrator
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST FAILED" | tail`

Expected: 256 tests / 62 suites passing (was 253 / 61 + 3 new tests + 1 new suite).

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Storage/LibrarySchema.swift JuiceScreenTests/LibrarySchemaV2Tests.swift
git commit -m "feat(schema): v2 migration creates captures_ocr_cache (was lazy)"
```

---

### Task 2: Remove lazy CREATE TABLE in upsertOCRText

**Files:**
- Modify: `JuiceScreen/Library/Storage/LibraryStoreLive.swift`

The `captures_ocr_cache` table is now managed by the v2 migration (Task 1). Remove the runtime `CREATE TABLE IF NOT EXISTS` that used to create it lazily.

- [ ] **Step 1: Edit LibraryStoreLive.upsertOCRText**

In `JuiceScreen/Library/Storage/LibraryStoreLive.swift`, locate the `upsertOCRText` method. Delete the entire `try db.execute(sql: """ CREATE TABLE IF NOT EXISTS captures_ocr_cache ... """)` block (lines around 121-128 — the comment block + the CREATE statement). Leave the rest of the method unchanged.

The full updated method should look like (use this as the reference for what stays):

```swift
    public func upsertOCRText(id: UUID, text: String) async throws {
        try await databaseQueue.write { db in
            // Fetch the captures row's internal rowid so FTS rowid matches, enabling the JOIN.
            guard let capturesRowid = try Int64.fetchOne(db,
                sql: "SELECT rowid FROM captures WHERE uuid = ?",
                arguments: [id.uuidString]) else { return }

            // If an old entry exists, remove its tokens from the FTS index first.
            if let oldText = try String.fetchOne(db,
                sql: "SELECT ocr_text FROM captures_ocr_cache WHERE uuid = ?",
                arguments: [id.uuidString]) {
                try db.execute(sql: """
                    INSERT INTO captures_fts(captures_fts, rowid, uuid, ocr_text, source_app)
                    VALUES ('delete', ?, ?, ?, ?)
                """, arguments: [capturesRowid, id.uuidString, oldText, ""])
            }

            // Insert new FTS entry with the captures rowid so JOIN works.
            try db.execute(sql: """
                INSERT INTO captures_fts (rowid, uuid, ocr_text, source_app) VALUES (?, ?, ?, ?)
            """, arguments: [capturesRowid, id.uuidString, text, ""])

            // Update the cache with the new text.
            try db.execute(sql: """
                INSERT INTO captures_ocr_cache (uuid, ocr_text) VALUES (?, ?)
                ON CONFLICT(uuid) DO UPDATE SET ocr_text = excluded.ocr_text
            """, arguments: [id.uuidString, text])
        }
    }
```

- [ ] **Step 2: Run full test target**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST FAILED" | tail`

Expected: 256/62 still passing. The OCR pipeline tests, FTS5 search tests, and library migration tests must all pass — the v2 migration now creates the table the app needs at startup.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStoreLive.swift
git commit -m "refactor(storage): drop lazy CREATE TABLE — v2 migration now owns captures_ocr_cache"
```

---

### Task 3: Fix emptyTrash FTS5 delete column names + test

**Files:**
- Modify: `JuiceScreen/Library/Storage/LibraryStoreLive.swift`
- Modify: `JuiceScreenTests/LibraryStoreLiveTests.swift`

The `emptyTrash()` FTS5 delete in Plan 9 used `text` as the column — but the FTS5 virtual table's columns are `uuid, ocr_text, source_app`. The `try?` swallowed the error so trashed-row FTS5 entries were leaking. Fix it to match the same `'delete'` syntax used by `upsertOCRText`.

- [ ] **Step 1: Write the failing test**

Append to `JuiceScreenTests/LibraryStoreLiveTests.swift`:

```swift
    @Test("emptyTrash also clears FTS5 entry + ocr_cache row for trashed captures")
    func emptyTrashClearsOCR() async throws {
        let (store, _) = try makeLiveStore()
        let trashed = makeRow(deleted: true)
        try await store.insert(trashed)
        try await store.upsertOCRText(id: trashed.uuid, text: "needle haystack words")

        // Sanity: search finds it before emptyTrash (search includes trashed by default? not for free text — see SearchQuery)
        // We verify cleanup by checking captures_ocr_cache directly after emptyTrash.

        let removed = try await store.emptyTrash()
        #expect(removed == 1)

        // Confirm the captures row is gone
        let allRows = try await store.list(filter: .all)
        #expect(allRows.contains(where: { $0.uuid == trashed.uuid }) == false)

        // Confirm captures_ocr_cache has no row for that uuid
        let cacheCount: Int = try await store.databaseQueueForTesting.read { db in
            try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM captures_ocr_cache WHERE uuid = ?",
                arguments: [trashed.uuid.uuidString]) ?? 0
        }
        #expect(cacheCount == 0)
    }
```

This test references `databaseQueueForTesting` — a debug accessor. Add it to `LibraryStoreLive`:

```swift
#if DEBUG
    public var databaseQueueForTesting: DatabaseQueue { databaseQueue }
#endif
```

(Place it near the bottom of the class definition.)

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | grep -E "emptyTrashClears|Test run with|TEST FAILED" | tail`

Expected: build succeeds, the new test FAILS — captures_ocr_cache row still exists because the FTS5 delete swallowed the column-name error and never reached the cache delete (or the cache delete worked but the test will catch the silent FTS5 column bug regardless because we changed the delete logic).

Wait — the existing emptyTrash code does `try?` for both the FTS5 delete and the cache delete. The cache delete probably DID work because it uses a real column name. Re-read the existing code in `JuiceScreen/Library/Storage/LibraryStoreLive.swift` lines 87-91. If the cache delete is on a separate `try?` line and uses correct SQL, this test may already pass. If so, treat this task as a refactor: fix the FTS5 column names so we stop silently leaking FTS5 rows, even though no test asserts that today. Add a defensive assertion via `try` (no `?`) on the cache delete since the table now reliably exists.

- [ ] **Step 3: Fix emptyTrash**

In `JuiceScreen/Library/Storage/LibraryStoreLive.swift`, replace the `emptyTrash()` body:

```swift
    public func emptyTrash() async throws -> Int {
        try await databaseQueue.write { db in
            // Fetch UUIDs and rowids first so we can clean FTS5 + cache for each.
            struct Pair: FetchableRecord, Decodable {
                let uuid: String
                let rowid: Int64
            }
            let rows = try Pair.fetchAll(db, sql: """
                SELECT uuid, rowid FROM captures WHERE deleted_at IS NOT NULL
            """)

            for row in rows {
                // Look up the cached OCR text so the FTS5 'delete' command can
                // de-tokenize correctly (FTS5 content='' tables require old values).
                if let oldText = try String.fetchOne(db,
                    sql: "SELECT ocr_text FROM captures_ocr_cache WHERE uuid = ?",
                    arguments: [row.uuid]) {
                    try db.execute(sql: """
                        INSERT INTO captures_fts(captures_fts, rowid, uuid, ocr_text, source_app)
                        VALUES ('delete', ?, ?, ?, ?)
                    """, arguments: [row.rowid, row.uuid, oldText, ""])
                }
                try db.execute(sql: "DELETE FROM captures_ocr_cache WHERE uuid = ?", arguments: [row.uuid])
                try db.execute(sql: "DELETE FROM captures WHERE uuid = ?", arguments: [row.uuid])
            }

            return rows.count
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST FAILED" | tail`

Expected: 257/62 passing (256 + 1 new test).

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Library/Storage/LibraryStoreLive.swift JuiceScreenTests/LibraryStoreLiveTests.swift
git commit -m "fix(storage): emptyTrash uses real FTS5 columns + clears cache deterministically"
```

---

### Task 4: scripts/build-release.sh

**Files:**
- Create: `scripts/build-release.sh`

This script archives the app in Release config and exports a copy to `build/JuiceScreen.app`. Idempotent. Used by both the release workflow and the maintainer.

- [ ] **Step 1: Create the script**

`scripts/build-release.sh`:

```bash
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

echo "✅ Built JuiceScreen $VERSION → $EXPORT_DIR/JuiceScreen.app"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/build-release.sh
```

- [ ] **Step 3: Smoke-test the script**

Run: `cd /Users/mkupermann/Documents/GitHub/JuiceScreen-foundation && bash scripts/build-release.sh 2>&1 | tail -10`

Expected: completes with `✅ Built JuiceScreen 0.9.0 → build/JuiceScreen.app` (the file is gitignored — see Step 4). The script may take ~2 minutes since it does a full Release archive.

If `xcbeautify` is not installed, the script will fail. Install it: `brew install xcbeautify` and re-run.

- [ ] **Step 4: Add build/ to .gitignore**

In the repo root `.gitignore`, ensure these lines exist (add any that are missing):

```
build/
*.xcarchive
exportOptions.plist
```

- [ ] **Step 5: Commit**

```bash
git add scripts/build-release.sh .gitignore
git commit -m "build: add scripts/build-release.sh — xcodebuild archive + export"
```

---

### Task 5: scripts/make-dmg.sh

**Files:**
- Create: `scripts/make-dmg.sh`

Wraps `build/JuiceScreen.app` in a DMG with a /Applications drop target. Uses Homebrew's `create-dmg` — a small wrapper around `hdiutil` that handles the cosmetic stuff (background image, icon position).

- [ ] **Step 1: Create the script**

`scripts/make-dmg.sh`:

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/make-dmg.sh
```

- [ ] **Step 3: Smoke-test (optional, requires create-dmg installed)**

If `brew install create-dmg` is available locally:

```bash
bash scripts/make-dmg.sh
```

Expected: `✅ DMG: build/JuiceScreen-0.9.0.dmg` plus size + sha256. Mount the DMG by double-clicking it; verify the icon position + /Applications symlink look right.

If `create-dmg` is not installed, skip the smoke test for now — the release workflow installs it on the runner.

- [ ] **Step 4: Commit**

```bash
git add scripts/make-dmg.sh
git commit -m "build: add scripts/make-dmg.sh — wraps app in DMG via create-dmg"
```

---

### Task 6: scripts/sign-update.sh

**Files:**
- Create: `scripts/sign-update.sh`

Calls Sparkle's `sign_update` binary against `SPARKLE_ED_KEY` (env var holding the maintainer's private key in base64) to produce the `<sparkle:edSignature>` value the appcast needs.

The Sparkle SPM package vends the `sign_update` binary inside the resolved package — the script locates it in DerivedData.

- [ ] **Step 1: Create the script**

`scripts/sign-update.sh`:

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/sign-update.sh
```

- [ ] **Step 3: Verify the script syntax**

Run: `bash -n scripts/sign-update.sh; echo "exit: $?"`

Expected: `exit: 0` (no syntax errors). A live signing test requires the maintainer's private key — that's covered in `docs/RELEASE.md`.

- [ ] **Step 4: Commit**

```bash
git add scripts/sign-update.sh
git commit -m "build: add scripts/sign-update.sh — signs DMG with EdDSA private key (local only)"
```

---

### Task 7: scripts/update-appcast.sh

**Files:**
- Create: `scripts/update-appcast.sh`

Appends a new `<item>` to `appcast/appcast.xml` with version, release date, file size, EdDSA signature, and minimum-system-version. Reads the latest changelog entry from `docs/CHANGELOG.md` to populate `<description>`.

- [ ] **Step 1: Create the script**

`scripts/update-appcast.sh`:

```bash
#!/usr/bin/env bash
# Appends a new <item> entry to appcast/appcast.xml for the current VERSION.
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
APPCAST="appcast/appcast.xml"
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

# Insert the new <item> immediately after the opening <channel> + its <title>/<link>/<description>/<language> elements.
# Strategy: split appcast.xml at the first existing <item>, or at </channel> if no items yet.
TMP="$(mktemp)"
if grep -q "<item>" "$APPCAST"; then
    awk -v item="$ITEM" '/^[[:space:]]*<item>/ && !p { print item; p=1 } { print }' "$APPCAST" > "$TMP"
else
    awk -v item="$ITEM" '/<\/channel>/ { print item } { print }' "$APPCAST" > "$TMP"
fi
mv "$TMP" "$APPCAST"

echo "✅ Appended ${VERSION} to ${APPCAST}"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/update-appcast.sh
```

- [ ] **Step 3: Syntax check**

Run: `bash -n scripts/update-appcast.sh; echo "exit: $?"`

Expected: `exit: 0`.

- [ ] **Step 4: Commit**

```bash
git add scripts/update-appcast.sh
git commit -m "build: add scripts/update-appcast.sh — appends new entry to appcast.xml"
```

---

### Task 8: appcast/appcast.xml initial template

**Files:**
- Create: `appcast/appcast.xml`

A valid Sparkle appcast that starts EMPTY (no `<item>` blocks). The maintainer runs `update-appcast.sh` after each release to add the v1.0.0 entry. This file is committed and served at `https://mkupermann.github.io/JuiceScreen/appcast.xml` via GitHub Pages.

- [ ] **Step 1: Create the file**

`appcast/appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>JuiceScreen</title>
        <link>https://github.com/mkupermann/JuiceScreen</link>
        <description>Open-source, 100% local screen capture for macOS.</description>
        <language>en</language>
    </channel>
</rss>
```

- [ ] **Step 2: Validate it parses**

Run: `xmllint --noout appcast/appcast.xml; echo "exit: $?"`

Expected: `exit: 0` (valid XML). If `xmllint` is not installed, that's fine — it ships with macOS Command Line Tools. Skip if needed.

- [ ] **Step 3: Commit**

```bash
git add appcast/appcast.xml
git commit -m "build: add appcast.xml initial template (no items yet)"
```

---

### Task 9: scripts/check-tools.sh — preflight

**Files:**
- Create: `scripts/check-tools.sh`

Verifies the maintainer has all the binaries needed to run a release. Saves frustration before a long archive build.

- [ ] **Step 1: Create the script**

`scripts/check-tools.sh`:

```bash
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
```

- [ ] **Step 2: Make executable + smoke-test**

```bash
chmod +x scripts/check-tools.sh
bash scripts/check-tools.sh
```

Expected: a list of tools; the script exits 0 if all are present, 1 otherwise. If anything is missing on the local machine, install it before continuing.

- [ ] **Step 3: Commit**

```bash
git add scripts/check-tools.sh
git commit -m "build: add scripts/check-tools.sh — preflight check for release tooling"
```

---

### Task 10: .github/workflows/release.yml

**Files:**
- Create: `.github/workflows/release.yml`

Runs on every git tag push of the form `v*.*.*`. Builds the DMG, uploads it as a draft GitHub Release. EdDSA signing + appcast publishing is intentionally NOT in this workflow — the maintainer does those locally.

- [ ] **Step 1: Create the file**

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  build-dmg:
    runs-on: macos-15
    timeout-minutes: 30

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Install tooling
        run: brew install xcodegen create-dmg xcbeautify

      - name: Verify VERSION matches tag
        run: |
          TAG_VERSION="${GITHUB_REF#refs/tags/v}"
          FILE_VERSION="$(cat VERSION)"
          if [[ "$TAG_VERSION" != "$FILE_VERSION" ]]; then
            echo "❌ Tag $TAG_VERSION does not match VERSION file ($FILE_VERSION)"
            exit 1
          fi
          echo "✅ Version match: $FILE_VERSION"

      - name: Build app
        run: bash scripts/build-release.sh

      - name: Make DMG
        run: bash scripts/make-dmg.sh

      - name: Compute DMG metadata
        id: dmg
        run: |
          VERSION="$(cat VERSION)"
          DMG="build/JuiceScreen-${VERSION}.dmg"
          SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
          SIZE="$(stat -f %z "$DMG")"
          echo "version=$VERSION"     >> "$GITHUB_OUTPUT"
          echo "dmg=$DMG"              >> "$GITHUB_OUTPUT"
          echo "sha256=$SHA"           >> "$GITHUB_OUTPUT"
          echo "size=$SIZE"            >> "$GITHUB_OUTPUT"

      - name: Create draft release + upload DMG
        uses: softprops/action-gh-release@v2
        with:
          draft: true
          name: "JuiceScreen ${{ steps.dmg.outputs.version }}"
          tag_name: ${{ github.ref_name }}
          files: ${{ steps.dmg.outputs.dmg }}
          body: |
            ## JuiceScreen ${{ steps.dmg.outputs.version }}

            This is a draft release. Maintainer must:
            1. Download the DMG attached below.
            2. Locally run `SPARKLE_ED_KEY=... scripts/sign-update.sh <dmg>` to get the EdDSA signature.
            3. Locally run `scripts/update-appcast.sh <signature> <length> <download-url>` and commit the appcast change.
            4. Edit this draft release: paste the changelog, click **Publish**.

            **DMG sha256:** `${{ steps.dmg.outputs.sha256 }}`
            **DMG size:**   `${{ steps.dmg.outputs.size }}` bytes
```

- [ ] **Step 2: Validate workflow YAML syntax**

If `actionlint` is installed: `actionlint .github/workflows/release.yml`. Otherwise, paste the file into [https://rhysd.github.io/actionlint](https://rhysd.github.io/actionlint) and check for errors. Or just rely on GitHub's own validation (the workflow won't run until the tag is pushed; syntax errors will surface as a failed workflow run).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow — tag-triggered DMG build + draft release"
```

---

### Task 11: docs/RELEASE.md — maintainer release runbook

**Files:**
- Create: `docs/RELEASE.md`

The single source of truth for shipping a new version. Step-by-step. Covers the one-time key generation, the per-release flow, and recovery from common errors.

- [ ] **Step 1: Create the file**

`docs/RELEASE.md`:

```markdown
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

1. In the GitHub repo settings → Pages, choose source branch `main`, folder `/appcast`. Save.
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

git add appcast/appcast.xml
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
| `update-appcast.sh` says "appcast already has an entry for X" | You ran it twice. Either revert with `git restore appcast/appcast.xml` and re-run, or hand-edit if you intentionally want to re-publish. |
| Users on 1.0.0 never see the 1.0.1 prompt | Check `Info.plist`'s `SUFeedURL`, browse it in a browser, validate XML, and confirm GitHub Pages is serving the latest commit (it can take ~60s). |
| `Check for Updates` says "verification failed" | The `SUPublicEDKey` in `Info.plist` doesn't match the private key used to sign. Either you rotated keys (don't, unless compromised) or the wrong key was used. Re-sign with the correct one. |
```

- [ ] **Step 2: Commit**

```bash
git add docs/RELEASE.md
git commit -m "docs: add release runbook"
```

---

### Task 12: docs/CHANGELOG.md + docs/QA-CHECKLIST.md

**Files:**
- Create: `docs/CHANGELOG.md`
- Create: `docs/QA-CHECKLIST.md`

- [ ] **Step 1: Create CHANGELOG**

`docs/CHANGELOG.md`:

```markdown
# Changelog

All notable changes to JuiceScreen are documented here. This project follows [Semantic Versioning](https://semver.org/) and the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [1.0.0] — 2026-05-06

First public release.

### Capture
- Region capture (⌘⇧4), full-screen capture (⌘⇧3), last-region (⌘⇧R)
- Window capture via the macOS picker
- Scroll capture (⌘⇧6) — works cleanly on most native apps + simple web pages; ~30% of complex pages with sticky/lazy-load content produce visible artifacts. Documented honestly.

### Recording
- Full-screen video recording (⌘⇧5) at 30 or 60 fps
- System audio + microphone (separate tracks)
- Cursor highlight ring; optional click-pulse + last-3-keystrokes overlays (Input Monitoring required)
- Post-record trim editor for video files

### Annotation
- 11 tools: select/move, arrow, line, rectangle, ellipse, text, highlight, blur, freehand, redact, crop
- Layer model with undo/redo
- Save as PNG, JPG (with quality slider), or rasterized PDF
- Copy to clipboard, Save, Save As

### Library
- All captures and recordings indexed in a local SQLite database
- Local OCR via Apple's Vision framework (English + German), free-text + filter search (`from:Safari error after:2026-04-15 type:image`)
- Smart filters (All, Images, Videos, Trash); soft-delete with 30-day GC; Restore from inspector

### Settings
- Real Settings panel: General (start at login, save folder, default format, JPG quality), Capture (image scale, include cursor), Recording (every toggle persists), Hotkeys (read-only display), Storage (usage stats, Empty trash now), About (Sparkle Check for Updates)

### Privacy
- Zero telemetry, zero analytics, zero crash reporter, zero third-party SDKs except Sparkle (update checks only)
- Two and only two network calls: appcast XML fetch + DMG download. Verifiable with Little Snitch / Lulu.

### Distribution
- Unsigned DMG (no Apple Developer ID) — first launch requires right-click → Open
- Sparkle 2.x EdDSA-signed updates from GitHub Releases
- macOS 14 Sonoma minimum
```

- [ ] **Step 2: Create QA-CHECKLIST**

`docs/QA-CHECKLIST.md`:

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add docs/CHANGELOG.md docs/QA-CHECKLIST.md
git commit -m "docs: add CHANGELOG.md (initial v1.0.0) + QA-CHECKLIST.md"
```

---

### Task 13: README installation section refresh

**Files:**
- Modify: `README.md`

The current README's "Installing" section says "currently pre-alpha" and lists steps that point at unreleased URLs. Replace with the spec's verbatim wording (with corrected URLs).

- [ ] **Step 1: Edit README**

In `README.md`, replace the entire `## Installing` section (line ~26 through line ~34) with:

```markdown
## Installing

1. Download `JuiceScreen-X.Y.Z.dmg` from [Releases](https://github.com/mkupermann/JuiceScreen/releases).
2. Open the DMG, drag `JuiceScreen.app` to `/Applications`.
3. **First launch will be blocked** because the app is not code-signed. Right-click `JuiceScreen.app` in `/Applications` → **Open** → confirm. On macOS 15+, also visit **System Settings → Privacy & Security → "Open Anyway"** if needed.
4. Grant Screen Recording permission when prompted.
5. The first-run wizard explains the rest.

**Why unsigned?** A signed/notarized DMG requires a $99/year Apple Developer account. JuiceScreen is free and open source — the trade-off is the one-time right-click prompt above. The DMG is EdDSA-signed via Sparkle for safe in-app updates after the first install.
```

Also update the Roadmap section to mark Plan 10 done:

Replace:
```markdown
Implementation proceeds via 10 plans, each shipping a working artifact. Foundation (this milestone) is Plan 1 of 10. Subsequent plans add image capture (Plan 2), annotation (Plan 3), library + storage (Plan 4), OCR + search (Plan 5), video recording (Plan 6), trim (Plan 7), scroll capture (Plan 8), settings + Sparkle + PDF (Plan 9, ✅ v0.9.0), build pipeline + ship (Plan 10).
```

with:

```markdown
All 10 plans shipped. v1.0.0 is the first public release. See `docs/CHANGELOG.md` for what landed in each milestone.
```

Also remove the v0.9 bullet from Known limitations that says "v0.9 ships with a placeholder Sparkle public key" — replace it with:

```markdown
- v1.0.0 is the first public release; the auto-update flow is functional but `mkupermann.github.io/JuiceScreen/appcast.xml` may take ~60 seconds after a release to reflect new versions (GitHub Pages cache).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): refresh Installing section + post-Plan-10 roadmap"
```

---

### Task 14: Bump VERSION 1.0.0 + tag + spec status

**Files:**
- Modify: `VERSION`
- Modify: `project.yml`
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Bump VERSION**

`VERSION`:

```
1.0.0
```

- [ ] **Step 2: Bump MARKETING_VERSION**

In `project.yml`, change `MARKETING_VERSION: "0.9.0"` to `MARKETING_VERSION: "1.0.0"`. Run `xcodegen generate`.

- [ ] **Step 3: Run final test suite**

Run: `xcodebuild test -scheme JuiceScreen -destination 'platform=macOS' -only-testing:JuiceScreenTests 2>&1 | grep -E "Test run with|TEST FAILED" | tail`

Expected: 257 tests / 62 suites passing (was 253/61 at end of Plan 9 + 3 schema tests + 1 emptyTrash-clears-OCR test).

- [ ] **Step 4: Build app**

Run: `xcodebuild build -scheme JuiceScreen -destination 'platform=macOS' 2>&1 | tail -3`

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Update spec doc**

In `docs/superpowers/specs/2026-05-04-juicescreen-design.md`, find the line `- ⬜ Plan 10: ...` (or "Plan 10: Build pipeline + ship") in the implementation status section, and replace it with:

```markdown
- ✅ **Plan 10: Build pipeline + ship v1.0.0** (v1.0.0, 2026-05-06) — Schema cleanup: captures_ocr_cache moved into a v2 LibrarySchema migration (was lazily created); emptyTrash() rewritten to use real FTS5 column names + the cache table directly. Release infrastructure: scripts/check-tools.sh (preflight), build-release.sh (xcodebuild archive + export), make-dmg.sh (create-dmg with /Applications symlink + 600x380 layout), sign-update.sh (Sparkle EdDSA local signing via SPARKLE_ED_KEY env var — never in CI), update-appcast.sh (idempotent appcast.xml entry append). .github/workflows/release.yml triggers on git tag push, builds DMG on macos-15, uploads as draft GitHub Release. EdDSA signing remains a manual local step the maintainer runs after CI completes (rationale: one-maintainer OSS, private key never on GitHub). docs/RELEASE.md is the maintainer runbook (one-time key gen + per-release flow + recovery), docs/CHANGELOG.md initial entry for v1.0.0, docs/QA-CHECKLIST.md manual smoke checklist. README installing-section refreshed. ~257 unit tests across ~62 suites.
```

Also update the "## Implementation status" header (or whatever pre-amble tracks completion) to note that all 10 plans are now ✅.

- [ ] **Step 6: Final commit + tag**

```bash
git add VERSION project.yml docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "chore: bump VERSION to 1.0.0 + spec status (Plan 10 complete)"
git tag v1.0.0
```

Do NOT push the tag yet. The maintainer pushes when they're ready to trigger the release workflow (per docs/RELEASE.md).

---

## Self-review notes

- **Spec coverage:** Build chain (Tasks 4-7 ✓). Sparkle setup (Tasks 6, 11 ✓ — note: real EdDSA key generation is a one-time runbook step, not an automated task, per spec's "private key never in CI"). GitHub Actions release.yml (Task 10 ✓). Versioning (Task 14 ✓). README installation (Task 13 ✓). Schema cleanup left over from Plan 9 (Tasks 1-3 ✓). Repository layout (`scripts/`, `appcast/`, `.github/workflows/`, `docs/`) all populated.
- **Placeholder scan:** No "TBD". The runbook in Task 11 references the real `generate_keys` location and tells the maintainer the exact substitution to make. The `SPARKLE_ED_KEY` env var is documented end-to-end. The only thing the user must do by hand is generate the keypair — that's correct since the private key must never leave their machine.
- **Type consistency:** `databaseQueueForTesting` is added in DEBUG-only and used by one test. `Pair` struct local to emptyTrash is FetchableRecord-conforming (matches GRDB's existing usage in the file). Migration name `v2` matches naming style of `v1`.
- **Known caveat:** Tasks 4 and 5's smoke tests require `xcbeautify` and `create-dmg` installed locally. The check-tools script in Task 9 surfaces this. CI runner installs both via brew.
- **Caveat 2:** `find_keys` is not a typo of `generate_keys`; the runbook uses the latter (correct). `sign_update` is the binary used by `sign-update.sh` (also correct).
