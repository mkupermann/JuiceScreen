import SwiftUI

/// Single horizontal toolbar at the top of the editor window.
/// Two rows: tool selector (left) + Copy/Save actions (right) on top, contextual controls below.
struct EditorToolbar: View {

    @Bindable var state: EditorState
    let actions: QuickActions

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                toolSelector
                Spacer(minLength: 16)
                actionButtons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            TopBar(state: state)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tools

    private var toolSelector: some View {
        HStack(spacing: 6) {
            ToolButton(tool: .select, isSelected: state.currentTool == .select,
                       shortcut: "V", action: { select(.select) })
            groupDivider

            ForEach([ToolType.arrow, .doubleArrow, .line, .rectangle, .ellipse,
                     .pen, .highlighter, .text, .blur], id: \.self) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: state.currentTool == tool,
                    shortcut: shortcutLabel(for: tool),
                    action: { select(tool) }
                )
            }

            groupDivider
            ToolButton(tool: .crop, isSelected: state.currentTool == .crop,
                       shortcut: "C", action: { select(.crop) })
        }
    }

    private var groupDivider: some View {
        Divider()
            .frame(height: 22)
            .padding(.horizontal, 4)
    }

    private func select(_ tool: ToolType) {
        state.currentTool = tool
        if tool != .select {
            state.selectedLayerID = nil
        }
    }

    private func shortcutLabel(for tool: ToolType) -> String {
        switch tool {
        case .select:      return "V"
        case .arrow:       return "A"
        case .doubleArrow: return "⇧A"
        case .line:        return "L"
        case .rectangle:   return "R"
        case .ellipse:     return "E"
        case .pen:         return "P"
        case .highlighter: return "H"
        case .text:        return "T"
        case .blur:        return "B"
        case .crop:        return "C"
        }
    }

    // MARK: - Actions (Copy / Save) — visible inside the editor, not just window chrome

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ActionButton(systemImage: "arrow.uturn.backward", help: "Undo (⌘Z)",
                         disabled: !state.canUndo) {
                state.undo()
            }
            ActionButton(systemImage: "arrow.uturn.forward", help: "Redo (⌘⇧Z)",
                         disabled: !state.canRedo) {
                state.redo()
            }
            Divider().frame(height: 22).padding(.horizontal, 4)
            ActionButton(systemImage: "doc.on.doc", help: "Copy to clipboard (⌘C)") {
                actions.copyToClipboard()
            }
            ActionButton(systemImage: "square.and.arrow.down", help: "Save (⌘S)") {
                actions.save()
            }
        }
    }
}

// MARK: - ToolButton

private struct ToolButton: View {
    let tool: ToolType
    let isSelected: Bool
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .frame(width: 32, height: 22)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Text(shortcut)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(minWidth: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolButtonStyle(isSelected: isSelected))
        .help("\(tool.displayName) (\(shortcut))")
        .accessibilityLabel(tool.displayName)
        .accessibilityHint("Keyboard shortcut: \(shortcut)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Custom button style that preserves the system focus ring for keyboard nav (WCAG 2.4.7),
/// adds a clear active-state background, and shows hover feedback.
private struct ToolButtonStyle: ButtonStyle {
    let isSelected: Bool
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background(pressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(focusRing)
            .focusable()
            .focused($isFocused)
            .onHover { isHovered = $0 }
    }

    private func background(pressed: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(pressed ? 0.42 : 0.30)
        }
        if pressed {
            return Color.primary.opacity(0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.07)
        }
        return .clear
    }

    @ViewBuilder
    private var focusRing: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
        }
    }
}

// MARK: - ActionButton (Copy / Save)

private struct ActionButton: View {
    let systemImage: String
    let help: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
    }
}
