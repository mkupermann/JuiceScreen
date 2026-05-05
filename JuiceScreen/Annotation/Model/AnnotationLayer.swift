import Foundation

public enum AnnotationLayer: Equatable, Hashable, Sendable, Identifiable {

    case arrow(ArrowProps, id: UUID = UUID())
    case line(LineProps, id: UUID = UUID())
    case rectangle(ShapeProps, id: UUID = UUID())
    case ellipse(ShapeProps, id: UUID = UUID())
    case freehand(FreehandProps, id: UUID = UUID())
    case text(TextProps, id: UUID = UUID())
    case blur(BlurProps, id: UUID = UUID())

    public var id: UUID {
        switch self {
        case .arrow(_, let id),
             .line(_, let id),
             .rectangle(_, let id),
             .ellipse(_, let id),
             .freehand(_, let id),
             .text(_, let id),
             .blur(_, let id):
            return id
        }
    }

    public var boundingRect: CGRect {
        switch self {
        case .arrow(let p, _):     return p.boundingRect
        case .line(let p, _):      return p.boundingRect
        case .rectangle(let p, _): return p.boundingRect
        case .ellipse(let p, _):   return p.boundingRect
        case .freehand(let p, _):  return p.boundingRect
        case .text(let p, _):      return p.boundingRect()
        case .blur(let p, _):      return p.boundingRect
        }
    }

    public var toolType: ToolType {
        switch self {
        case .arrow(let p, _):     return p.doubleHeaded ? .doubleArrow : .arrow
        case .line:                return .line
        case .rectangle:           return .rectangle
        case .ellipse:             return .ellipse
        case .freehand(let p, _):  return p.isHighlighter ? .highlighter : .pen
        case .text:                return .text
        case .blur:                return .blur
        }
    }
}
