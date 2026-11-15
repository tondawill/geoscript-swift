/// User-defined ("typed") vs. eyeballed dimensions.
///
/// A typed dimension is a lock: segment AB is locked when one endpoint is a distance point whose parent
/// is the other endpoint; a circle is locked when its numeric radius was typed, or, for k(S, |SB|), when
/// B is a distance point locked to S. Locked dimensions are shown in the drawing and cannot change by dragging.

public enum DimensionError: Error, Equatable, Sendable {
    case cannotEditSegment, cannotEditCircle, exerciseLocked
}

extension Construction {
    /// The point that locks straight object `s`, if any: a distance point or length-locked direction point.
    public func segmentLock(_ s: GeoObject) -> GeoObject? {
        let ends = parentsOf(s)
        guard s.isLinear, ends.count == 2 else { return nil }
        func locks(_ id: Id, to parent: Id) -> GeoObject? {
            guard let p = point(id) else { return nil }
            switch p {
            case .distancePoint(let d) where d.parent == parent: return p
            case .directionPoint(let d) where d.lengthLocked && d.parent == parent: return p
            default: return nil
            }
        }
        return locks(ends[1], to: ends[0]) ?? locks(ends[0], to: ends[1])
    }

    private func throughLock(_ k: Circle) -> DistancePoint? {
        guard let through = k.through, case .distancePoint(let b)? = point(through), b.parent == k.center else { return nil }
        return b
    }

    public func isLocked(_ o: GeoObject) -> Bool {
        if case .circle(let k) = o {
            return k.through != nil ? throughLock(k) != nil : k.locked
        }
        return segmentLock(o) != nil
    }

    public func segmentLength(_ s: GeoObject, _ resolved: Resolved) -> Double? {
        let ends = parentsOf(s)
        guard s.isLinear, let a = resolved[ends[0]], let b = resolved[ends[1]] else { return nil }
        return dist(a, b)
    }

    public func circleRadius(_ k: GeoObject, _ resolved: Resolved) -> Double? {
        if case let .circle(_, radius)? = curveGeom(k, resolved) { return radius }
        return nil
    }

    private mutating func moveFree(_ id: Id, to p: Vec) {
        guard let i = objects.firstIndex(where: { $0.id == id }), case .freePoint(var f) = objects[i] else { return }
        f.x = p.x
        f.y = p.y
        objects[i] = .freePoint(f)
    }

    /// Turns a free point into a distance point locked to `parent`.
    private mutating func lockPoint(_ p: GeoObject, parent: Id, distance: Double, angle: Double) -> Bool {
        guard case .freePoint(let f) = p else { return false }
        return replaceObject(.distancePoint(DistancePoint(id: f.id, name: f.name, parent: parent, distance: distance, angle: angle)))
    }

    private func isFree(_ o: GeoObject) -> Bool {
        if case .freePoint = o { return true }
        return false
    }

    /// Runs a change on a copy; a change that fails or alters the exercise leaves this construction as it was.
    private mutating func guarded(_ change: (inout Construction) -> DimensionError?) -> DimensionError? {
        var next = self
        if let error = change(&next) { return error }
        if touchesExercise(after: next) { return .exerciseLocked }
        self = next
        return nil
    }

    /// Sets |AB| = d and locks it. Both ends move symmetrically around the midpoint; an end that cannot
    /// move stays and the other end moves. Returns why it failed, or nil on success.
    @discardableResult
    public mutating func setSegmentLength(_ segId: Id, _ d: Double) -> DimensionError? {
        guarded { $0.applySegmentLength(segId, d) }
    }

    private mutating func applySegmentLength(_ segId: Id, _ d: Double) -> DimensionError? {
        guard let s = object(segId), s.isLinear, d > 0 else { return .cannotEditSegment }
        let ends = parentsOf(s)
        let positions = resolve()
        guard let pa = positions[ends[0]], let pb = positions[ends[1]] else { return .cannotEditSegment }
        let angle = dist(pa, pb) == 0 ? 0 : angleOf(pa, pb)
        let mid = Vec(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)

        // Already locked: change the distance, moving the parent if it is free.
        if let lock = segmentLock(s) {
            let parentId = parentsOf(lock)[0]
            let dir = lock.id == ends[1] ? angle : angle + .pi // parent → child
            // Moving the start of "C ∈ ↦AB" would turn it, so only the length changes there.
            var aimed = false
            if case .distancePoint(let p) = lock, p.toward != nil { aimed = true }
            if !aimed, let parent = point(parentId), isFree(parent) {
                moveFree(parentId, to: polar(mid, d / 2, dir + .pi))
            }
            guard let i = objects.firstIndex(where: { $0.id == lock.id }) else { return .cannotEditSegment }
            switch lock {
            case .distancePoint(var p): p.distance = d; objects[i] = .distancePoint(p)
            case .directionPoint(var p): p.distance = d; objects[i] = .directionPoint(p)
            default: return .cannotEditSegment
            }
            return nil
        }

        // Not locked yet: make one endpoint depend on the other.
        guard let a = point(ends[0]), let b = point(ends[1]) else { return .cannotEditSegment }
        // A direction point (⊥ / ∥ / angle) keeps its direction and just gets a fixed length.
        for (child, parent) in [(b, a), (a, b)] {
            if case .directionPoint(var p) = child, p.parent == parent.id, p.onCurve == nil {
                p.distance = d
                p.lengthLocked = true
                if replaceObject(.directionPoint(p)) { return nil }
            }
        }
        for (child, parent, dir) in [(b, a, angle), (a, b, angle + .pi)] where isFree(child) {
            var next = self
            if isFree(parent) { next.moveFree(parent.id, to: polar(mid, d / 2, dir + .pi)) }
            if next.lockPoint(child, parent: parent.id, distance: d, angle: dir) {
                self = next
                return nil
            }
        }
        return .cannotEditSegment
    }

