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
