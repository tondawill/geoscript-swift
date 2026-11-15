import Testing
@testable import GeoEngine

@Suite struct UndoHistory {
    @Test func undoAndRedoWalkTheSteps() {
        var history = History<Int>()
        #expect(!history.canUndo && !history.canRedo)
        history.record(1)
        history.record(2)
        var current = 3

        current = history.undo(from: current) ?? -1
        #expect(current == 2)
        current = history.undo(from: current) ?? -1
        #expect(current == 1)
        #expect(!history.canUndo)
        #expect(history.undo(from: current) == nil)

        current = history.redo(from: current) ?? -1
        #expect(current == 2)
        current = history.redo(from: current) ?? -1
        #expect(current == 3)
        #expect(!history.canRedo)
        #expect(history.redo(from: current) == nil)
    }

    @Test func newChangeClearsRedo() {
        var history = History<Int>()
        history.record(1)
        _ = history.undo(from: 2)
        #expect(history.canRedo)
        history.record(1)
        #expect(!history.canRedo)
    }

    @Test func keepsOnlyTheLimit() {
        var history = History<Int>(limit: 200)
        for i in 0..<250 { history.record(i) }
        #expect(history.past.count == 200)
        #expect(history.past.first == 50)
    }
}