    /// Removes the lock on |AB|: the locked endpoint keeps its position but its length is free again.
    public mutating func unlockSegment(_ segId: Id) {
        if let s = object(segId), let lock = segmentLock(s) { unlockPoint(lock) }
    }

    private mutating func unlockPoint(_ p: GeoObject) {
        switch p {
        case .directionPoint(var d):
            d.lengthLocked = false
            replaceObject(.directionPoint(d))
        case .distancePoint(let d):
            guard let pos = resolve()[d.id] else { return }
            replaceObject(.freePoint(FreePoint(id: d.id, name: d.name, x: pos.x, y: pos.y)))
        default:
            break
        }
    }

    /// Sets r and locks it. For k(S, |SB|) the point B slides along SB to distance r and is locked there.
    @discardableResult
    public mutating func setCircleRadius(_ circleId: Id, _ r: Double) -> DimensionError? {
        guarded { $0.applyCircleRadius(circleId, r) }
    }

    private mutating func applyCircleRadius(_ circleId: Id, _ r: Double) -> DimensionError? {
        // k(S, r = |AD|) takes its radius from AD; change |AD| instead.
        guard case .circle(var k)? = object(circleId), r > 0, k.span == nil else { return .cannotEditCircle }
        guard let through = k.through else {
            k.radius = r
            k.locked = true
            replaceObject(.circle(k))
            return nil
        }
        if var lock = throughLock(k) {
            lock.distance = r
            replaceObject(.distancePoint(lock))
            return nil
        }
        let positions = resolve()
        guard let s = positions[k.center], let b = point(through), let pb = positions[through] else { return .cannotEditCircle }
        return lockPoint(b, parent: k.center, distance: r, angle: dist(s, pb) == 0 ? 0 : angleOf(s, pb)) ? nil : .cannotEditCircle
    }

    public mutating func unlockCircle(_ circleId: Id) {
        guard case .circle(var k)? = object(circleId), k.span == nil else { return }
        if k.through == nil {
            k.locked = false
            replaceObject(.circle(k))
        } else if let lock = throughLock(k) {
            unlockPoint(.distancePoint(lock))
        }
    }

    /// Dragging a point with the mouse. Like `movePoint`, except that the fixed end of a typed segment
    /// rotates the segment around its other end. A point that anchors several distance points just moves,
    /// because rotating around one of them would break the others.
    public mutating func dragPoint(_ id: Id, to target: Vec) {
        guard case .freePoint(var f)? = object(id) else {
            movePoint(id, to: target)
            return
        }
        let children = objects.compactMap { o -> DistancePoint? in
            if case .distancePoint(let d) = o, d.parent == id { return d }
            return nil
        }
        guard children.count == 1, var child = children.first, child.toward == nil, let childPos = resolve()[child.id],
              objects.contains(where: { o in
                  guard case .segment(let s) = o else { return false }
                  return (s.a == id && s.b == child.id) || (s.b == id && s.a == child.id)
              }), dist(childPos, target) != 0 else {
            movePoint(id, to: target)
            return
        }
        let pos = polar(childPos, child.distance, angleOf(childPos, target))
        f.x = pos.x
        f.y = pos.y
        child.angle = angleOf(pos, childPos)
        replaceObject(.freePoint(f))
        replaceObject(.distancePoint(child))
    }

    /// Can this segment be moved as a whole? Each end must be free or depend only on the other end.
    public func canTranslateSegment(_ id: Id) -> Bool {
        guard case .segment(let s)? = object(id), let a = point(s.a), let b = point(s.b) else { return false }
        func movable(_ end: GeoObject, other: Id) -> Bool {
            switch end {
            case .freePoint: true
            case .distancePoint(let d): d.parent == other && d.toward == nil
            case .directionPoint(let d): d.parent == other && d.onCurve == nil
            default: false
            }
        }
        return movable(a, other: s.b) && movable(b, other: s.a) && (isFree(a) || isFree(b))
    }

    /// Moves a whole segment. Ends that depend on the other end follow by themselves.
    public mutating func translateSegment(_ id: Id, dx: Double, dy: Double) {
        guard canTranslateSegment(id), case .segment(let s)? = object(id) else { return }
        for end in [s.a, s.b] {
            if case .freePoint(let f)? = object(end) { moveFree(end, to: Vec(x: f.x + dx, y: f.y + dy)) }
        }
    }

    /// Why this dimension can't be changed at all, or nil when it can.
    public func dimensionError(_ o: GeoObject) -> DimensionError? {
        var probe = self
        if case .circle = o { return probe.setCircleRadius(o.id, 1) }
        return probe.setSegmentLength(o.id, 1)
    }

    public func canEditDimension(_ o: GeoObject) -> Bool {
        dimensionError(o) == nil
    }

    /// Dragging the outline of an eyeballed circle resizes it; locked or attached circles don't change.
    public mutating func resizeCircle(_ id: Id, radius: Double) {
        guard radius > 0, case .circle(var k)? = object(id), k.through == nil, !k.locked else { return }
        k.radius = radius
        replaceObject(.circle(k))
    }
}
