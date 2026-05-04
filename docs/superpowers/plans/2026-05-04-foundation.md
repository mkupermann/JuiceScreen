# JuiceScreen — Foundation Implementation Plan (Plan 1 of 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship JuiceScreen `v0.1.0` — a menu-bar accessory app that builds cleanly, launches without crashing, registers global hotkeys via Carbon, runs the Screen Recording permission flow with a first-run wizard, exposes a stub Settings window with all six tabs, and has CI green. No actual screen-capture functionality yet — that is Plan 2.

**Architecture:** Single Xcode target. SwiftUI for chrome (windows, panels, settings tabs); AppKit for the menu bar item (`NSStatusItem`) and the Carbon hotkey wrapper. Module boundaries enforced at folder level — modules talk only through value types defined in `Shared/`. XcodeGen owns the project file (`project.yml`) so the `.xcodeproj` is regenerable from a YAML source of truth and not committed to the repo.

**Tech Stack:** Swift 5.10 / Swift 6, SwiftUI, AppKit, Carbon (`RegisterEventHotKey`), CoreGraphics (`CGRequestScreenCaptureAccess`), AVFoundation (`AVCaptureDevice` for mic), IOKit.hid (`IOHIDCheckAccess` for Input Monitoring), Swift Testing (unit tests), XCUITest (smoke test), XcodeGen, GitHub Actions.

**Spec reference:** `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

---

## File Structure

```
JuiceScreen/
├── .github/
│   └── workflows/
│       └── ci.yml                                  ← GitHub Actions: xcodegen + xcodebuild test
├── .gitignore
├── LICENSE                                         ← MIT
├── README.md                                       ← install, dev setup, project status
├── VERSION                                         ← single line: "0.1.0"
├── project.yml                                     ← XcodeGen source of truth
├── JuiceScreen/                                    ← app sources
│   ├── App/
│   │   ├── JuiceScreenApp.swift                    ← @main entry point (SwiftUI App)
│   │   ├── AppDelegate.swift                       ← lifecycle + dependency wiring
│   │   └── ActivationPolicyController.swift        ← .accessory <-> .regular toggle
│   ├── MenuBar/
│   │   ├── MenuBarController.swift                 ← NSStatusItem owner
│   │   ├── MenuBarMenuBuilder.swift                ← builds the dropdown menu
│   │   └── HotkeyService.swift                     ← Carbon RegisterEventHotKey wrapper
│   ├── Permissions/
│   │   ├── PermissionsService.swift                ← protocol + status/type enums
│   │   ├── PermissionsServiceLive.swift            ← real macOS implementation
│   │   ├── FakePermissionsService.swift            ← test double
│   │   ├── SettingsDeepLink.swift                  ← x-apple.systempreferences URLs
│   │   └── FirstRun/
│   │       ├── FirstRunCoordinator.swift           ← orchestrates the flow
│   │       ├── ScreenRecordingPermissionView.swift
│   │       ├── HotkeyConflictWizardView.swift
│   │       └── WelcomePanelView.swift
│   ├── Preferences/
│   │   ├── Preferences.swift                       ← value type holding all prefs
│   │   └── PreferencesStore.swift                  ← UserDefaults wrapper
│   ├── MainWindow/
│   │   └── Settings/
│   │       ├── SettingsWindow.swift                ← standalone NSWindow with tabs
│   │       ├── SettingsTab.swift                   ← enum of tab identities
│   │       ├── GeneralTab.swift                    ← stub
│   │       ├── CaptureTab.swift                    ← stub
│   │       ├── RecordingTab.swift                  ← stub
│   │       ├── HotkeysTab.swift                    ← stub
│   │       ├── StorageTab.swift                    ← stub
│   │       └── AboutTab.swift                      ← real (version, links)
│   ├── Shared/
│   │   ├── Hotkey.swift                            ← value type: keycode + modifiers
│   │   ├── KeyCodeFormatter.swift                  ← "⌘⇧4" rendering
│   │   └── Logger.swift                            ← os.Logger factory
│   └── Resources/
│       ├── Assets.xcassets/
│       │   └── AppIcon.appiconset/
│       ├── Info.plist
│       └── JuiceScreen.entitlements
├── JuiceScreenTests/
│   ├── HotkeyTests.swift
│   ├── KeyCodeFormatterTests.swift
│   ├── PreferencesStoreTests.swift
│   ├── FakePermissionsServiceTests.swift
│   └── FirstRunCoordinatorTests.swift
├── JuiceScreenUITests/
│   └── LaunchSmokeTests.swift                      ← app launches, menu bar icon present
└── docs/
    ├── README.md                                   ← (already exists from spec phase)
    └── superpowers/
        ├── specs/
        │   └── 2026-05-04-juicescreen-design.md    ← (already exists)
        └── plans/
            └── 2026-05-04-foundation.md            ← (this file)
```

---

## Task 1: Repo housekeeping (.gitignore, VERSION, LICENSE, README skeleton)

**Files:**
- Create: `.gitignore`
- Create: `VERSION`
- Create: `LICENSE`
- Create: `README.md`

- [ ] **Step 1: Write `.gitignore`**

```
# macOS
.DS_Store

# Xcode (generated)
*.xcodeproj/
DerivedData/
build/
*.xcworkspace/
xcuserdata/
*.xcuserstate
*.xcuserdatad/
*.moved-aside

# Swift Package Manager
.build/
Packages/
Package.resolved
.swiftpm/

# IDE noise
.idea/
.vscode/

# CI / local
*.dmg
*.zip
appcast/appcast.xml.bak

# Sparkle private key — never commit
sparkle_keys/
```

- [ ] **Step 2: Write `VERSION`**

```
0.1.0
```

(Single line, no newline-trimming surprises later. The build reads this file at build time via a Run Script phase added in Task 2.)

- [ ] **Step 3: Write `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Michael Kupermann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Write `README.md` (project root, distinct from `docs/README.md`)**

```markdown
# JuiceScreen

Open-source, 100% local screen capture for macOS. Region / window / full-screen / scroll capture, video recording with audio, annotation, OCR-indexed library search.

**Status:** Pre-alpha (Foundation milestone in progress). Not yet usable for capture.

## Installing

_Not yet — first usable build will ship at the end of Plan 2 (Image Capture)._

## Developing

Requires:
- macOS 14 Sonoma or newer
- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

Setup:

```bash
git clone https://github.com/mkupermann/JuiceScreen.git
cd JuiceScreen
xcodegen generate
open JuiceScreen.xcodeproj
```

Run tests:

```bash
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS'
```

## License

MIT. See `LICENSE`.

## Design

See `docs/superpowers/specs/2026-05-04-juicescreen-design.md` for the full design spec.
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore VERSION LICENSE README.md
git commit -m "chore: repo housekeeping (gitignore, VERSION, LICENSE, README skeleton)"
```

---

## Task 2: XcodeGen project.yml — app + tests + UI tests targets

**Files:**
- Create: `project.yml`

- [ ] **Step 1: Write `project.yml`**

```yaml
name: JuiceScreen
options:
  bundleIdPrefix: com.bks-lab
  deploymentTarget:
    macOS: "14.0"
  developmentLanguage: en
  createIntermediateGroups: true
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "5.10"
    SWIFT_STRICT_CONCURRENCY: complete
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    PRODUCT_NAME: JuiceScreen
    DEAD_CODE_STRIPPING: YES
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    GCC_TREAT_WARNINGS_AS_ERRORS: NO
    SWIFT_TREAT_WARNINGS_AS_ERRORS: NO

targets:
  JuiceScreen:
    type: application
    platform: macOS
    sources:
      - path: JuiceScreen
        excludes:
          - "**/*.md"
    resources:
      - path: JuiceScreen/Resources/Assets.xcassets
    info:
      path: JuiceScreen/Resources/Info.plist
      properties:
        CFBundleName: JuiceScreen
        CFBundleDisplayName: JuiceScreen
        CFBundleIdentifier: com.bks-lab.juicescreen
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSUIElement: true
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        NSHumanReadableCopyright: "© 2026 Michael Kupermann. MIT licensed."
        NSCameraUsageDescription: "JuiceScreen does not use the camera."
        NSMicrophoneUsageDescription: "JuiceScreen needs microphone access only when you enable mic recording during a screen recording. It is never accessed otherwise."
    entitlements:
      path: JuiceScreen/Resources/JuiceScreen.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.device.audio-input: true
        com.apple.security.device.camera: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.bks-lab.juicescreen
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
        DEVELOPMENT_TEAM: ""
    scheme:
      testTargets:
        - JuiceScreenTests
        - JuiceScreenUITests
      gatherCoverageData: true

  JuiceScreenTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: JuiceScreenTests
    dependencies:
      - target: JuiceScreen
    settings:
      base:
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/JuiceScreen.app/Contents/MacOS/JuiceScreen

  JuiceScreenUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - path: JuiceScreenUITests
    dependencies:
      - target: JuiceScreen
    settings:
      base:
        TEST_TARGET_NAME: JuiceScreen
```

- [ ] **Step 2: Create empty source dirs so XcodeGen has something to discover**

```bash
mkdir -p JuiceScreen/App
mkdir -p JuiceScreen/MenuBar
mkdir -p JuiceScreen/Permissions/FirstRun
mkdir -p JuiceScreen/Preferences
mkdir -p JuiceScreen/MainWindow/Settings
mkdir -p JuiceScreen/Shared
mkdir -p JuiceScreen/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p JuiceScreenTests
mkdir -p JuiceScreenUITests
```

- [ ] **Step 3: Create stub `Info.plist` and `JuiceScreen.entitlements`**

`JuiceScreen/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

(XcodeGen will inject the keys defined in `info.properties` at generation time.)

`JuiceScreen/Resources/JuiceScreen.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 4: Create `Assets.xcassets/Contents.json` and AppIcon stub**

