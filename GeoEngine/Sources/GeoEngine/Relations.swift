import Foundation

/// Relations between lines: ⊥, ∥ and a typed angle, stored as `DirectionPoint`s so they hold whenever
/// anything moves. Either q turns around one endpoint (anchor), or around its intersection X with p
/// (pivot), where X is a new hidden point on p and both ends of q become direction points of X.

public enum RelationKind: Sendable {
    case perpendicular, parallel, angle
}

public enum RelationError: Error, Equatable, Sendable {
    case cannotRotate, noIntersection
}

public typealias RelationResult = Result<Construction, RelationError>

public enum RelationTool: Sendable {
    case perpendicular, parallel
}

/// Which line turns. `.less`: whichever moves the drawing less; `.second`: the second line.
/// Either way the other line turns when the chosen one can't.
public enum Turn: Sendable {
    case less, second
}

public enum RotationPivot: Sendable {
    case auto, intersection, anchor
}

private let relationEps = 1e-6

/// One of the four angles two crossing lines make: from the arm of `start` at direction `startDir`,
/// counter-clockwise by `size` (0 < size < π) to an arm of `end`, around the crossing `at`.
public struct AngleSector: Equatable, Sendable {
    public let start: Id
    public let end: Id
    public let at: Vec
    public let startDir: Double
    public let size: Double
}

/// Angle in [0, 2π).
private func mod2Pi(_ a: Double) -> Double {
    let r = a.truncatingRemainder(dividingBy: 2 * .pi)
    return r < 0 ? r + 2 * .pi : r
}

/// Angle modulo π, in [0, π): the angle between two lines (not rays).
public func modPi(_ a: Double) -> Double {
    let r = (a.truncatingRemainder(dividingBy: .pi) + .pi).truncatingRemainder(dividingBy: .pi)
    return r > .pi - relationEps ? 0 : r
}

public func kindOfOffset(_ offset: Double) -> RelationKind {
    let o = modPi(offset)
    if o < relationEps { return .parallel }
    if abs(o - .pi / 2) < relationEps { return .perpendicular }
    return .angle
}

public struct Relation: Sendable {
    /// The rotated line.
    public let q: GeoObject
    /// The reference line.
    public let p: Id
    public let kind: RelationKind
    /// Angle between p and q in [0, π).
    public let angle: Double
    public let points: [DirectionPoint]
    /// The common parent of the direction points (the point q turns around).
    public let pivot: Id
}

/// Direction from `from` along a straight object towards its farther visible end: the side a ⊥ or angle
/// mark is drawn on. Lines and rays just use their own direction.
public func armDirection(_ a: Vec, _ b: Vec, _ ext: Extent, from: Vec) -> Double {
    let own = angleOf(a, b)
    if ext != .segment { return own }
    let far = dist(from, a) > dist(from, b) ? a : b
    return dist(from, far) == 0 ? own : angleOf(from, far)
}

private func directionPoint(_ o: GeoObject?) -> DirectionPoint? {
    if case .directionPoint(let p)? = o { return p }
    return nil
}

extension Construction {
    /// Direction (radians) of a straight object, a → b.
    public func directionOf(_ id: Id, _ resolved: Resolved) -> Double? {
        guard let o = object(id), o.isLinear, case let .straight(a, b, _)? = curveGeom(o, resolved) else { return nil }
        return angleOf(a, b)
    }

    /// The relation that defines line `q`, if any.
    public func relationOf(_ q: GeoObject) -> Relation? {
        guard q.isLinear else { return nil }
        let ends = parentsOf(q)
        let da = directionPoint(object(ends[0]))
        let db = directionPoint(object(ends[1]))
        let points: [DirectionPoint]
        if let db, db.parent == ends[0] {
            points = [db]
        } else if let da, da.parent == ends[1] {
            points = [da]
        } else if let da, let db, da.parent == db.parent, da.ref == db.ref {
            points = [da, db]
        } else {
            return nil
        }
        let offset = modPi(points[0].offset)
        return Relation(q: q, p: points[0].ref, kind: kindOfOffset(offset), angle: offset, points: points, pivot: points[0].parent)
    }

    public func allRelations() -> [Relation] {
        objects.compactMap(relationOf)
    }

    private func distToLinear(_ pos: Vec, _ o: GeoObject, _ a: Vec, _ b: Vec) -> Double {
        switch o {
        case .segment: pointToSegmentDist(pos, a, b)
        case .line: pointToRayDist(pos, a, b, infinite: true)
        default: pointToRayDist(pos, a, b)
        }
    }

