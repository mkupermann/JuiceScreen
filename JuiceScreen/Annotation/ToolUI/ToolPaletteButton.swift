import SwiftUI

struct ToolPaletteButton: View {

    let tool: ToolType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: tool.sfSymbol)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }
}
