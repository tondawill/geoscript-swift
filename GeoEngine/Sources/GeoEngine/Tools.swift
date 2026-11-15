/// Which straight object the tool draws: segment AB, line ↔AB or ray ↦AB.
public enum LineShape: Sendable {
    case segment, line, ray
}

/// How a straight object ends: at a snap, with a typed length towards the mouse, or in a direction
/// tied to another line (⊥ / ∥ / angle), `locked` when the length was typed.
public enum SegmentEnd: Sendable {
    case snap(Snap)
    case length(Double, toward: Vec)
    /// A typed length along the ray from the start through an existing point, which it keeps following.
    case lengthThrough(Double, point: Id)
    case direction(ref: Id, offset: Double, distance: Double, locked: Bool, onCurve: OnCurve? = nil)
}

extension Construction {
    /// The second point of a ray is called X (X₁, X₂ … when taken).
    private func rayPointName() -> String {
        let used = usedNames
        if !used.contains("X") { return "X" }
        var i = 1
        while used.contains("X" + toSubscript(i)) { i += 1 }
        return "X" + toSubscript(i)
    }

    /// Commits a segment / line / ray in one step, creating any new endpoints.
    /// Returns false, changing nothing, when the object would be degenerate.
    @discardableResult
    public mutating func finishSegment(start: Snap, end: SegmentEnd, shape: LineShape = .segment) -> Bool {
        switch end {
        case .length(let length, _):
            guard length > 0 else { return false }
        case let .lengthThrough(length, through):
            guard length > 0, let target = resolve()[through], dist(start.pos, target) > 0 else { return false }
            if case .point(let startId, _) = start, startId == through { return false }
        case .direction(_, _, let distance, _, _):
            guard distance > 0 else { return false }
        case .snap(let snap):
            if case .point(let endId, _) = snap, case .point(let startId, _) = start, endId == startId { return false }
            if dist(start.pos, snap.pos) == 0 { return false }
        }

        let firstNewId = nextId
        func isNew(_ id: Id) -> Bool { (Int(id.dropFirst()) ?? 0) >= firstNewId }

        let a = materializeSnap(start)
        let b: Id
        switch end {
        case let .length(length, toward):
            let angle = dist(start.pos, toward) == 0 ? 0 : angleOf(start.pos, toward)
            b = addDistancePoint(parent: a, distance: length, angle: angle)
        case let .lengthThrough(length, through):
            let angle = resolve()[through].map { angleOf(start.pos, $0) } ?? 0
            b = addDistancePoint(parent: a, distance: length, angle: angle, toward: through)
        case let .direction(ref, offset, distance, locked, onCurve):
            b = addDirectionPoint(parent: a, ref: ref, offset: offset, distance: distance, lengthLocked: locked,
                                  onCurve: onCurve, name: shape == .ray ? rayPointName() : nil)
        case .snap(let snap):
            b = materializeSnap(snap)
            if shape == .ray, isNew(b), case .free = snap { renameObject(b, rayPointName()) }
        }

        switch shape {
        case .segment:
            addSegment(a, b)
        case .line:
            // A line is defined by two helper points that are never shown.
            for id in [a, b] where isNew(id) { hidePoint(id) }
            addLine(a, b)
        case .ray:
            addRay(a, b)
        }
        return true
    }

    /// Commits circle k(S, r). The centre must be an existing point and r must be positive.
    /// `locked`: r was typed by the user.
    @discardableResult
    public mutating func finishCircle(center: Id, radius: Double, locked: Bool) -> Bool {
        guard point(center) != nil, radius > 0 else { return false }
        addCircle(center: center, radius: radius, locked: locked)
        return true
    }

    /// Commits circle k(S, |SB|) attached to the existing point B.
    @discardableResult
    public mutating func finishCircleThrough(center: Id, through: Id) -> Bool {
        guard point(center) != nil, point(through) != nil, center != through else { return false }
        addCircle(center: center, through: through)
        return true
    }
}