    /// Turns line `qId` so that q's direction = direction of p + `offset`, keeping its length (anchor) or
    /// its two arms (pivot). `.intersection` insists on the intersection unless the lines share an
    /// endpoint; `.auto` uses it only when there is no shared endpoint.
    public func rotateRelativeTo(_ pId: Id, _ qId: Id, offset: Double, pivot: RotationPivot, _ resolved: Resolved) -> RelationResult {
        guard let p = object(pId), let q = object(qId), p.isLinear, q.isLinear, p.id != q.id,
              let gp = curveGeom(p, resolved), let gq = curveGeom(q, resolved),
              case let .straight(gpa, gpb, _) = gp, case let .straight(gqa, gqb, _) = gq else { return .failure(.cannotRotate) }
        let pEnds = parentsOf(p)
        let qEnds = parentsOf(q)
        let qDir = dist(gqa, gqb) == 0 ? 0 : angleOf(gqa, gqb)

        let cross = intersect(gp, gq).first ?? nil
        // An endpoint of q shared with p, or lying where they cross: q turns about it.
        let shared = qEnds.first(where: pEnds.contains) ?? cross.flatMap { x in
            qEnds.first { id in resolved[id].map { dist($0, x) < 1e-9 } ?? false }
        }

        // Lines that share an endpoint already meet there: turning around a new point on p would be circular.
        let needsIntersection = shared == nil && (pivot == .intersection || (pivot == .auto && cross != nil))
        if needsIntersection {
            guard let cross else { return .failure(.noIntersection) }
            return rotateAroundIntersection(pId: p.id, q: q, cross: cross, gp: gp, qDir: qDir, offset: offset, resolved)
        }

        // Anchor: the shared endpoint, otherwise the endpoint of q nearest to p.
        let anchorId = shared ?? (distToLinear(gqa, p, gpa, gpb) <= distToLinear(gqb, p, gpa, gpb) ? qEnds[0] : qEnds[1])
        let farId = anchorId == qEnds[0] ? qEnds[1] : qEnds[0]
        guard let farPoint = point(farId), let anchorPos = resolved[anchorId], let farPos = resolved[farId] else { return .failure(.cannotRotate) }
        let flip = farId == qEnds[0] ? Double.pi : 0
        var next = self
        var far = farPoint
        // q is held by an angle to another line r through the anchor: r hangs on q instead, so both keep
        // their angle and turn together.
        if case .directionPoint(let d) = far, d.ref != p.id, d.parent == anchorId, d.onCurve == nil {
            guard let flipped = next.reversingRelation(d, line: q.id, resolved) else { return .failure(.cannotRotate) }
            next = flipped.construction
            far = flipped.point
        }
        guard next.toDirectionPoint(far, parent: anchorId, ref: p.id, offset: offset + flip, distance: dist(anchorPos, farPos)) else {
            return .failure(.cannotRotate)
        }
        return .success(next)
    }

    /// Point `d` hangs on line r (= d.ref) through its parent: make r's other end hang on `line` (the line
    /// through d) at the same angle, and free `d` (keeping a typed length). Nil when r's end can't hang on it.
    private func reversingRelation(_ d: DirectionPoint, line: Id, _ resolved: Resolved) -> (construction: Construction, point: GeoObject)? {
        guard let r = object(d.ref), r.isLinear, case let ends = parentsOf(r), ends.count == 2, ends.contains(d.parent),
              case let yId = ends[0] == d.parent ? ends[1] : ends[0], let y = point(yId),
              let anchor = resolved[d.parent], let yPos = resolved[yId], let xPos = resolved[d.id],
              let lineDir = directionOf(line, resolved), dist(anchor, yPos) > 0 else { return nil }
        var yLocked = false
        switch y {
        case .freePoint: break
        case .distancePoint(let yd) where yd.parent == d.parent && yd.toward == nil: yLocked = true
        default: return nil
        }
        let newY = GeoObject.directionPoint(DirectionPoint(id: yId, name: y.name ?? "", hidden: y.isHidden, parent: d.parent, ref: line,
                                                           offset: angleOf(anchor, yPos) - lineDir, distance: dist(anchor, yPos),
                                                           lengthLocked: yLocked, onCurve: nil))
        let newX: GeoObject = d.lengthLocked
            ? .distancePoint(DistancePoint(id: d.id, name: d.name, hidden: d.hidden, parent: d.parent, distance: d.distance, angle: angleOf(anchor, xPos)))
            : .freePoint(FreePoint(id: d.id, name: d.name, hidden: d.hidden, x: xPos.x, y: xPos.y))
        // Both at once: one without the other would be circular.
        guard let sorted = toposort(objects.map { $0.id == yId ? newY : ($0.id == d.id ? newX : $0) }) else { return nil }
        var next = self
        next.objects = sorted
        return (next, newX)
    }

