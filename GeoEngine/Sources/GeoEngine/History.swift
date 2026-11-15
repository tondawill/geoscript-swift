/// Undo and redo over snapshots of a value.
public struct History<State> {
    public private(set) var past: [State] = []
    public private(set) var future: [State] = []
    public let limit: Int

    public init(limit: Int = 200) {
        self.limit = limit
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Records `state` as an undo step. A new change makes the redo list meaningless, so it is cleared.
    public mutating func record(_ state: State) {
        past.append(state)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    /// Returns the state to go back to, remembering `current` for redo.
    public mutating func undo(from current: State) -> State? {
        guard let previous = past.popLast() else { return nil }
        future.insert(current, at: 0)
        return previous
    }

    /// Returns the state to go forward to, remembering `current` for undo.
    public mutating func redo(from current: State) -> State? {
        guard !future.isEmpty else { return nil }
        past.append(current)
        return future.removeFirst()
    }
}