`JuiceScreen/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`JuiceScreen/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

(Real icon assets ship in Plan 10; stubs are fine for Foundation.)

- [ ] **Step 5: Stub source files so the build has at least one .swift in each target**

`JuiceScreen/App/JuiceScreenApp.swift`:

```swift
import SwiftUI

@main
struct JuiceScreenApp: App {
    var body: some Scene {
        Settings { EmptyView() } // replaced in Task 14
    }
}
```

`JuiceScreenTests/PlaceholderTests.swift`:

```swift
import Testing

@Suite("Placeholder")
struct PlaceholderTests {
    @Test func placeholder() {
        #expect(true)
    }
}
```

`JuiceScreenUITests/PlaceholderUITests.swift`:

```swift
import XCTest

final class PlaceholderUITests: XCTestCase {
    func test_placeholder() throws {
        // Real smoke test in Task 23.
    }
}
```

- [ ] **Step 6: Generate the Xcode project and verify it builds**

Run:

```bash
brew install xcodegen 2>/dev/null || true
xcodegen generate
xcodebuild -list -project JuiceScreen.xcodeproj
```

Expected output: a list of targets including `JuiceScreen`, `JuiceScreenTests`, `JuiceScreenUITests` and a scheme `JuiceScreen`.

Run a build:

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **`. (Code signing should fall back to ad-hoc since `CODE_SIGN_IDENTITY: "-"` is set.)

Run tests:

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **` with the placeholder test passing.

- [ ] **Step 7: Commit**

```bash
git add project.yml JuiceScreen JuiceScreenTests JuiceScreenUITests
git commit -m "feat: scaffold XcodeGen project with app, unit, and UI test targets"
```

(Note: `.xcodeproj` is gitignored, not committed. Contributors regenerate via `xcodegen generate`.)

---

## Task 3: `Hotkey` value type + tests

**Files:**
- Create: `JuiceScreen/Shared/Hotkey.swift`
- Create: `JuiceScreenTests/HotkeyTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/HotkeyTests.swift`:

```swift
import Testing
@testable import JuiceScreen

@Suite("Hotkey value type")
struct HotkeyTests {

    @Test("Equality is by value")
    func equality() {
        let a = Hotkey(keyCode: 21, modifiers: [.command, .shift])
        let b = Hotkey(keyCode: 21, modifiers: [.shift, .command])
        let c = Hotkey(keyCode: 22, modifiers: [.command, .shift])
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Encodes round-trips via dictionary representation")
    func dictionaryRoundTrip() throws {
        let original = Hotkey(keyCode: 21, modifiers: [.command, .shift, .control])
        let dict = original.asDictionary
        let decoded = try #require(Hotkey(dictionary: dict))
        #expect(decoded == original)
    }

    @Test("Carbon modifier mask")
    func carbonMask() {
        let h = Hotkey(keyCode: 21, modifiers: [.command, .shift])
        // Carbon constants: cmdKey=256, shiftKey=512
        #expect(h.carbonModifierMask == 256 | 512)
    }

    @Test("Rejects empty modifier set")
    func rejectsBareKey() {
        // A hotkey with no modifiers would conflict with normal typing.
        // Hotkey is not a validation type, but PreferencesStore validates;
        // here we just confirm it permits any modifier set, even empty.
        let h = Hotkey(keyCode: 21, modifiers: [])
        #expect(h.modifiers.isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/HotkeyTests
```

Expected: compile failure — `Hotkey` is undefined.

- [ ] **Step 3: Implement `Hotkey.swift`**

`JuiceScreen/Shared/Hotkey.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// A combination of a virtual keycode + modifier flags representing a global hotkey.
/// Pure value type — no resource ownership. `HotkeyService` registers/unregisters with the system.
public struct Hotkey: Hashable, Sendable {

    /// Subset of `NSEvent.ModifierFlags` we accept. Keeping it narrow avoids
    /// confusion over deviceIndependentFlagsMask vs raw flags.
    public struct Modifier: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifier(rawValue: 1 << 0)
        public static let shift   = Modifier(rawValue: 1 << 1)
        public static let option  = Modifier(rawValue: 1 << 2)
        public static let control = Modifier(rawValue: 1 << 3)
    }

    public let keyCode: UInt32
    public let modifiers: Modifier

    public init(keyCode: UInt32, modifiers: Modifier) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Carbon-compatible modifier mask for `RegisterEventHotKey`.
    public var carbonModifierMask: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.shift)   { mask |= UInt32(shiftKey) }
        if modifiers.contains(.option)  { mask |= UInt32(optionKey) }
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    // MARK: - Dictionary representation (for UserDefaults persistence)

    public var asDictionary: [String: UInt32] {
        ["keyCode": keyCode, "modifiers": modifiers.rawValue]
    }

    public init?(dictionary: [String: UInt32]) {
        guard let keyCode = dictionary["keyCode"],
              let modRaw = dictionary["modifiers"] else { return nil }
        self.keyCode = keyCode
        self.modifiers = Modifier(rawValue: modRaw)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/HotkeyTests
```

Expected: `** TEST SUCCEEDED **`. All four test cases pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Shared/Hotkey.swift JuiceScreenTests/HotkeyTests.swift
git commit -m "feat(shared): add Hotkey value type with Carbon modifier mask + persistence dict"
```

---

## Task 4: `KeyCodeFormatter` + tests

**Files:**
- Create: `JuiceScreen/Shared/KeyCodeFormatter.swift`
- Create: `JuiceScreenTests/KeyCodeFormatterTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/KeyCodeFormatterTests.swift`:

```swift
import Testing
@testable import JuiceScreen

@Suite("KeyCodeFormatter")
struct KeyCodeFormatterTests {

    @Test("Renders ⌘⇧4")
    func cmdShift4() {
        // virtual keycode 21 = "4" on US layout
        let h = Hotkey(keyCode: 21, modifiers: [.command, .shift])
        #expect(KeyCodeFormatter.string(for: h) == "⌘⇧4")
    }

    @Test("Renders ⌃⇧L")
    func ctrlShiftL() {
        // virtual keycode 37 = "l" on US layout
        let h = Hotkey(keyCode: 37, modifiers: [.control, .shift])
        #expect(KeyCodeFormatter.string(for: h) == "⌃⇧L")
    }

    @Test("Modifier order is canonical: ⌃⌥⇧⌘")
    func modifierOrder() {
        let h = Hotkey(keyCode: 21, modifiers: [.command, .shift, .option, .control])
        #expect(KeyCodeFormatter.string(for: h) == "⌃⌥⇧⌘4")
    }

    @Test("Function keys render as F-N")
    func functionKey() {
        // virtual keycode 122 = F1
        let h = Hotkey(keyCode: 122, modifiers: [.command])
        #expect(KeyCodeFormatter.string(for: h) == "⌘F1")
    }

    @Test("Unknown keycode renders fallback hex token")
    func unknownKey() {
        let h = Hotkey(keyCode: 999, modifiers: [.command])
        #expect(KeyCodeFormatter.string(for: h) == "⌘<999>")
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/KeyCodeFormatterTests
```

Expected: compile failure — `KeyCodeFormatter` undefined.

- [ ] **Step 3: Implement `KeyCodeFormatter.swift`**

`JuiceScreen/Shared/KeyCodeFormatter.swift`:

```swift
import Carbon.HIToolbox

/// Renders a `Hotkey` as a human-readable string like "⌘⇧4".
/// Modifier order follows Apple HIG: Control, Option, Shift, Command.
public enum KeyCodeFormatter {

    public static func string(for hotkey: Hotkey) -> String {
        modifierString(for: hotkey.modifiers) + keyString(for: hotkey.keyCode)
    }

    private static func modifierString(for mods: Hotkey.Modifier) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s
    }

    private static func keyString(for keyCode: UInt32) -> String {
        // Function keys
        if let fn = functionKeyMap[keyCode] {
            return fn
        }
        // Letters & digits via TIS
        if let str = stringFromKeyCode(keyCode) {
            return str.uppercased()
        }
        return "<\(keyCode)>"
    }

    /// Translates a virtual keycode to a printable character via the current keyboard layout.
    /// Returns nil if the key is non-printable (function keys, modifier keys themselves).
    private static func stringFromKeyCode(_ keyCode: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutPtr = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutPtr), to: UnsafePointer<UCKeyboardLayout>.self)

        var keysDown: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var realLength = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &keysDown,
            chars.count,
            &realLength,
            &chars
        )
        guard status == noErr, realLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: realLength)
    }

    /// Function key mappings for keys that produce no character via UCKeyTranslate.
    private static let functionKeyMap: [UInt32: String] = [
        UInt32(kVK_F1):  "F1",  UInt32(kVK_F2):  "F2",  UInt32(kVK_F3):  "F3",
        UInt32(kVK_F4):  "F4",  UInt32(kVK_F5):  "F5",  UInt32(kVK_F6):  "F6",
        UInt32(kVK_F7):  "F7",  UInt32(kVK_F8):  "F8",  UInt32(kVK_F9):  "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓"
    ]
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/KeyCodeFormatterTests
```

Expected: all 5 cases pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Shared/KeyCodeFormatter.swift JuiceScreenTests/KeyCodeFormatterTests.swift
git commit -m "feat(shared): KeyCodeFormatter renders hotkeys as ⌃⌥⇧⌘<key> strings"
```

---

## Task 5: `Logger` factory

**Files:**
- Create: `JuiceScreen/Shared/Logger.swift`

(No tests — this is a thin factory and would require log-output capture which adds noise. Smoke test happens by other modules using it and producing visible output in Console.app.)

- [ ] **Step 1: Implement `Logger.swift`**

`JuiceScreen/Shared/Logger.swift`:

