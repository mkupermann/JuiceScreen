import AppKit
import SwiftUI

struct KeyboardCommandsModifier: ViewModifier {
    @Bindable var state: EditorState

    func body(content: Content) -> some View {
        content
            .onKeyPress(.delete, action: handleDelete)
            .onKeyPress(action: handleKey)
    }

    /// True if keyboard focus is on a text input. We never intercept keys in that
    /// case — typing in a TextField (text body, layer-text edit, etc.) must not be
    /// consumed by tool shortcuts or undo.
    private var textInputHasFocus: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSText || responder is NSTextView || responder is NSTextField
    }

    private func handleDelete() -> KeyPress.Result {
        if textInputHasFocus { return .ignored }
        state.deleteSelected()
        return .handled
    }

    /// One handler for everything else. Lowercases the keystroke so ⇧Z still matches "z".
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if textInputHasFocus { return .ignored }
        let mods = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = press.characters.lowercased()

        // Undo / redo / duplicate use ⌘.
        if mods.contains(.command) {
            switch key {
            case "z":
                if mods.contains(.shift) { state.redo() } else { state.undo() }
                return .handled
            case "d":
                state.duplicateSelected()
                return .handled
            default:
                return .ignored
            }
        }

        // Tool shortcuts only fire with no modifier (shift allowed for ⇧A → double arrow).
        if !mods.subtracting([.shift]).isEmpty { return .ignored }

        switch key {
        case "v": state.currentTool = .select; return .handled
        case "a":
            state.currentTool = mods.contains(.shift) ? .doubleArrow : .arrow
            state.selectedLayerID = nil
            return .handled
        case "l": state.currentTool = .line;        state.selectedLayerID = nil; return .handled
        case "r": state.currentTool = .rectangle;   state.selectedLayerID = nil; return .handled
        case "e": state.currentTool = .ellipse;     state.selectedLayerID = nil; return .handled
        case "p": state.currentTool = .pen;         state.selectedLayerID = nil; return .handled
        case "h": state.currentTool = .highlighter; state.selectedLayerID = nil; return .handled
        case "t": state.currentTool = .text;        state.selectedLayerID = nil; return .handled
        case "b": state.currentTool = .blur;        state.selectedLayerID = nil; return .handled
        case "c": state.currentTool = .crop;        state.selectedLayerID = nil; return .handled
        default:  return .ignored
        }
    }
}

extension View {
    func editorKeyboardCommands(state: EditorState) -> some View {
        modifier(KeyboardCommandsModifier(state: state))
    }
}
