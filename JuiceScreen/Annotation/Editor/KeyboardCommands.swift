import AppKit
import SwiftUI

struct KeyboardCommandsModifier: ViewModifier {
    @Bindable var state: EditorState

    func body(content: Content) -> some View {
        content
            .onKeyPress(.init("z"), action: {
                if NSEvent.modifierFlags.contains(.shift) { state.redo() } else { state.undo() }
                return .handled
            })
            .onKeyPress(.init("d"), action: { state.duplicateSelected(); return .handled })
            .onKeyPress(.delete, action: { state.deleteSelected(); return .handled })
    }
}

extension View {
    func editorKeyboardCommands(state: EditorState) -> some View {
        modifier(KeyboardCommandsModifier(state: state))
    }
}
