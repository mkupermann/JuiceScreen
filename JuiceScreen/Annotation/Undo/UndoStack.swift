/// Generic snapshot-based undo stack. Each `push` records the new value so a later
/// `undo` can restore the previous one. Pushing after an `undo` discards the redo tail.
///
/// Used by the editor with `T = AnnotationDocument`.
public struct UndoStack<T> {

    private var past: [T] = []
    private var future: [T] = []
    public private(set) var current: T

    public init(initial: T) {
        self.current = initial
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public mutating func push(_ next: T) {
        past.append(current)
        current = next
        future.removeAll()
    }

    public mutating func undo() {
        guard let prev = past.popLast() else { return }
        future.append(current)
        current = prev
    }

    public mutating func redo() {
        guard let next = future.popLast() else { return }
        past.append(current)
        current = next
    }
}