```swift
import os

/// Factory for category-tagged loggers under the `com.bks-lab.juicescreen` subsystem.
///
/// Usage:
/// ```
/// private let log = AppLog.logger(category: "MenuBar")
/// log.info("status item created")
/// ```
public enum AppLog {
    public static let subsystem = "com.bks-lab.juicescreen"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
```

- [ ] **Step 2: Verify it compiles by building**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Shared/Logger.swift
git commit -m "feat(shared): AppLog factory for os.Logger instances"
```

---

## Task 6: `PermissionsService` protocol + types

**Files:**
- Create: `JuiceScreen/Permissions/PermissionsService.swift`

- [ ] **Step 1: Implement `PermissionsService.swift`**

`JuiceScreen/Permissions/PermissionsService.swift`:

```swift
import Foundation

/// Status of a TCC permission as observed at a point in time.
public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Categories of TCC permissions JuiceScreen requests.
/// Accessibility (kTCCServiceAccessibility) is intentionally absent — see design spec §6.
public enum PermissionType: String, CaseIterable, Sendable {
    case screenRecording
    case microphone
    case inputMonitoring
}

/// Abstraction over macOS TCC. Live impl in `PermissionsServiceLive`.
/// Test impl in `FakePermissionsService` (test target).
public protocol PermissionsService: Sendable {
    func status(for permission: PermissionType) -> PermissionStatus

    /// Triggers the system permission prompt if `notDetermined`. No-op if already determined.
    func request(_ permission: PermissionType) async -> PermissionStatus

    /// Opens the appropriate System Settings pane for the user to toggle a permission manually.
    func openSettings(for permission: PermissionType)
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Permissions/PermissionsService.swift
git commit -m "feat(permissions): PermissionsService protocol + status/type enums"
```

---

## Task 7: `FakePermissionsService` + tests

**Files:**
- Create: `JuiceScreen/Permissions/FakePermissionsService.swift`
- Create: `JuiceScreenTests/FakePermissionsServiceTests.swift`

(`FakePermissionsService` lives in the main target, not the test target, because `FirstRunCoordinator` and SwiftUI previews both want to use it.)

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/FakePermissionsServiceTests.swift`:

```swift
import Testing
@testable import JuiceScreen

@Suite("FakePermissionsService")
struct FakePermissionsServiceTests {

    @Test("Returns configured status")
    func returnsConfiguredStatus() {
        let fake = FakePermissionsService(initial: [
            .screenRecording: .granted,
            .microphone: .denied,
            .inputMonitoring: .notDetermined
        ])
        #expect(fake.status(for: .screenRecording) == .granted)
        #expect(fake.status(for: .microphone) == .denied)
        #expect(fake.status(for: .inputMonitoring) == .notDetermined)
    }

    @Test("Defaults to notDetermined")
    func defaultsToNotDetermined() {
        let fake = FakePermissionsService()
        #expect(fake.status(for: .screenRecording) == .notDetermined)
    }

    @Test("Request transitions notDetermined to the configured next status")
    func requestUsesNextStatus() async {
        let fake = FakePermissionsService(initial: [.screenRecording: .notDetermined])
        fake.nextStatusOnRequest[.screenRecording] = .granted
        let result = await fake.request(.screenRecording)
        #expect(result == .granted)
        #expect(fake.status(for: .screenRecording) == .granted)
    }

    @Test("Request is no-op if already determined")
    func requestNoOpIfDetermined() async {
        let fake = FakePermissionsService(initial: [.screenRecording: .granted])
        fake.nextStatusOnRequest[.screenRecording] = .denied
        let result = await fake.request(.screenRecording)
        #expect(result == .granted)
    }

