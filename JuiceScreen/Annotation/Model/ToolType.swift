/// The 11 annotation tools available in the JuiceScreen editor.
public enum ToolType: String, CaseIterable, Sendable, Hashable {
    case select
    case arrow
    case doubleArrow
    case line
    case rectangle
    case ellipse
    case pen
    case highlighter
    case text
    case blur
    case crop

    /// Human-readable label shown in the tool palette.
    public var displayName: String {
        switch self {
        case .select:      return "Select"
        case .arrow:       return "Arrow"
        case .doubleArrow: return "Double Arrow"
        case .line:        return "Line"
        case .rectangle:   return "Rectangle"
        case .ellipse:     return "Ellipse"
        case .pen:         return "Pen"
        case .highlighter: return "Highlighter"
        case .text:        return "Text"
        case .blur:        return "Blur"
        case .crop:        return "Crop"
        }
    }

    /// SF Symbol name used for the tool button icon.
    public var sfSymbol: String {
        switch self {
        case .select:      return "cursorarrow"
        case .arrow:       return "arrow.up.right"
        case .doubleArrow: return "arrow.left.and.right"
        case .line:        return "line.diagonal"
        case .rectangle:   return "rectangle"
        case .ellipse:     return "oval"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text:        return "textformat"
        case .blur:        return "drop"
        case .crop:        return "crop"
        }
    }
}
