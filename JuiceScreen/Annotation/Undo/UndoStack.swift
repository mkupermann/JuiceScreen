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

    /// Replace `current` without modifying history. For drag sessions: the gesture
    /// keeps mutating the document during onChanged, then commits one undo entry
    /// via `commitChange(from:)` at onEnded.
    public mutating func setCurrent(_ next: T) {
        current = next
    }

    /// Push `original` onto `past` so the next `undo` restores the pre-drag state,
    /// and clear the redo tail. Pair with `setCurrent` calls from a drag session.
    public mutating func commitChange(from original: T) {
        past.append(original)
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