    /// Replaces `point` by a direction point (from a free point, a distance point or a direction point).
    private mutating func toDirectionPoint(_ point: GeoObject, parent: Id, ref: Id, offset: Double, distance: Double) -> Bool {
        var distance = distance
        var lengthLocked = false
        var onCurve: OnCurve?
        switch point {
        case .distancePoint(let p):
            guard p.parent == parent else { return false }
            lengthLocked = true
            distance = p.distance
        case .directionPoint(let p):
            // Tied to another line already (e.g. |∠ABC| = 50°): re-tying it would silently drop that relation.
            guard p.parent == parent, p.ref == ref else { return false }
            lengthLocked = p.lengthLocked
            distance = p.distance
            onCurve = p.onCurve
        case .freePoint:
            break
        default:
            return false
        }
        return replaceObject(.directionPoint(DirectionPoint(id: point.id, name: point.name ?? "", hidden: point.isHidden, parent: parent, ref: ref,
                                                            offset: offset, distance: distance, lengthLocked: lengthLocked, onCurve: onCurve)))
    }

    private func rotateAroundIntersection(pId: Id, q: GeoObject, cross: Vec, gp: CurveGeom, qDir: Double, offset: Double,
                                          _ resolved: Resolved) -> RelationResult {
        let ends = parentsOf(q)
        guard let pa = point(ends[0]), let pb = point(ends[1]) else { return .failure(.cannotRotate) }
        // X is a hidden helper: the step reads "AB; AB ⊥ p" and the right angle is marked where they cross.
        var next = self
        let x = next.addPointOn(pId, t: project(gp, cross), name: "")
        next.hidePoint(x)
        for end in [pa, pb] {
            guard let pos = resolved[end.id] else { return .failure(.cannotRotate) }
            let along = (pos.x - cross.x) * cos(qDir) + (pos.y - cross.y) * sin(qDir)
            guard next.toDirectionPoint(end, parent: x, ref: pId, offset: offset + (along < 0 ? .pi : 0), distance: dist(pos, cross)) else {
                return .failure(.cannotRotate)
            }
        }
        return .success(next)
    }

    /// Changes the angle of an existing relation (⊥ and ∥ become an ordinary angle). Returns nil if it can't.
    public func settingRelationAngle(_ qId: Id, _ angle: Double) -> Construction? {
        guard let q = object(qId), let rel = relationOf(q), angle >= 0 else { return nil }
        var next = self
        for var pt in rel.points {
            let flip = pt.offset - rel.angle
            pt.offset = angle + (flip / .pi).rounded() * .pi
            guard next.replaceObject(.directionPoint(pt)) else { return nil }
        }
        return next
    }

    /// Removes a relation: the direction points become ordinary (free / distance) points where they are now.
    public func removingRelation(_ qId: Id, _ resolved: Resolved) -> Construction {
        guard let q = object(qId), let rel = relationOf(q) else { return self }
        var next = self
        for pt in rel.points {
            guard let pos = resolved[pt.id] else { continue }
            if pt.lengthLocked, let parentPos = resolved[pt.parent] {
                next.replaceObject(.distancePoint(DistancePoint(id: pt.id, name: pt.name, hidden: pt.hidden, parent: pt.parent,
                                                                distance: pt.distance, angle: angleOf(parentPos, pos))))
            } else {
                next.replaceObject(.freePoint(FreePoint(id: pt.id, name: pt.name, hidden: pt.hidden, x: pos.x, y: pos.y)))
            }
        }
        return next
    }

    /// New line through point `a`, ⊥ or ∥ to p, with a helper direction point.
    public func lineThrough(_ a: Id, _ pId: Id, _ tool: RelationTool, helperLength: Double = 3) -> Construction? {
        guard point(a) != nil, let p = object(pId), p.isLinear else { return nil }
        var next = self
        let b = next.addDirectionPoint(parent: a, ref: pId, offset: tool == .perpendicular ? .pi / 2 : 0,
                                       distance: helperLength, lengthLocked: false)
        next.addLine(a, b)
        return next
    }

    /// ⊥ / ∥ tool, second click. Lines: one of them turns to be ⊥ / ∥ to the other. A point gets a new line through it.
    public func finishRelation(_ tool: RelationTool, _ pId: Id, target: Id, turn: Turn = .less, _ resolved: Resolved) -> RelationResult {
        guard let o = object(target) else { return .failure(.cannotRotate) }
        if o.isPoint {
            return lineThrough(o.id, pId, tool).map { .success($0) } ?? .failure(.cannotRotate)
        }
        guard o.isLinear else { return .failure(.cannotRotate) }
        // Turn the moving line the short way: ⊥ is +90° or −90° from the other, ∥ is 0° or 180°.
        func turnOf(_ ref: Id, _ moving: Id) -> RelationResult {
            let d = directionBetween(ref, moving, resolved)
            let offset = tool == .perpendicular ? (d >= 0 ? Double.pi / 2 : -Double.pi / 2) : (abs(d) <= .pi / 2 ? 0 : Double.pi)
            return rotateRelativeTo(ref, moving, offset: offset, pivot: tool == .perpendicular ? .auto : .anchor, resolved)
        }
        return pick({ turnOf(pId, target) }, { turnOf(target, pId) }, turn, resolved)
    }

