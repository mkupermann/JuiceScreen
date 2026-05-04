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
