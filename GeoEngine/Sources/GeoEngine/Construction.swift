import Foundation

/// Direct parents of an object: the incoming edges of the DAG.
public func parentsOf(_ o: GeoObject) -> [Id] {
    switch o {
    case .freePoint: []
    case .distancePoint(let p): p.toward.map { [p.parent, $0] } ?? [p.parent]
    case .intersectionPoint(let p): [p.a, p.b]
    case .pointOn(let p): [p.on]
    case .directionPoint(let p): p.onCurve.map { [p.parent, p.ref, $0.id] } ?? [p.parent, p.ref]
    case .segment(let s): [s.a, s.b]
    case .line(let l), .ray(let l): [l.a, l.b]
    case .circle(let k):
        if let through = k.through { [k.center, through] } else if let span = k.span { [k.center] + span } else { [k.center] }
    }
}

/// Stable topological sort (keeps the existing order where possible); nil when there is a cycle.
public func toposort(_ objects: [GeoObject]) -> [GeoObject]? {
    let byId = Dictionary(objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var placed = Set<Id>()
    var visiting = Set<Id>()
    var out: [GeoObject] = []
    func visit(_ o: GeoObject) -> Bool {
        if placed.contains(o.id) { return true }
        if visiting.contains(o.id) { return false }
        visiting.insert(o.id)
        for p in parentsOf(o) {
            if let parent = byId[p], !visit(parent) { return false }
        }
        visiting.remove(o.id)
        placed.insert(o.id)
        out.append(o)
        return true
    }
    for o in objects where !visit(o) { return nil }
    return out
}

public func isDraggable(_ o: GeoObject) -> Bool {
    if o.isHidden { return false }
    switch o {
    case .freePoint, .pointOn: return true
    case .distancePoint(let p): return p.toward == nil
    case .directionPoint(let p): return p.onCurve == nil
    default: return false
    }
}

extension Construction {
    public func object(_ id: Id) -> GeoObject? {
        objects.first { $0.id == id }
    }

    public func point(_ id: Id) -> GeoObject? {
        object(id).flatMap { $0.isPoint ? $0 : nil }
    }

    public func styleOf(_ id: Id) -> ObjectStyle {
        styles[id] ?? ObjectStyle()
    }

    /// Changes the appearance of one object; opacity is kept within 50–100 %.
    public mutating func setStyle(_ id: Id, _ style: ObjectStyle) {
        var next = style
        next.opacity = min(1, max(ObjectStyle.minOpacity, next.opacity))
        styles[id] = next
    }

    public var usedNames: Set<String> {
        Set(objects.compactMap { o in
            guard let name = o.name, !name.isEmpty else { return nil }
            return name
        })
    }

    public func suggestPointName() -> String {
        nextPointName(usedNames)
    }

    /// Display name: segments without a custom name are called after their endpoints (AB).
    public func displayName(_ o: GeoObject) -> String {
        func endpoint(_ id: Id) -> String { object(id)?.name ?? "?" }
        switch o {
        case .segment(let s) where (s.name ?? "").isEmpty: return endpoint(s.a) + endpoint(s.b)
        case .ray(let r) where r.name.isEmpty: return "↦" + endpoint(r.a) + endpoint(r.b)
        default: return o.name ?? ""
        }
    }

    private mutating func add(_ make: (Id) -> GeoObject) -> Id {
        let id = "o\(nextId)"
        objects.append(make(id))
        nextId += 1
        return id
    }

    @discardableResult
    public mutating func addFreePoint(_ pos: Vec, name: String? = nil) -> Id {
        let name = name ?? suggestPointName()
        return add { .freePoint(FreePoint(id: $0, name: name, x: pos.x, y: pos.y)) }
    }

    @discardableResult
    public mutating func addDistancePoint(parent: Id, distance: Double, angle: Double, toward: Id? = nil, name: String? = nil) -> Id {
        let name = name ?? suggestPointName()
        return add { .distancePoint(DistancePoint(id: $0, name: name, parent: parent, distance: distance, angle: angle, toward: toward)) }
    }

    @discardableResult
    public mutating func addIntersectionPoint(_ a: Id, _ b: Id, index: Int, name: String? = nil) -> Id {
        let name = name ?? suggestPointName()
        return add { .intersectionPoint(IntersectionPoint(id: $0, name: name, a: a, b: b, index: index)) }
    }

    @discardableResult
    public mutating func addPointOn(_ on: Id, t: Double, name: String? = nil) -> Id {
        let name = name ?? suggestPointName()
        return add { .pointOn(PointOnObject(id: $0, name: name, on: on, t: t)) }
    }

    @discardableResult
    public mutating func addDirectionPoint(parent: Id, ref: Id, offset: Double, distance: Double, lengthLocked: Bool,
                                           onCurve: OnCurve? = nil, name: String? = nil) -> Id {
        let name = name ?? suggestPointName()
        return add {
            .directionPoint(DirectionPoint(id: $0, name: name, parent: parent, ref: ref, offset: offset,
                                           distance: distance, lengthLocked: lengthLocked, onCurve: onCurve))
        }
    }

    private mutating func update(_ id: Id, _ change: (inout GeoObject) -> Void) {
        guard let i = objects.firstIndex(where: { $0.id == id }) else { return }
        change(&objects[i])
    }

    /// Marks a free point as placed on its own, so the protocol lists it as a separate step.
    public mutating func markOwnStep(_ id: Id) {
        update(id) { o in
            if case .freePoint(var p) = o { p.ownStep = true; o = .freePoint(p) }
        }
    }

    /// Makes a point a hidden helper (an end of a line).
    public mutating func hidePoint(_ id: Id) {
        update(id) { o in
            guard o.isPoint else { return }
            o.name = ""
            o.isHidden = true
        }
    }

    /// Line ↔AB or ray ↦AB. Rays are written ↦AX and have no letter name of their own.
    @discardableResult
    public mutating func addLine(_ a: Id, _ b: Id) -> Id {
        let name = nextLineName(usedNames)
        return add { .line(StraightLine(id: $0, name: name, a: a, b: b)) }
    }

    @discardableResult
    public mutating func addRay(_ a: Id, _ b: Id) -> Id {
        add { .ray(StraightLine(id: $0, name: "", a: a, b: b)) }
    }

    @discardableResult
    public mutating func addSegment(_ a: Id, _ b: Id) -> Id {
        add { .segment(Segment(id: $0, name: nil, a: a, b: b)) }
    }

    /// Circle with a numeric radius; `locked` when the user typed it.
    @discardableResult
    public mutating func addCircle(center: Id, radius: Double, locked: Bool = false, name: String? = nil) -> Id {
        let name = name ?? nextCircleName(usedNames)
        return add { .circle(Circle(id: $0, name: name, center: center, radius: radius, locked: locked)) }
    }

    /// Circle k(S, r = |AD|) whose radius follows the distance of A and D.
    @discardableResult
    public mutating func addCircle(center: Id, span: (Id, Id), name: String? = nil) -> Id {
        let name = name ?? nextCircleName(usedNames)
        return add { .circle(Circle(id: $0, name: name, center: center, span: [span.0, span.1], radius: 0, locked: false)) }
    }

    /// Circle k(S, |SB|) that stays attached to point `through`.
    @discardableResult
    public mutating func addCircle(center: Id, through: Id, name: String? = nil) -> Id {
        let name = name ?? nextCircleName(usedNames)
        return add { .circle(Circle(id: $0, name: name, center: center, through: through, radius: 0, locked: false)) }
    }

    /// Replaces one object (same id) and restores topological order. Returns false, changing nothing, on a cycle.
    @discardableResult
    public mutating func replaceObject(_ next: GeoObject) -> Bool {
        guard let sorted = toposort(objects.map { $0.id == next.id ? next : $0 }) else { return false }
        objects = sorted
        return true
    }

    /// Removes an object together with everything that (transitively) depends on it.
    public mutating func removeObject(_ id: Id) {
        var removed: Set<Id> = [id]
        // Insertion order is topological, so one forward pass catches all descendants.
        for o in objects where parentsOf(o).contains(where: removed.contains) {
            removed.insert(o.id)
        }
        objects.removeAll { removed.contains($0.id) }
    }

    /// Removes `ids` like `removeObject`, except that points built on them stay where they are as free
    /// points, so whatever was built on those points stays too. The two ends of a segment turned about
    /// a removed point keep its direction and length: the first end becomes free and the second a
    /// direction point from it.
    public mutating func removeKeepingPoints(_ ids: [Id]) {
        var removed = Set(ids)
        let positions = resolve()
        var kept: [Id: GeoObject] = [:]
        for o in objects {
            if removed.contains(o.id) || kept[o.id] != nil || !parentsOf(o).contains(where: removed.contains) { continue }
            guard o.isPoint, let pos = positions[o.id] else {
                removed.insert(o.id)
                continue
            }
            kept[o.id] = .freePoint(FreePoint(id: o.id, name: o.name ?? "", hidden: o.isHidden, x: pos.x, y: pos.y))
            guard case .directionPoint(let dp) = o, removed.contains(dp.parent), !removed.contains(dp.ref), dp.onCurve == nil else { continue }
            // Its partner: the other end of a segment / ray turned about the same point, on the other side.
            let partner = objects.compactMap { q -> DirectionPoint? in
                guard case .directionPoint(let other) = q, other.id != dp.id, other.parent == dp.parent, other.ref == dp.ref,
                      other.onCurve == nil, abs(wrapAngle(other.offset - dp.offset - .pi)) < 1e-9 else { return nil }
                let joined = objects.contains { s in
                    guard s.isLinear else { return false }
                    let ends = parentsOf(s)
                    return (ends[0] == dp.id && ends[1] == other.id) || (ends[0] == other.id && ends[1] == dp.id)
                }
                return joined ? other : nil
            }.first
            if var other = partner {
                other.parent = dp.id
                other.distance = dp.distance + other.distance
                other.lengthLocked = dp.lengthLocked && other.lengthLocked
                kept[other.id] = .directionPoint(other)
            }
        }
        if let sorted = toposort(objects.filter { !removed.contains($0.id) }.map { kept[$0.id] ?? $0 }) {
            objects = sorted
        } else if let first = ids.first {
            removeObject(first)
        }
    }

    /// Renames an object. Segments accept nil (back to the endpoint name); others ignore an empty name.
    public mutating func renameObject(_ id: Id, _ name: String?) {
        update(id) { o in
            if case .segment = o { o.name = name } else if let name, !name.isEmpty { o.name = name }
        }
    }

    /// Is `name` already taken by an object other than `exceptId`?
    public func isNameTaken(_ name: String, except exceptId: Id? = nil) -> Bool {
        objects.contains { $0.id != exceptId && $0.name == name }
    }

    /// Drags a point to `target`. A free point moves there; a distance point only rotates towards it;
    /// a point on an object slides along it. Intersection points cannot be dragged.
    public mutating func movePoint(_ id: Id, to target: Vec) {
        let positions = resolve()
        guard let i = objects.firstIndex(where: { $0.id == id }) else { return }
        switch objects[i] {
        case .freePoint(var p):
            p.x = target.x
            p.y = target.y
            objects[i] = .freePoint(p)
        case .distancePoint(var p):
            guard p.toward == nil, let parent = positions[p.parent], dist(parent, target) != 0 else { return }
            p.angle = angleOf(parent, target)
            objects[i] = .distancePoint(p)
        case .directionPoint(var p):
            guard p.onCurve == nil, !p.lengthLocked, let parent = positions[p.parent],
                  let ref = object(p.ref), ref.isLinear,
                  case let .straight(a, b, _)? = curveGeom(ref, positions) else { return }
            let dir = angleOf(a, b) + p.offset
            let along = (target.x - parent.x) * cos(dir) + (target.y - parent.y) * sin(dir)
            p.distance = max(0.01, along)
            objects[i] = .directionPoint(p)
        case .pointOn(var p):
            guard let on = object(p.on), let g = curveGeom(on, positions) else { return }
            p.t = project(g, target)
            objects[i] = .pointOn(p)
        default:
            break
        }
    }

    /// World positions of all points, walking the DAG in topological order. Points whose definition
    /// currently has no solution are left out: they and their dependents are hidden.
    public func resolve() -> Resolved {
        var positions: Resolved = [:]
        var curves: [Id: GeoObject] = [:]
        func geom(_ id: Id) -> CurveGeom? {
            curves[id].flatMap { curveGeom($0, positions) }
        }
        for o in objects {
            switch o {
            case .freePoint(let p):
                positions[p.id] = Vec(x: p.x, y: p.y)
            case .distancePoint(let p):
                guard let parent = positions[p.parent] else { continue }
                if let toward = p.toward {
                    guard let target = positions[toward], dist(parent, target) > 0 else { continue }
                    positions[p.id] = polar(parent, p.distance, angleOf(parent, target))
                } else {
                    positions[p.id] = polar(parent, p.distance, p.angle)
                }
            case .directionPoint(let p):
                guard let parent = positions[p.parent], case let .straight(a, b, _)? = geom(p.ref) else { continue }
                let dir = angleOf(a, b) + p.offset
                if let onCurve = p.onCurve {
                    guard let target = geom(onCurve.id) else { continue }
                    let ray = CurveGeom.straight(a: parent, b: polar(parent, 1, dir), ext: .ray)
                    let hits = intersect(ray, target)
                    if onCurve.index < hits.count, let hit = hits[onCurve.index] { positions[p.id] = hit }
                } else {
                    positions[p.id] = polar(parent, p.distance, dir)
                }
            case .intersectionPoint(let p):
                guard let ga = geom(p.a), let gb = geom(p.b) else { continue }
                let hits = intersect(ga, gb)
                if p.index < hits.count, let hit = hits[p.index] { positions[p.id] = hit }
            case .pointOn(let p):
                if let g = geom(p.on) { positions[p.id] = pointAt(g, p.t) }
            default:
                curves[o.id] = o
            }
        }
        return positions
    }

    /// Finds the object under `p` within `tolerance` (world units). Points win over straight objects,
    /// those over circles; within a class the closest wins.
    public func hitTest(_ resolved: Resolved, at p: Vec, tolerance: Double,
                        filter: (GeoObject) -> Bool = { _ in true }) -> GeoObject? {
        var best: GeoObject?
        var bestScore = Double.infinity
        for o in objects where filter(o) {
            var d = Double.infinity
            var priority = 0.0
            switch o {
            case .segment(let s):
                priority = 1
                if let a = resolved[s.a], let b = resolved[s.b] { d = pointToSegmentDist(p, a, b) }
            case .line(let l), .ray(let l):
                priority = 1
                var infinite = false
                if case .line = o { infinite = true }
                if let a = resolved[l.a], let b = resolved[l.b] { d = pointToRayDist(p, a, b, infinite: infinite) }
            case .circle:
                priority = 2
                if case let .circle(center, radius)? = curveGeom(o, resolved) { d = pointToCircleDist(p, center, radius) }
            default:
                if !o.isHidden, let pos = resolved[o.id] { d = dist(p, pos) }
            }
            if d > tolerance { continue }
            let score = priority * 1e6 + d
            if score < bestScore {
                bestScore = score
                best = o
            }
        }
        return best
    }

    // MARK: Exercise ("zadání")

    public func isExercise(_ id: Id) -> Bool {
        exercise?.contains(id) ?? false
    }

    /// Makes objects part of the exercise (with everything they are built on), or takes them out of it
    /// (with every exercise object built on them, which could otherwise move).
    public mutating func setExercise(_ ids: [Id], on: Bool) {
        var set = Set(exercise ?? [])
        let byId = Dictionary(objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if on {
            func include(_ id: Id) {
                guard !set.contains(id), let o = byId[id] else { return }
                set.insert(id)
                parentsOf(o).forEach(include)
            }
            ids.forEach(include)
        } else {
            var out = Set(ids)
            // Objects are in topological order, so one pass finds everything built on them.
            for o in objects where parentsOf(o).contains(where: out.contains) { out.insert(o.id) }
            set.subtract(out)
        }
        exercise = objects.filter { set.contains($0.id) }.map(\.id)
    }

    /// Does `after` change, restyle or remove an object of this construction's exercise?
    public func touchesExercise(after: Construction) -> Bool {
        guard let exercise, !exercise.isEmpty else { return false }
        return exercise.contains { id in
            guard let b = after.object(id) else { return true }
            return object(id) != b || styles[id] != after.styles[id]
        }
    }
}
