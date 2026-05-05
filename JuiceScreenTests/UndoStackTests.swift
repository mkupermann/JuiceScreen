import Testing
@testable import JuiceScreen

@Suite("UndoStack")
struct UndoStackTests {

    @Test("Initial state: cannot undo or redo")
    func initial() {
        let stack = UndoStack<Int>(initial: 0)
        #expect(stack.current == 0)
        #expect(stack.canUndo == false)
        #expect(stack.canRedo == false)
    }

    @Test("Push moves current forward and enables undo")
    func pushEnablesUndo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        #expect(stack.current == 1)
        #expect(stack.canUndo == true)
        #expect(stack.canRedo == false)
    }

    @Test("Undo restores previous state and enables redo")
    func undoEnablesRedo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        stack.undo()
        #expect(stack.current == 0)
        #expect(stack.canUndo == false)
        #expect(stack.canRedo == true)
    }

    @Test("Redo restores re-done state")
    func redo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        stack.undo()
        stack.redo()
        #expect(stack.current == 1)
        #expect(stack.canUndo == true)
        #expect(stack.canRedo == false)
    }

    @Test("Push after undo discards forward history")
    func pushDiscardsRedo() {
        var stack = UndoStack<Int>(initial: 0)
        stack.push(1)
        stack.push(2)
        stack.undo()
        #expect(stack.current == 1)
        #expect(stack.canRedo == true)

        stack.push(99)
        #expect(stack.current == 99)
        #expect(stack.canRedo == false)
    }

    @Test("Many pushes work without errors")
    func manyPushes() {
        var stack = UndoStack<Int>(initial: 0)
        for i in 1...100 { stack.push(i) }
        #expect(stack.current == 100)
        for _ in 1...100 { stack.undo() }
        #expect(stack.current == 0)
        #expect(stack.canUndo == false)
    }
}