    /// The angle between lines p and q that `mouse` lies in, or nil when they don't cross.
    public func angleSector(_ pId: Id, _ qId: Id, mouse: Vec, _ resolved: Resolved) -> AngleSector? {
        guard pId != qId, let p = object(pId), let q = object(qId), let gp = curveGeom(p, resolved), let gq = curveGeom(q, resolved),
              let cross = intersect(gp, gq).first ?? nil,
              let pd = directionOf(pId, resolved), let qd = directionOf(qId, resolved), modPi(qd - pd) > relationEps else { return nil }
        let arms = [(pId, pd), (pId, pd + .pi), (qId, qd), (qId, qd + .pi)]
        let m = dist(cross, mouse) == 0 ? pd + 1e-3 : angleOf(cross, mouse)
        // The arm just clockwise of the mouse starts the sector; the next arm counter-clockwise ends it.
        guard let start = arms.min(by: { mod2Pi(m - $0.1) < mod2Pi(m - $1.1) }),
              let end = arms.filter({ $0.0 != start.0 }).min(by: { mod2Pi($0.1 - start.1) < mod2Pi($1.1 - start.1) }) else { return nil }
        return AngleSector(start: start.0, end: end.0, at: cross, startDir: start.1, size: mod2Pi(end.1 - start.1))
    }

    /// Angle tool: one of the two lines turns around their crossing so that `sector` becomes `angle`
    /// radians, by the smallest turn. The other angles change with it.
    public func finishSectorAngle(_ sector: AngleSector, angle: Double, turn: Turn = .less, _ resolved: Resolved) -> RelationResult {
        guard angle > 0, angle < .pi, let startDir = directionOf(sector.start, resolved),
              let endDir = directionOf(sector.end, resolved) else { return .failure(.cannotRotate) }
        let delta = angle - sector.size
        return pick({ rotateRelativeTo(sector.start, sector.end, offset: endDir + delta - startDir, pivot: .intersection, resolved) },
                    { rotateRelativeTo(sector.end, sector.start, offset: startDir - delta - endDir, pivot: .intersection, resolved) },
                    turn, resolved)
    }

    /// Angle tool: q (or p, see `Turn`) turns around the intersection so that the lines make `angle` radians.
    public func finishAngle(_ pId: Id, _ qId: Id, angle: Double, turn: Turn = .less, _ resolved: Resolved) -> RelationResult {
        guard angle > 0, angle < .pi else { return .failure(.cannotRotate) }
        return pick({ rotateRelativeTo(pId, qId, offset: angle, pivot: .intersection, resolved) },
                    { rotateRelativeTo(qId, pId, offset: angle, pivot: .intersection, resolved) }, turn, resolved)
    }

    private func pick(_ second: () -> RelationResult, _ first: () -> RelationResult, _ turn: Turn, _ resolved: Resolved) -> RelationResult {
        // A turn that would move the exercise doesn't count: then the other line turns.
        func guarded(_ r: RelationResult) -> RelationResult {
            if case .success(let next) = r, touchesExercise(after: next) { return .failure(.cannotRotate) }
            return r
        }
        let a = guarded(second())
        if case .success = a, turn == .second { return a }
        let b = guarded(first())
        guard case .success(let nb) = b else { return a }
        guard case .success(let na) = a else { return b }
        return movement(resolved, nb) < movement(resolved, na) - 1e-9 ? b : a
    }

    /// How far the existing points move (helper points included).
    private func movement(_ before: Resolved, _ c: Construction) -> Double {
        let after = c.resolve()
        return before.reduce(0) { sum, entry in
            sum + (after[entry.key].map { dist(entry.value, $0) } ?? 1000)
        }
    }

    /// Signed angle from the direction of p to the direction of q, in (−π, π].
    private func directionBetween(_ pId: Id, _ qId: Id, _ resolved: Resolved) -> Double {
        func angle(_ id: Id) -> Double {
            guard let o = object(id), o.isLinear else { return 0 }
            let ends = parentsOf(o)
            guard let a = resolved[ends[0]], let b = resolved[ends[1]] else { return 0 }
            return atan2(b.y - a.y, b.x - a.x)
        }
        let d = angle(qId) - angle(pId)
        return atan2(sin(d), cos(d))
    }
}
