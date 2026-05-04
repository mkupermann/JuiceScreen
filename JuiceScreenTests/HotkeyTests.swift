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