    @Test("openSettings records the call for tests to inspect")
    func openSettingsRecorded() {
        let fake = FakePermissionsService()
        fake.openSettings(for: .microphone)
        fake.openSettings(for: .screenRecording)
        #expect(fake.openedSettingsFor == [.microphone, .screenRecording])
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakePermissionsServiceTests
```

Expected: compile failure — `FakePermissionsService` undefined.

- [ ] **Step 3: Implement `FakePermissionsService.swift`**

`JuiceScreen/Permissions/FakePermissionsService.swift`:

```swift
import Foundation

/// Test double for `PermissionsService`. Mutable storage uses a lock for thread safety
/// because async tests may exercise it from multiple actors.
public final class FakePermissionsService: PermissionsService, @unchecked Sendable {

    private let lock = NSLock()
    private var statuses: [PermissionType: PermissionStatus]

    /// When `request(_:)` is called for a permission whose current status is
    /// `.notDetermined`, the value here becomes the new status.
    /// Defaults to `.granted` if not configured.
    public var nextStatusOnRequest: [PermissionType: PermissionStatus] = [:]

    /// Records each permission for which `openSettings(for:)` was called.
    public private(set) var openedSettingsFor: [PermissionType] = []

    public init(initial: [PermissionType: PermissionStatus] = [:]) {
        var seeded: [PermissionType: PermissionStatus] = [:]
        for type in PermissionType.allCases {
            seeded[type] = initial[type] ?? .notDetermined
        }
        self.statuses = seeded
    }

    public func status(for permission: PermissionType) -> PermissionStatus {
        lock.lock(); defer { lock.unlock() }
        return statuses[permission] ?? .notDetermined
    }

    public func request(_ permission: PermissionType) async -> PermissionStatus {
        lock.lock()
        let current = statuses[permission] ?? .notDetermined
        guard current == .notDetermined else {
            lock.unlock()
            return current
        }
        let next = nextStatusOnRequest[permission] ?? .granted
        statuses[permission] = next
        lock.unlock()
        return next
    }

    public func openSettings(for permission: PermissionType) {
        lock.lock(); defer { lock.unlock() }
        openedSettingsFor.append(permission)
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FakePermissionsServiceTests
```

Expected: all 5 cases pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Permissions/FakePermissionsService.swift JuiceScreenTests/FakePermissionsServiceTests.swift
git commit -m "feat(permissions): FakePermissionsService for tests and SwiftUI previews"
```

---

## Task 8: `SettingsDeepLink` for opening Privacy panes

**Files:**
- Create: `JuiceScreen/Permissions/SettingsDeepLink.swift`

(No unit test — `NSWorkspace.open` is a side effect we can't meaningfully assert against without launching System Settings. Smoke-tested manually in Task 19.)

- [ ] **Step 1: Implement `SettingsDeepLink.swift`**

`JuiceScreen/Permissions/SettingsDeepLink.swift`:

```swift
import AppKit

/// Deep links into specific panes of System Settings (macOS 13+).
/// URLs change between major macOS versions; these are valid for macOS 14+.
public enum SettingsDeepLink {

    public static func open(_ permission: PermissionType) {
        let url = url(for: permission)
        NSWorkspace.shared.open(url)
    }

    public static func openKeyboardShortcuts() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!
        NSWorkspace.shared.open(url)
    }

    private static func url(for permission: PermissionType) -> URL {
        switch permission {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Permissions/SettingsDeepLink.swift
git commit -m "feat(permissions): SettingsDeepLink to open Privacy + Keyboard Settings panes"
```

---

## Task 9: `PermissionsServiceLive` — Screen Recording, Microphone, Input Monitoring

**Files:**
- Create: `JuiceScreen/Permissions/PermissionsServiceLive.swift`

(No automated test — these wrap real system APIs that we cannot stub on CI runners. Manual smoke test as part of the first-run flow in Task 19.)

- [ ] **Step 1: Implement `PermissionsServiceLive.swift`**

`JuiceScreen/Permissions/PermissionsServiceLive.swift`:

```swift
import AppKit
import AVFoundation
import CoreGraphics
import IOKit.hid

public final class PermissionsServiceLive: PermissionsService {

    private let log = AppLog.logger(category: "PermissionsServiceLive")

    public init() {}

    public func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .screenRecording: return screenRecordingStatus()
        case .microphone:      return microphoneStatus()
        case .inputMonitoring: return inputMonitoringStatus()
        }
    }

    public func request(_ permission: PermissionType) async -> PermissionStatus {
        switch permission {
        case .screenRecording: return await requestScreenRecording()
        case .microphone:      return await requestMicrophone()
        case .inputMonitoring: return await requestInputMonitoring()
        }
    }

    public func openSettings(for permission: PermissionType) {
        SettingsDeepLink.open(permission)
    }

    // MARK: - Screen Recording

    private func screenRecordingStatus() -> PermissionStatus {
        // CGPreflightScreenCaptureAccess returns false if denied or notDetermined.
        // There is no public API to distinguish denied from notDetermined for
        // screen recording — Apple does not expose a TCC status query for it.
        // We treat false as `.denied` because the user-visible recovery is the same:
        // open System Settings and toggle the permission.
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }
        return .denied
    }

    private func requestScreenRecording() async -> PermissionStatus {
        // CGRequestScreenCaptureAccess triggers the TCC prompt the FIRST time only.
        // Subsequent calls when status is denied do nothing. The user then must
        // visit System Settings — handled by openSettings(for:).
        let granted = CGRequestScreenCaptureAccess()
        return granted ? .granted : .denied
    }

    // MARK: - Microphone

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined
        }
    }

    private func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    // MARK: - Input Monitoring

    private func inputMonitoringStatus() -> PermissionStatus {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        case kIOHIDAccessTypeUnknown:
            return .notDetermined
        default:
            return .notDetermined
        }
    }

    private func requestInputMonitoring() async -> PermissionStatus {
        // IOHIDRequestAccess is synchronous and triggers the TCC prompt on first call.
        // Subsequent calls when denied do nothing — same as Screen Recording.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        return granted ? .granted : .denied
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds. Compiler warnings about unused `log` are acceptable.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Permissions/PermissionsServiceLive.swift
git commit -m "feat(permissions): PermissionsServiceLive bridging CGScreenCapture, AVCaptureDevice, IOHID"
```

---

## Task 10: `Preferences` value type + `PreferencesStore` + tests

**Files:**
- Create: `JuiceScreen/Preferences/Preferences.swift`
- Create: `JuiceScreen/Preferences/PreferencesStore.swift`
- Create: `JuiceScreenTests/PreferencesStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/PreferencesStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("PreferencesStore")
struct PreferencesStoreTests {

    /// Each test gets its own ephemeral UserDefaults to avoid bleed.
    private func makeEphemeralStore() -> (PreferencesStore, UserDefaults) {
        let suiteName = "JuiceScreenTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (PreferencesStore(defaults: defaults), defaults)
    }

    @Test("First read returns sensible defaults")
    func defaults() {
        let (store, _) = makeEphemeralStore()
        let prefs = store.load()
        #expect(prefs.firstRunComplete == false)
        #expect(prefs.startAtLogin == false)
        #expect(prefs.captureRegionHotkey == Hotkey(keyCode: 21, modifiers: [.command, .shift]))
        #expect(prefs.saveDirectory.path.hasSuffix("Pictures/JuiceScreen"))
        #expect(prefs.defaultStillFormat == .png)
        #expect(prefs.jpegQuality == 0.9)
    }

    @Test("Saved hotkey round-trips")
    func hotkeyRoundTrip() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.captureFullScreenHotkey = Hotkey(keyCode: 20, modifiers: [.command, .control])
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.captureFullScreenHotkey == Hotkey(keyCode: 20, modifiers: [.command, .control]))
    }

    @Test("firstRunComplete persists")
    func firstRunCompletePersists() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.firstRunComplete = true
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.firstRunComplete == true)
    }

    @Test("Save directory persists")
    func saveDirectoryPersists() {
        let (store, _) = makeEphemeralStore()
        var prefs = store.load()
        prefs.saveDirectory = URL(fileURLWithPath: "/tmp/jstest")
        store.save(prefs)

        let reloaded = store.load()
        #expect(reloaded.saveDirectory.path == "/tmp/jstest")
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PreferencesStoreTests
```

Expected: compile failure — `Preferences` and `PreferencesStore` undefined.

- [ ] **Step 3: Implement `Preferences.swift`**

`JuiceScreen/Preferences/Preferences.swift`:

```swift
import Foundation

public enum StillImageFormat: String, Sendable, CaseIterable {
    case png
    case jpg
}

/// All user preferences for JuiceScreen. Pure value type — no I/O.
/// Persisted via `PreferencesStore`.
public struct Preferences: Equatable, Sendable {

    public var firstRunComplete: Bool
    public var startAtLogin: Bool

    public var saveDirectory: URL
    public var defaultStillFormat: StillImageFormat
    public var jpegQuality: Double          // 0.0 – 1.0

    public var captureRegionHotkey: Hotkey
    public var captureWindowHotkey: Hotkey
    public var captureFullScreenHotkey: Hotkey
    public var captureLastRegionHotkey: Hotkey
    public var recordScreenHotkey: Hotkey
    public var openLibraryHotkey: Hotkey

    public var hotkeysPaused: Bool

    public static let defaults: Preferences = {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        let saveDir = pictures.appendingPathComponent("JuiceScreen", isDirectory: true)

        return Preferences(
            firstRunComplete: false,
            startAtLogin: false,
            saveDirectory: saveDir,
            defaultStillFormat: .png,
            jpegQuality: 0.9,
            // virtual keycodes per Carbon: 21=4, 19=2, 20=3, 15=R, 23=5, 37=L
            captureRegionHotkey:     Hotkey(keyCode: 21, modifiers: [.command, .shift]),
            captureWindowHotkey:     Hotkey(keyCode: 19, modifiers: [.command, .shift]),
            captureFullScreenHotkey: Hotkey(keyCode: 20, modifiers: [.command, .shift]),
            captureLastRegionHotkey: Hotkey(keyCode: 15, modifiers: [.command, .shift]),
            recordScreenHotkey:      Hotkey(keyCode: 23, modifiers: [.command, .shift]),
            openLibraryHotkey:       Hotkey(keyCode: 37, modifiers: [.command, .shift]),
            hotkeysPaused: false
        )
    }()
}
```

- [ ] **Step 4: Implement `PreferencesStore.swift`**

`JuiceScreen/Preferences/PreferencesStore.swift`:

```swift
import Foundation

/// Reads/writes `Preferences` via `UserDefaults`. Single source of truth at runtime.
public final class PreferencesStore: @unchecked Sendable {

    private enum Key {
        static let firstRunComplete = "firstRunComplete"
        static let startAtLogin = "startAtLogin"
        static let saveDirectory = "saveDirectory"
        static let defaultStillFormat = "defaultStillFormat"
        static let jpegQuality = "jpegQuality"
        static let captureRegionHotkey = "captureRegionHotkey"
        static let captureWindowHotkey = "captureWindowHotkey"
        static let captureFullScreenHotkey = "captureFullScreenHotkey"
        static let captureLastRegionHotkey = "captureLastRegionHotkey"
        static let recordScreenHotkey = "recordScreenHotkey"
        static let openLibraryHotkey = "openLibraryHotkey"
        static let hotkeysPaused = "hotkeysPaused"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Preferences {
        let d = Preferences.defaults
        return Preferences(
            firstRunComplete:        defaults.object(forKey: Key.firstRunComplete) as? Bool ?? d.firstRunComplete,
            startAtLogin:            defaults.object(forKey: Key.startAtLogin) as? Bool ?? d.startAtLogin,
            saveDirectory:           loadURL(Key.saveDirectory) ?? d.saveDirectory,
            defaultStillFormat:      loadEnum(Key.defaultStillFormat) ?? d.defaultStillFormat,
            jpegQuality:             defaults.object(forKey: Key.jpegQuality) as? Double ?? d.jpegQuality,
            captureRegionHotkey:     loadHotkey(Key.captureRegionHotkey)     ?? d.captureRegionHotkey,
            captureWindowHotkey:     loadHotkey(Key.captureWindowHotkey)     ?? d.captureWindowHotkey,
            captureFullScreenHotkey: loadHotkey(Key.captureFullScreenHotkey) ?? d.captureFullScreenHotkey,
            captureLastRegionHotkey: loadHotkey(Key.captureLastRegionHotkey) ?? d.captureLastRegionHotkey,
            recordScreenHotkey:      loadHotkey(Key.recordScreenHotkey)      ?? d.recordScreenHotkey,
            openLibraryHotkey:       loadHotkey(Key.openLibraryHotkey)       ?? d.openLibraryHotkey,
            hotkeysPaused:           defaults.object(forKey: Key.hotkeysPaused) as? Bool ?? d.hotkeysPaused
        )
    }

    public func save(_ prefs: Preferences) {
        defaults.set(prefs.firstRunComplete, forKey: Key.firstRunComplete)
        defaults.set(prefs.startAtLogin, forKey: Key.startAtLogin)
        saveURL(prefs.saveDirectory, key: Key.saveDirectory)
        defaults.set(prefs.defaultStillFormat.rawValue, forKey: Key.defaultStillFormat)
        defaults.set(prefs.jpegQuality, forKey: Key.jpegQuality)
        saveHotkey(prefs.captureRegionHotkey,     key: Key.captureRegionHotkey)
        saveHotkey(prefs.captureWindowHotkey,     key: Key.captureWindowHotkey)
        saveHotkey(prefs.captureFullScreenHotkey, key: Key.captureFullScreenHotkey)
        saveHotkey(prefs.captureLastRegionHotkey, key: Key.captureLastRegionHotkey)
        saveHotkey(prefs.recordScreenHotkey,      key: Key.recordScreenHotkey)
        saveHotkey(prefs.openLibraryHotkey,       key: Key.openLibraryHotkey)
        defaults.set(prefs.hotkeysPaused, forKey: Key.hotkeysPaused)
    }

    // MARK: - Helpers

    private func loadHotkey(_ key: String) -> Hotkey? {
        guard let dict = defaults.dictionary(forKey: key) as? [String: UInt32] else { return nil }
        return Hotkey(dictionary: dict)
    }

    private func saveHotkey(_ hotkey: Hotkey, key: String) {
        defaults.set(hotkey.asDictionary, forKey: key)
    }

    private func loadURL(_ key: String) -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func saveURL(_ url: URL, key: String) {
        defaults.set(url.path, forKey: key)
    }

    private func loadEnum(_ key: String) -> StillImageFormat? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return StillImageFormat(rawValue: raw)
    }
}
```

- [ ] **Step 5: Run, verify pass**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/PreferencesStoreTests
```

Expected: all 4 cases pass.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/Preferences/Preferences.swift JuiceScreen/Preferences/PreferencesStore.swift JuiceScreenTests/PreferencesStoreTests.swift
git commit -m "feat(preferences): Preferences value type + UserDefaults-backed store"
```

---

## Task 11: `HotkeyService` — Carbon RegisterEventHotKey wrapper

**Files:**
- Create: `JuiceScreen/MenuBar/HotkeyService.swift`

(No automated test — Carbon hotkeys require a running event loop and entitled application. Smoke-tested by hand by running the app after Task 16.)

- [ ] **Step 1: Implement `HotkeyService.swift`**

`JuiceScreen/MenuBar/HotkeyService.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// Identifies a hotkey within JuiceScreen. Sent into Carbon as the EventHotKeyID `id`.
public enum HotkeyAction: UInt32, CaseIterable, Sendable {
    case captureRegion     = 1
    case captureWindow     = 2
    case captureFullScreen = 3
    case captureLastRegion = 4
    case recordScreen      = 5
    case openLibrary       = 6
    case stopRecording     = 7  // dynamically (un)bound during a recording session
}

/// Registers global hotkeys via Carbon and dispatches their fire events to a closure.
/// One service instance per process. Not thread-safe; call from the main thread.
public final class HotkeyService {

    private let log = AppLog.logger(category: "HotkeyService")
    private let signature: OSType = OSType(0x4A555352) // 'JUSR'

    private var registrations: [HotkeyAction: EventHotKeyRef] = [:]
    private var handlers: [HotkeyAction: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    public init() {
        installEventHandler()
    }

    deinit {
        for (_, ref) in registrations {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Registers `hotkey` for `action`. Replaces any prior binding for the same action.
    /// Returns true if registration succeeded.
    @discardableResult
    public func register(_ hotkey: Hotkey, for action: HotkeyAction, handler: @escaping () -> Void) -> Bool {
        unregister(action)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifierMask,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed for \(action.rawValue): OSStatus=\(status)")
            return false
        }
        registrations[action] = ref
        handlers[action] = handler
        return true
    }

    public func unregister(_ action: HotkeyAction) {
        if let ref = registrations.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: action)
    }

    public func unregisterAll() {
        for action in HotkeyAction.allCases {
            unregister(action)
        }
    }

    // MARK: - Carbon event handler bridge

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout.size(ofValue: hkID),
                    nil,
                    &hkID
                )
                guard status == noErr,
                      let action = HotkeyAction(rawValue: hkID.id) else { return noErr }
                service.handlers[action]?()
                return noErr
            },
            1,
            &spec,
            userData,
            &eventHandler
        )
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds. Carbon import works.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MenuBar/HotkeyService.swift
git commit -m "feat(menubar): HotkeyService wrapping Carbon RegisterEventHotKey"
```

---

## Task 12: `ActivationPolicyController` — toggle .accessory ↔ .regular

**Files:**
- Create: `JuiceScreen/App/ActivationPolicyController.swift`

(No automated test — observes `NSWindow` notifications which require a running app.)

- [ ] **Step 1: Implement `ActivationPolicyController.swift`**

`JuiceScreen/App/ActivationPolicyController.swift`:

```swift
import AppKit

/// Promotes the app from `.accessory` (no Dock icon) to `.regular` while any non-status
/// window is visible, then demotes back to `.accessory` once the last one closes.
/// Pattern used by Things, Bear, and other menu-bar-with-windows apps.
@MainActor
public final class ActivationPolicyController {

    private let log = AppLog.logger(category: "ActivationPolicy")
    private var observers: [NSObjectProtocol] = []

    public init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.evaluate()
        })
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            // Re-evaluate after the window is removed from NSApp.windows.
            DispatchQueue.main.async { self?.evaluate() }
        })
        evaluate()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver(_:))
    }

    private func evaluate() {
        let hasUserWindow = NSApp.windows.contains { window in
            window.isVisible && !window.className.contains("StatusBar")
        }
        let desired: NSApplication.ActivationPolicy = hasUserWindow ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
            log.info("Activation policy → \(String(describing: desired))")
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/App/ActivationPolicyController.swift
git commit -m "feat(app): ActivationPolicyController toggles .accessory <-> .regular by visible windows"
```

---

## Task 13: `MenuBarMenuBuilder` — builds the dropdown structure

**Files:**
- Create: `JuiceScreen/MenuBar/MenuBarMenuBuilder.swift`

- [ ] **Step 1: Implement `MenuBarMenuBuilder.swift`**

`JuiceScreen/MenuBar/MenuBarMenuBuilder.swift`:

```swift
import AppKit

/// Action callbacks supplied to the menu builder. Each is fired when the corresponding
/// menu item is chosen. Real implementations land in later plans (capture, recording, etc.);
/// for Foundation they log a TODO message.
@MainActor
public struct MenuBarActions {
    public var captureRegion: () -> Void
    public var captureWindow: () -> Void
    public var captureFullScreen: () -> Void
    public var captureLastRegion: () -> Void
    public var recordScreen: () -> Void
    public var openLibrary: () -> Void
    public var openPreferences: () -> Void
    public var quit: () -> Void

    public init(captureRegion: @escaping () -> Void,
                captureWindow: @escaping () -> Void,
                captureFullScreen: @escaping () -> Void,
                captureLastRegion: @escaping () -> Void,
                recordScreen: @escaping () -> Void,
                openLibrary: @escaping () -> Void,
                openPreferences: @escaping () -> Void,
                quit: @escaping () -> Void) {
        self.captureRegion = captureRegion
        self.captureWindow = captureWindow
        self.captureFullScreen = captureFullScreen
        self.captureLastRegion = captureLastRegion
        self.recordScreen = recordScreen
        self.openLibrary = openLibrary
        self.openPreferences = openPreferences
        self.quit = quit
    }
}

@MainActor
public enum MenuBarMenuBuilder {

    public static func build(prefs: Preferences, actions: MenuBarActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(item("Capture Region",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureRegionHotkey),
                          action: actions.captureRegion))
        menu.addItem(item("Capture Window",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureWindowHotkey),
                          action: actions.captureWindow))
        menu.addItem(item("Capture Full Screen",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureFullScreenHotkey),
                          action: actions.captureFullScreen))
        menu.addItem(item("Capture Last Region",
                          shortcut: KeyCodeFormatter.string(for: prefs.captureLastRegionHotkey),
                          action: actions.captureLastRegion))

        menu.addItem(.separator())
        menu.addItem(item("Record Screen",
                          shortcut: KeyCodeFormatter.string(for: prefs.recordScreenHotkey),
                          action: actions.recordScreen))

        menu.addItem(.separator())
        menu.addItem(item("Open Library",
                          shortcut: KeyCodeFormatter.string(for: prefs.openLibraryHotkey),
                          action: actions.openLibrary))

        menu.addItem(.separator())
        menu.addItem(item("Preferences…",
                          shortcut: "⌘,",
                          action: actions.openPreferences))
        menu.addItem(item("Quit JuiceScreen",
                          shortcut: "⌘Q",
                          action: actions.quit))

        return menu
    }

    private static func item(_ title: String, shortcut: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.keyEquivalent = ""             // hotkeys handled by HotkeyService, not NSMenu
        item.toolTip = shortcut
        let attr = NSMutableAttributedString(string: title)
        // Render shortcut in a faded trailing chunk for visual parity with system menus
        let pad = String(repeating: " ", count: max(2, 28 - title.count))
        attr.append(NSAttributedString(string: pad + shortcut,
                                       attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        item.attributedTitle = attr
        return item
    }
}

/// Trampolines `NSMenuItem` action selectors into a Swift closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.closure = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { closure() }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MenuBar/MenuBarMenuBuilder.swift
git commit -m "feat(menubar): MenuBarMenuBuilder constructs the full dropdown structure"
```

---

## Task 14: `MenuBarController` — owns NSStatusItem

**Files:**
- Create: `JuiceScreen/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Implement `MenuBarController.swift`**

`JuiceScreen/MenuBar/MenuBarController.swift`:

```swift
import AppKit

@MainActor
public final class MenuBarController {

    private let log = AppLog.logger(category: "MenuBar")
    private let statusItem: NSStatusItem
    private var prefs: Preferences
    private let actions: MenuBarActions

    public init(prefs: Preferences, actions: MenuBarActions) {
        self.prefs = prefs
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()
        rebuildMenu()
        log.info("Menu bar item created")
    }

    /// Rebuild the menu when preferences (e.g., hotkeys) change.
    public func update(prefs: Preferences) {
        self.prefs = prefs
        rebuildMenu()
    }

    /// Toggle the menu-bar icon to indicate an active recording.
    public func setRecordingIndicator(_ recording: Bool) {
        statusItem.button?.image = recording ? recordingImage : idleImage
    }

    // MARK: - Setup

    private func configureButton() {
        statusItem.button?.image = idleImage
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "JuiceScreen"
    }

    private func rebuildMenu() {
        statusItem.menu = MenuBarMenuBuilder.build(prefs: prefs, actions: actions)
    }

    // MARK: - Icons (system-symbol stubs; designed art lands in Plan 10)

    private var idleImage: NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "JuiceScreen")
        img?.isTemplate = true
        return img?.withSymbolConfiguration(cfg)
    }

    private var recordingImage: NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
        img?.isTemplate = true
        return img?.withSymbolConfiguration(cfg)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/MenuBar/MenuBarController.swift
git commit -m "feat(menubar): MenuBarController owns NSStatusItem and rebuilds menu on prefs change"
```

---

## Task 15: Settings stub — window + 6 tabs

**Files:**
- Create: `JuiceScreen/MainWindow/Settings/SettingsTab.swift`
- Create: `JuiceScreen/MainWindow/Settings/SettingsWindow.swift`
- Create: `JuiceScreen/MainWindow/Settings/GeneralTab.swift`
- Create: `JuiceScreen/MainWindow/Settings/CaptureTab.swift`
- Create: `JuiceScreen/MainWindow/Settings/RecordingTab.swift`
- Create: `JuiceScreen/MainWindow/Settings/HotkeysTab.swift`
- Create: `JuiceScreen/MainWindow/Settings/StorageTab.swift`
- Create: `JuiceScreen/MainWindow/Settings/AboutTab.swift`

(No tests — these are SwiftUI views with placeholder content. Real interactivity in later plans.)

- [ ] **Step 1: Implement `SettingsTab.swift`**

```swift
import Foundation

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, capture, recording, hotkeys, storage, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general:   return "General"
        case .capture:   return "Capture"
        case .recording: return "Recording"
        case .hotkeys:   return "Hotkeys"
        case .storage:   return "Storage"
        case .about:     return "About"
        }
    }

    public var symbol: String {
        switch self {
        case .general:   return "gear"
        case .capture:   return "camera"
        case .recording: return "record.circle"
        case .hotkeys:   return "keyboard"
        case .storage:   return "internaldrive"
        case .about:     return "info.circle"
        }
    }
}
```

- [ ] **Step 2: Implement each tab as a stub**

Create five separate files, each with the explicit code below.

`JuiceScreen/MainWindow/Settings/GeneralTab.swift`:

```swift
import SwiftUI

struct GeneralTab: View {
    var body: some View {
        Form {
            Section {
                Text("General settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("General")
            } footer: {
                Text("Wired up in a later plan.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

`JuiceScreen/MainWindow/Settings/CaptureTab.swift`:

```swift
import SwiftUI

struct CaptureTab: View {
    var body: some View {
        Form {
            Section {
                Text("Capture settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Capture")
            } footer: {
                Text("Wired up in a later plan.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

`JuiceScreen/MainWindow/Settings/RecordingTab.swift`:

```swift
import SwiftUI

struct RecordingTab: View {
    var body: some View {
        Form {
            Section {
                Text("Recording settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Recording")
            } footer: {
                Text("Wired up in a later plan.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

`JuiceScreen/MainWindow/Settings/HotkeysTab.swift`:

```swift
import SwiftUI

struct HotkeysTab: View {
    var body: some View {
        Form {
            Section {
                Text("Hotkey configuration will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Wired up in a later plan.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

`JuiceScreen/MainWindow/Settings/StorageTab.swift`:

```swift
import SwiftUI

struct StorageTab: View {
    var body: some View {
        Form {
            Section {
                Text("Storage settings will live here.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Storage")
            } footer: {
                Text("Wired up in a later plan.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 3: Implement `AboutTab.swift` (real content)**

`JuiceScreen/MainWindow/Settings/AboutTab.swift`:

```swift
import SwiftUI

struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("JuiceScreen")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)

            Text("Open-source, 100% local screen capture for macOS.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/mkupermann/JuiceScreen")!)
                Link("MIT License", destination: URL(string: "https://github.com/mkupermann/JuiceScreen/blob/main/LICENSE")!)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Implement `SettingsWindow.swift`**

`JuiceScreen/MainWindow/Settings/SettingsWindow.swift`:

```swift
import SwiftUI
import AppKit

@MainActor
public final class SettingsWindow {

    private static var window: NSWindow?

    public static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "JuiceScreen Settings"
        window.contentView = NSHostingView(rootView: SettingsContainer())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }
}

private struct SettingsContainer: View {
    @State private var selection: SettingsTab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab().tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }.tag(SettingsTab.general)
            CaptureTab().tabItem { Label(SettingsTab.capture.title, systemImage: SettingsTab.capture.symbol) }.tag(SettingsTab.capture)
            RecordingTab().tabItem { Label(SettingsTab.recording.title, systemImage: SettingsTab.recording.symbol) }.tag(SettingsTab.recording)
            HotkeysTab().tabItem { Label(SettingsTab.hotkeys.title, systemImage: SettingsTab.hotkeys.symbol) }.tag(SettingsTab.hotkeys)
            StorageTab().tabItem { Label(SettingsTab.storage.title, systemImage: SettingsTab.storage.symbol) }.tag(SettingsTab.storage)
            AboutTab().tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.symbol) }.tag(SettingsTab.about)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add JuiceScreen/MainWindow/Settings
git commit -m "feat(settings): stub Settings window with 6 tabs (About is fully wired, rest placeholders)"
```

---

## Task 16: First-run views — `ScreenRecordingPermissionView`, `WelcomePanelView`

**Files:**
- Create: `JuiceScreen/Permissions/FirstRun/ScreenRecordingPermissionView.swift`
- Create: `JuiceScreen/Permissions/FirstRun/WelcomePanelView.swift`

- [ ] **Step 1: Implement `ScreenRecordingPermissionView.swift`**

```swift
import SwiftUI

struct ScreenRecordingPermissionView: View {

    let onGrant: () -> Void
    let onOpenSettings: () -> Void
    var onSkip: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Screen Recording permission needed")
                .font(.title3).fontWeight(.semibold)

            Text("JuiceScreen captures your screen using Apple's Screen Recording API. macOS requires you to grant permission once. After granting, you may need to relaunch the app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            HStack {
                Button("Open System Settings") { onOpenSettings() }
                Button("Grant Permission") { onGrant() }
                    .keyboardShortcut(.defaultAction)
            }

            if let onSkip {
                Button("Continue without (capture will not work)") { onSkip() }
                    .buttonStyle(.link)
                    .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(width: 520, height: 320)
    }
}
```

- [ ] **Step 2: Implement `WelcomePanelView.swift`**

```swift
import SwiftUI

struct WelcomePanelView: View {

    let regionShortcut: String
    let recordShortcut: String
    let libraryShortcut: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to JuiceScreen")
                .font(.title3).fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                line("Press \(regionShortcut) to capture a region")
                line("Press \(recordShortcut) to record your screen")
                line("Open the Library with \(libraryShortcut)")
            }

            HStack {
                Spacer()
                Button("Got it") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 460)
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.body)
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add JuiceScreen/Permissions/FirstRun/ScreenRecordingPermissionView.swift JuiceScreen/Permissions/FirstRun/WelcomePanelView.swift
git commit -m "feat(firstrun): ScreenRecordingPermissionView + WelcomePanelView (brutal minimal)"
```

---

## Task 17: `HotkeyConflictWizardView`

**Files:**
- Create: `JuiceScreen/Permissions/FirstRun/HotkeyConflictWizardView.swift`

- [ ] **Step 1: Implement `HotkeyConflictWizardView.swift`**

```swift
import SwiftUI

struct HotkeyConflictWizardView: View {

    let onOpenKeyboardSettings: () -> Void
    let onUseAlternativeDefaults: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Hotkey conflict with macOS")
                .font(.title3).fontWeight(.semibold)

            Text("JuiceScreen wants to use ⌘⇧3, ⌘⇧4, and ⌘⇧5 for its capture and record shortcuts. macOS already uses these for the built-in screenshot tool.")
                .foregroundStyle(.secondary)

            Text("To let JuiceScreen claim them, open Keyboard Settings → Shortcuts → Screenshots and uncheck the conflicting items. You can also keep the alternative defaults below — JuiceScreen will use a different combo and the system shortcuts continue to work.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Skip") { onSkip() }
                Spacer()
                Button("Use alternative defaults") { onUseAlternativeDefaults() }
                Button("Open Keyboard Settings") { onOpenKeyboardSettings() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 560)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Permissions/FirstRun/HotkeyConflictWizardView.swift
git commit -m "feat(firstrun): HotkeyConflictWizardView for ⌘⇧3/4/5 conflicts"
```

---

## Task 18: `FirstRunCoordinator` + tests

**Files:**
- Create: `JuiceScreen/Permissions/FirstRun/FirstRunCoordinator.swift`
- Create: `JuiceScreenTests/FirstRunCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

`JuiceScreenTests/FirstRunCoordinatorTests.swift`:

```swift
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FirstRunCoordinator")
@MainActor
struct FirstRunCoordinatorTests {

    private func ephemeralStore() -> PreferencesStore {
        let suite = "JuiceScreenTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PreferencesStore(defaults: defaults)
    }

    @Test("Initial state is awaitingScreenRecording when permission notDetermined")
    func initialNotDetermined() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .notDetermined])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        #expect(coordinator.state == .awaitingScreenRecording)
    }

    @Test("If screen recording already granted on first run, jumps to hotkey wizard")
    func grantedJumpsToHotkeys() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        #expect(coordinator.state == .awaitingHotkeyDecision)
    }

    @Test("If first run already complete, state is .done immediately")
    func alreadyComplete() {
        let store = ephemeralStore()
        var prefs = store.load()
        prefs.firstRunComplete = true
        store.save(prefs)
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        #expect(coordinator.state == .done)
    }

    @Test("Granting permission advances to hotkey decision")
    func grantAdvances() async {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .notDetermined])
        perms.nextStatusOnRequest[.screenRecording] = .granted
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        await coordinator.requestScreenRecording()
        #expect(coordinator.state == .awaitingHotkeyDecision)
    }

    @Test("Hotkey decision advances to welcome")
    func hotkeyDecisionAdvances() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        coordinator.acceptHotkeyDefaults()
        #expect(coordinator.state == .awaitingWelcomeDismiss)
    }

    @Test("Dismissing welcome marks first run complete and reaches .done")
    func welcomeDismissPersists() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        coordinator.acceptHotkeyDefaults()
        coordinator.dismissWelcome()
        #expect(coordinator.state == .done)
        #expect(store.load().firstRunComplete == true)
    }

    @Test("Choosing alternative hotkeys writes them to preferences")
    func alternativeHotkeysPersist() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        coordinator.useAlternativeHotkeys()
        let prefs = store.load()
        // Alternatives use ⌘⌃ instead of ⌘⇧ to avoid the macOS screenshot conflict
        #expect(prefs.captureRegionHotkey.modifiers == [.command, .control])
        #expect(prefs.captureFullScreenHotkey.modifiers == [.command, .control])
        #expect(prefs.recordScreenHotkey.modifiers == [.command, .control])
    }
}
```

- [ ] **Step 2: Run, verify it fails**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FirstRunCoordinatorTests
```

Expected: compile failure — `FirstRunCoordinator` undefined.

- [ ] **Step 3: Implement `FirstRunCoordinator.swift`**

```swift
import Foundation
import Observation

/// Drives the four-step first-run flow: screen recording permission → hotkey decision → welcome → done.
/// Owns no UI; views observe `state` and call back into the coordinator's methods.
@MainActor
@Observable
public final class FirstRunCoordinator {

    public enum State: Equatable {
        case awaitingScreenRecording
        case awaitingHotkeyDecision
        case awaitingWelcomeDismiss
        case done
    }

    public private(set) var state: State

    private let permissions: PermissionsService
    private let preferences: PreferencesStore
    private let log = AppLog.logger(category: "FirstRun")

    public init(permissions: PermissionsService, preferences: PreferencesStore) {
        self.permissions = permissions
        self.preferences = preferences

        let prefs = preferences.load()
        if prefs.firstRunComplete {
            self.state = .done
        } else {
            switch permissions.status(for: .screenRecording) {
            case .granted:      self.state = .awaitingHotkeyDecision
            case .denied,
                 .notDetermined: self.state = .awaitingScreenRecording
            }
        }
    }

    /// Re-evaluates state. Call when the view wants to drive the flow forward without an action
    /// (for example, to skip to .awaitingHotkeyDecision when permission is already granted).
    public func start() {
        guard state != .done else { return }
        if state == .awaitingScreenRecording,
           permissions.status(for: .screenRecording) == .granted {
            state = .awaitingHotkeyDecision
        }
    }

    public func requestScreenRecording() async {
        let result = await permissions.request(.screenRecording)
        log.info("Screen recording permission result: \(String(describing: result))")
        if result == .granted {
            state = .awaitingHotkeyDecision
        }
    }

    public func openScreenRecordingSettings() {
        permissions.openSettings(for: .screenRecording)
    }

    public func skipScreenRecording() {
        // User chose to continue without permission. Capture won't work but the app should not be blocked.
        state = .awaitingHotkeyDecision
    }

    public func acceptHotkeyDefaults() {
        state = .awaitingWelcomeDismiss
    }

    public func useAlternativeHotkeys() {
        var prefs = preferences.load()
        // Swap shift→control on the conflicting trio so we coexist with the macOS shortcuts.
        prefs.captureRegionHotkey     = Hotkey(keyCode: 21, modifiers: [.command, .control])
        prefs.captureFullScreenHotkey = Hotkey(keyCode: 20, modifiers: [.command, .control])
        prefs.recordScreenHotkey      = Hotkey(keyCode: 23, modifiers: [.command, .control])
        preferences.save(prefs)
        state = .awaitingWelcomeDismiss
    }

    public func dismissWelcome() {
        var prefs = preferences.load()
        prefs.firstRunComplete = true
        preferences.save(prefs)
        state = .done
    }
}
```

- [ ] **Step 4: Run, verify pass**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenTests/FirstRunCoordinatorTests
```

Expected: all 7 cases pass.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/Permissions/FirstRun/FirstRunCoordinator.swift JuiceScreenTests/FirstRunCoordinatorTests.swift
git commit -m "feat(firstrun): FirstRunCoordinator state machine for permission/hotkey/welcome flow"
```

---

## Task 19: `FirstRunWindow` — host views and bind to coordinator

**Files:**
- Create: `JuiceScreen/Permissions/FirstRun/FirstRunWindow.swift`

- [ ] **Step 1: Implement `FirstRunWindow.swift`**

```swift
import SwiftUI
import AppKit

@MainActor
public final class FirstRunWindow {

    private static var window: NSWindow?

    public static func showIfNeeded(coordinator: FirstRunCoordinator) {
        guard coordinator.state != .done else { return }
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "JuiceScreen — Setup"
        window.contentView = NSHostingView(rootView: FirstRunHost(coordinator: coordinator) {
            window.close()
            Self.window = nil
        })
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }
}

private struct FirstRunHost: View {
    @Bindable var coordinator: FirstRunCoordinator
    let onDone: () -> Void

    var body: some View {
        Group {
            switch coordinator.state {
            case .awaitingScreenRecording:
                ScreenRecordingPermissionView(
                    onGrant: { Task { await coordinator.requestScreenRecording() } },
                    onOpenSettings: { coordinator.openScreenRecordingSettings() },
                    onSkip: { coordinator.skipScreenRecording() }
                )

            case .awaitingHotkeyDecision:
                HotkeyConflictWizardView(
                    onOpenKeyboardSettings: { SettingsDeepLink.openKeyboardShortcuts() },
                    onUseAlternativeDefaults: { coordinator.useAlternativeHotkeys() },
                    onSkip: { coordinator.acceptHotkeyDefaults() }
                )

            case .awaitingWelcomeDismiss:
                WelcomePanelView(
                    regionShortcut: "⌘⇧4",
                    recordShortcut: "⌘⇧5",
                    libraryShortcut: "⌘⇧L",
                    onDismiss: { coordinator.dismissWelcome() }
                )

            case .done:
                Color.clear.onAppear { onDone() }
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add JuiceScreen/Permissions/FirstRun/FirstRunWindow.swift
git commit -m "feat(firstrun): FirstRunWindow hosts the wizard views bound to FirstRunCoordinator"
```

---

## Task 20: `AppDelegate` — wire dependencies, drive first run, register hotkeys

**Files:**
- Create: `JuiceScreen/App/AppDelegate.swift`
- Modify: `JuiceScreen/App/JuiceScreenApp.swift`

- [ ] **Step 1: Implement `AppDelegate.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let log = AppLog.logger(category: "App")

    private let permissions: PermissionsService = PermissionsServiceLive()
    private let preferences = PreferencesStore()
    private let hotkeyService = HotkeyService()

    private var menuBar: MenuBarController?
    private var firstRun: FirstRunCoordinator?
    private var activationPolicy: ActivationPolicyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("JuiceScreen launching")

        // Activation policy controller (sets initial state to .accessory)
        activationPolicy = ActivationPolicyController()

        // Menu bar
        let actions = MenuBarActions(
            captureRegion:     { [weak self] in self?.todoLog("captureRegion") },
            captureWindow:     { [weak self] in self?.todoLog("captureWindow") },
            captureFullScreen: { [weak self] in self?.todoLog("captureFullScreen") },
            captureLastRegion: { [weak self] in self?.todoLog("captureLastRegion") },
            recordScreen:      { [weak self] in self?.todoLog("recordScreen") },
            openLibrary:       { [weak self] in self?.todoLog("openLibrary") },
            openPreferences:   { SettingsWindow.show() },
            quit:              { NSApp.terminate(nil) }
        )
        let prefs = preferences.load()
        menuBar = MenuBarController(prefs: prefs, actions: actions)

        // Hotkeys
        registerHotkeys(prefs: prefs, actions: actions)

        // First-run wizard (no-op if already complete)
        let coordinator = FirstRunCoordinator(permissions: permissions, preferences: preferences)
        firstRun = coordinator
        coordinator.start()
        FirstRunWindow.showIfNeeded(coordinator: coordinator)
    }

    private func registerHotkeys(prefs: Preferences, actions: MenuBarActions) {
        hotkeyService.register(prefs.captureRegionHotkey,     for: .captureRegion)     { actions.captureRegion() }
        hotkeyService.register(prefs.captureWindowHotkey,     for: .captureWindow)     { actions.captureWindow() }
        hotkeyService.register(prefs.captureFullScreenHotkey, for: .captureFullScreen) { actions.captureFullScreen() }
        hotkeyService.register(prefs.captureLastRegionHotkey, for: .captureLastRegion) { actions.captureLastRegion() }
        hotkeyService.register(prefs.recordScreenHotkey,      for: .recordScreen)      { actions.recordScreen() }
        hotkeyService.register(prefs.openLibraryHotkey,       for: .openLibrary)       { actions.openLibrary() }
    }

    private func todoLog(_ what: String) {
        log.info("TODO: \(what) action — implemented in a later plan")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app — don't quit when user closes the Settings window.
        false
    }
}
```

- [ ] **Step 2: Modify `JuiceScreenApp.swift` to use the delegate**

Replace the entire file content:

```swift
import SwiftUI

@main
struct JuiceScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Empty scene — UI is owned by AppDelegate (menu bar + on-demand windows).
        // Settings { EmptyView() } would show a Settings menu item in a regular app;
        // we use a custom SettingsWindow instead, so we use an empty Settings scene.
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
```

Expected: succeeds.

- [ ] **Step 4: Manual smoke test**

```bash
# Run the app from the build output
open "$(xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
```

Expected:
- Menu bar icon appears (camera.viewfinder symbol)
- Click → menu shows all 8 entries with shortcut labels
- "Preferences…" opens the Settings window with 6 tabs
- About tab shows "Version 0.1.0 (1)"
- First time you run: the screen recording permission window may appear
- Click each capture/record menu item: Console.app shows `TODO: ... action — implemented in a later plan` log lines under the `com.bks-lab.juicescreen` subsystem
- Press the hotkeys (e.g. ⌘⇧4): same TODO log lines appear
- Quit via "Quit JuiceScreen"

If any of these fail, fix before commit. Common gotchas:
- LSUIElement not honored: check Info.plist for `LSUIElement = true`
- Hotkeys silent: macOS screenshot shortcut may be intercepting; either go through the conflict wizard or test with the alternative defaults

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift JuiceScreen/App/JuiceScreenApp.swift
git commit -m "feat(app): AppDelegate wires permissions, menu bar, hotkeys, first-run"
```

---

## Task 21: GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Implement `ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: macos-15
    timeout-minutes: 25

    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Build
        run: |
          xcodebuild \
            -project JuiceScreen.xcodeproj \
            -scheme JuiceScreen \
            -destination 'platform=macOS' \
            -configuration Debug \
            build | xcbeautify
        shell: bash

      - name: Test (unit + UI)
        run: |
          xcodebuild \
            -project JuiceScreen.xcodeproj \
            -scheme JuiceScreen \
            -destination 'platform=macOS' \
            -configuration Debug \
            test | xcbeautify
        shell: bash

      - name: Print version
        run: cat VERSION
```

(`xcbeautify` is preinstalled on `macos-15` GitHub runners; if it ever isn't, `brew install xcbeautify` it in a step before Build.)

- [ ] **Step 2: Push and verify CI runs green**

This step requires the repo to exist on GitHub. Until then, validate locally:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test
```

Expected: both commands succeed.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow (xcodegen + xcodebuild build/test on macos-15)"
```

---

## Task 22: README — install and dev sections (full)

**Files:**
- Modify: `README.md` (replace contents from Task 1)

- [ ] **Step 1: Replace `README.md` with the production-quality version**

```markdown
# JuiceScreen

Open-source, 100% local screen capture for macOS. Region / window / full-screen / scroll capture, video recording with audio, annotation, OCR-indexed library search.

**Status:** v0.1.0 — Foundation milestone. Menu-bar shell, permissions flow, and Settings stub work. Capture functionality lands in subsequent milestones.

## Why

CleanShot X is excellent but proprietary. JuiceScreen aims to be the lean open-source alternative:

- **Open source** (MIT licensed)
- **100% local** — zero network calls except optional Sparkle update checks. No telemetry. No analytics. No crash reporter
- **Lean feature set** — only what's actually used
- **Modern minimal UI**

See `docs/superpowers/specs/2026-05-04-juicescreen-design.md` for the full design.

## Installing

JuiceScreen is currently pre-alpha. Once v1.0.0 ships:

1. Download `JuiceScreen-X.Y.Z.dmg` from [Releases](https://github.com/mkupermann/JuiceScreen/releases)
2. Open the DMG and drag `JuiceScreen.app` to `/Applications`
3. **First launch will be blocked** because the app is not code-signed. Right-click `JuiceScreen.app` in `/Applications` → **Open** → confirm. On macOS 15+, also visit **System Settings → Privacy & Security → "Open Anyway"** if needed
4. Grant Screen Recording permission when prompted
5. The first-run wizard will explain the rest

## Developing

**Requirements:**

- macOS 14 Sonoma or newer
- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

**Setup:**

```bash
git clone https://github.com/mkupermann/JuiceScreen.git
cd JuiceScreen
xcodegen generate
open JuiceScreen.xcodeproj
```

The `.xcodeproj` is regenerated from `project.yml` and not committed. Edit `project.yml` (not the `.xcodeproj`) to add files or change build settings.

**Run tests:**

```bash
xcodebuild test -scheme JuiceScreen -destination 'platform=macOS'
```

**Run from CLI:**

```bash
xcodebuild -scheme JuiceScreen -destination 'platform=macOS' build
open "$(xcodebuild -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
```

## Privacy

JuiceScreen makes **two** kinds of network calls and no others:

1. Sparkle fetching the appcast XML from `https://mkupermann.github.io/JuiceScreen/appcast.xml` (default: on launch + every 24h; user can fully disable in Settings)
2. Sparkle downloading a new DMG from `github.com` when the user clicks **Install Update**

That is the entire network surface. No telemetry. No analytics. No crash reporter. No third-party SDKs. Verifiable with [Little Snitch](https://obdev.at/products/littlesnitch/) or [Lulu](https://objective-see.org/products/lulu.html).

## Known limitations

(These will be expanded as the app gains features.)

- App is unsigned — first launch requires right-click → Open
- No support for macOS < 14
- No iCloud sync of library (by design — local-only)
- macOS 15+ may re-prompt for Screen Recording permission weekly (Apple's behavior, not ours)

Scroll capture, vector PDF export, and additional limitations will be documented as those features ship.

## License

MIT. See `LICENSE`.

## Roadmap

Implementation proceeds via 10 plans, each shipping a working artifact. Foundation (this milestone) is Plan 1 of 10. Subsequent plans add image capture (Plan 2), annotation (Plan 3), library + storage (Plan 4), OCR + search (Plan 5), video recording (Plan 6), trim (Plan 7), scroll capture (Plan 8), settings + Sparkle (Plan 9), build pipeline + ship (Plan 10).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: full README with install, dev setup, privacy guarantee, roadmap"
```

---

## Task 23: UI smoke test — app launches and menu bar icon present

**Files:**
- Modify: `JuiceScreenUITests/PlaceholderUITests.swift` → rename + replace
- Create: `JuiceScreenUITests/LaunchSmokeTests.swift` (replaces placeholder)

- [ ] **Step 1: Delete the placeholder UI test**

```bash
rm JuiceScreenUITests/PlaceholderUITests.swift
```

- [ ] **Step 2: Implement `LaunchSmokeTests.swift`**

```swift
import XCTest

/// Verifies the app launches successfully and exits cleanly.
/// More extensive UI tests come in later plans once visible UI exists.
final class LaunchSmokeTests: XCTestCase {

    func test_launchAndQuit() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JUICESCREEN_UI_TEST_MODE"] = "1"
        app.launch()
        // App is LSUIElement — has no main window. Just confirm it didn't crash.
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
    }
}
```

- [ ] **Step 3: Add UI-test-mode handling in AppDelegate**

The first-run window would block UI tests on a clean test runner. Add a guard.

Modify `JuiceScreen/App/AppDelegate.swift` — replace the `applicationDidFinishLaunching` method's first-run block with this version:

```swift
        // First-run wizard (no-op if already complete OR if running in UI test mode)
        if ProcessInfo.processInfo.environment["JUICESCREEN_UI_TEST_MODE"] == nil {
            let coordinator = FirstRunCoordinator(permissions: permissions, preferences: preferences)
            firstRun = coordinator
            coordinator.start()
            FirstRunWindow.showIfNeeded(coordinator: coordinator)
        }
```

- [ ] **Step 4: Run the UI test**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test -only-testing:JuiceScreenUITests/LaunchSmokeTests/test_launchAndQuit
```

Expected: passes. Smoke confirms the app launches and the menu-bar item is created without crashing.

- [ ] **Step 5: Commit**

```bash
git add JuiceScreen/App/AppDelegate.swift JuiceScreenUITests
git commit -m "test(ui): launch smoke test + UI_TEST_MODE guard to skip first-run wizard"
```

---

## Task 24: Run the full test matrix locally and tag v0.1.0

**Files:**
- (no source changes)

- [ ] **Step 1: Clean build from scratch**

```bash
rm -rf JuiceScreen.xcodeproj DerivedData build
xcodegen generate
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' clean build
```

Expected: `** CLEAN SUCCEEDED **` followed by `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Run all tests**

```bash
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **` with all suites green:
- `HotkeyTests` — 4 cases
- `KeyCodeFormatterTests` — 5 cases
- `FakePermissionsServiceTests` — 5 cases
- `PreferencesStoreTests` — 4 cases
- `FirstRunCoordinatorTests` — 7 cases
- `LaunchSmokeTests` — 1 case

Total: 26 tests passing.

- [ ] **Step 3: Manual smoke test on a clean profile**

```bash
# Wipe any prior preferences so we hit the first-run flow fresh
defaults delete com.bks-lab.juicescreen 2>/dev/null || true

# Build & launch
xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' build
open "$(xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -showBuildSettings | awk -F' = ' '/ TARGET_BUILD_DIR /{print $2}' | head -1)/JuiceScreen.app"
```

Expected first-launch behavior:

1. App launches. No Dock icon (LSUIElement honored). Menu bar shows the camera.viewfinder symbol
2. If Screen Recording permission is not granted, the first-run wizard appears
3. Granting → hotkey conflict wizard appears
4. Choosing "Use alternative defaults" → welcome panel appears
5. Welcome → "Got it" → wizard closes, no further panels
6. Click menu bar icon → menu shows all 8 entries with shortcut labels next to them
7. Preferences… → Settings window opens with 6 tabs; About shows "Version 0.1.0 (1)" and the GitHub/MIT links
8. While Settings is open, JuiceScreen has a Dock icon and is ⌘-Tabbable; closing Settings hides the Dock icon (but the app keeps running and the menu bar icon remains)
9. Press a configured hotkey (e.g. ⌘⌃4 if you chose alternatives) — Console.app shows `TODO: captureRegion action — implemented in a later plan` under subsystem `com.bks-lab.juicescreen`
10. Quit JuiceScreen → no zombie process

If anything in this list fails, do **not** tag — fix the issue first.

- [ ] **Step 4: Tag v0.1.0**

```bash
git tag -a v0.1.0 -m "Foundation milestone: menu bar, permissions, hotkeys, settings stub, CI"
git tag -l v0.1.0
```

(Do NOT push the tag yet — that happens when the repo is on GitHub. For now, the local tag marks the milestone.)

- [ ] **Step 5: Verify clean working tree**

```bash
git status
```

Expected output: `nothing to commit, working tree clean`.

---

## Task 25: Update the spec doc footer with Foundation status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-04-juicescreen-design.md`

- [ ] **Step 1: Append a new section to the spec doc**

Open `docs/superpowers/specs/2026-05-04-juicescreen-design.md` and append at the very end (after the "Open questions for v1.1+" section):

```markdown

---

## Implementation status (updated as plans complete)

- ✅ **Plan 1: Foundation** (v0.1.0, 2026-05-04) — Xcode project, menu-bar accessory, permissions service, Carbon hotkey wrapper, first-run wizard, Settings stub with 6 tabs, GitHub Actions CI. 26 tests passing
- ⬜ Plan 2: Image capture
- ⬜ Plan 3: Annotation editor
- ⬜ Plan 4: Library + storage
- ⬜ Plan 5: OCR + search
- ⬜ Plan 6: Video recording
- ⬜ Plan 7: Trim + post-record
- ⬜ Plan 8: Scroll capture
- ⬜ Plan 9: PDF export + Sparkle + Settings completion
- ⬜ Plan 10: Build pipeline + ship v1.0.0
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-04-juicescreen-design.md
git commit -m "docs(spec): mark Plan 1 (Foundation) complete in implementation status"
```

---

## Plan completion checklist

After Task 25, verify:

- [ ] `git log --oneline | wc -l` shows ~26 commits since the spec commit (one per task plus the design-spec root)
- [ ] `git tag -l v0.1.0` shows the tag locally
- [ ] `xcodebuild -project JuiceScreen.xcodeproj -scheme JuiceScreen -destination 'platform=macOS' test` is green
- [ ] Manual smoke test (Task 24, Step 3) passes end-to-end
- [ ] No leftover `// TODO` comments outside the explicitly logged "TODO: ... action" placeholders that Plan 2 will replace

When everything checks out: ship v0.1.0 alpha (when ready, push to GitHub and create a Release with the manual-smoke-test artifact). Then start Plan 2 (Image Capture).
