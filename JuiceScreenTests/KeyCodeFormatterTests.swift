import Testing
@testable import JuiceScreen

@Suite("KeyCodeFormatter")
struct KeyCodeFormatterTests {

    @Test("Renders ⌘⇧4")
    func cmdShift4() {
        // virtual keycode 21 = "4" on US layout
        let h = Hotkey(keyCode: 21, modifiers: [.command, .shift])
        #expect(KeyCodeFormatter.string(for: h) == "⇧⌘4")
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
