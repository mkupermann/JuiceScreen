import SwiftUI

struct ToolPalette: View {

    @Bindable var state: EditorState

    var body: some View {
        VStack(spacing: 4) {
            ForEach(ToolType.allCases, id: \.self) { tool in
                ToolPaletteButton(tool: tool, isSelected: state.currentTool == tool) {
                    state.currentTool = tool
                    if tool != .select {
                        state.selectedLayerID = nil
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 48)
        .background(.regularMaterial)
    }
}
