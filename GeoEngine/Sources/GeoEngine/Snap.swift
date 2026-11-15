import Foundation

/// Where a new point would go, in priority order: existing point, intersection, on a curve, free.
public enum Snap: Equatable, Sendable {
    case point(id: Id, pos: Vec)
    case intersection(a: Id, b: Id, index: Int, pos: Vec)
    case on(curve: Id, t: Double, pos: Vec)
    case free(pos: Vec)

    public var pos: Vec {
        switch self {
        case .point(_, let pos), .intersection(_, _, _, let pos), .on(_, _, let pos), .free(let pos): pos
        }
    }

    /// Ids of the objects this snap refers to (for highlighting).
    public var targets: [Id] {
        switch self {
        case .point(let id, _): [id]
        case .intersection(let a, let b, _, _): [a, b]
        case .on(let curve, _, _): [curve]
        case .free: []
        }
    }
}

/// How close (radians) a drawn line must be to ⊥ / ∥ before it snaps: 2°.
public let directionSnapTolerance = 2 * Double.pi / 180

/// A drawn line that snaps to be perpendicular / parallel to `ref`: direction = direction of ref + offset.
public struct DirectionSnap: Equatable, Sendable {
    public let kind: RelationTool
    public let ref: Id
    public let offset: Double
    /// ⊥ only: the new line starts on the reference line (so the ⊥ mark can sit at the corner).
    public let touching: Bool
}

/// A ⊥ / ∥ line that also ends on another object: where the direction meets curve `curve`.
public struct DirectionHit: Equatable, Sendable {
    public let curve: Id
    public let index: Int
    public let pos: Vec
}

extension Construction {
    /// Looks for a line the segment start→mouse is almost ⊥ or ∥ to.
    public func findDirectionSnap(_ resolved: Resolved, start: Vec, mouse: Vec, excluding: Set<Id> = []) -> DirectionSnap? {
        if dist(start, mouse) == 0 { return nil }
        let heading = atan2(mouse.y - start.y, mouse.x - start.x)
        var best: DirectionSnap?
        var bestDev = directionSnapTolerance
        for o in objects where o.isLinear && !excluding.contains(o.id) {
            guard case let .straight(a, b, ext)? = curveGeom(o, resolved), dist(a, b) != 0 else { continue }
            let phi = atan2(b.y - a.y, b.x - a.x)
            let d = ext == .segment ? pointToSegmentDist(start, a, b) : pointToRayDist(start, a, b, infinite: ext == .line)
            let through = d < epsWorld
            // ⊥ works against every line; ∥ only for lines not through the start.
            var candidates: [(RelationTool, Double)] = [(.perpendicular, .pi / 2), (.perpendicular, -.pi / 2)]
            if !through { candidates += [(.parallel, 0), (.parallel, .pi)] }
            for (kind, offset) in candidates {
                let dev = abs(wrapAngle(heading - (phi + offset))) - (through ? 1e-9 : 0) // ties go to lines through the start
                if dev < bestDev {
                    bestDev = dev
                    best = DirectionSnap(kind: kind, ref: o.id, offset: offset, touching: through)
                }
            }
        }
        return best
    }

    /// The ray from `start` in direction `dir` meets a curve close to the mouse: the end can sit on that curve.
    public func findDirectionHit(_ resolved: Resolved, start: Vec, dir: Double, mouse: Vec, tolerance: Double) -> DirectionHit? {
        let ray = CurveGeom.straight(a: start, b: polar(start, 1, dir), ext: .ray)
        var best: DirectionHit?
        var bestD = tolerance
        for o in objects where o.isCurve {
            guard let g = curveGeom(o, resolved) else { continue }
            for (index, hit) in intersect(ray, g).enumerated() {
                guard let pos = hit, dist(pos, start) >= epsWorld else { continue }
                let d = dist(pos, mouse)
                if d <= bestD {
                    bestD = d
                    best = DirectionHit(curve: o.id, index: index, pos: pos)
                }
            }
        }
        return best
    }

    public func findSnap(_ resolved: Resolved, at p: Vec, tolerance: Double) -> Snap {
        // 1. Existing points.
        var best: Snap?
        var bestD = tolerance
        for o in objects where o.isPoint && !o.isHidden {
            guard let pos = resolved[o.id] else { continue }
            let d = dist(p, pos)
            if d <= bestD {
                best = .point(id: o.id, pos: pos)
                bestD = d
            }
        }
        if let best { return best }

        let curves = objects.compactMap { o in curveGeom(o, resolved).map { (id: o.id, g: $0) } }

        // 2. Intersections of two curves.
        for i in curves.indices {
            for j in curves.indices where j > i {
                for (index, hit) in intersect(curves[i].g, curves[j].g).enumerated() {
                    guard let pos = hit else { continue }
                    let d = dist(p, pos)
                    if d <= bestD {
                        best = .intersection(a: curves[i].id, b: curves[j].id, index: index, pos: pos)
                        bestD = d
                    }
                }
            }
        }
        if let best { return best }

        // 3. A single curve.
        for (id, g) in curves {
            let t = project(g, p)
            let pos = pointAt(g, t)
            let d = dist(p, pos)
            if d <= bestD {
                best = .on(curve: id, t: t, pos: pos)
                bestD = d
            }
        }
        return best ?? .free(pos: p)
    }

    /// Turns a snap into a point id, creating the (dependent) point if needed.
    @discardableResult
    public mutating func materializeSnap(_ snap: Snap, name: String? = nil) -> Id {
        switch snap {
        case .point(let id, _): id
        case let .intersection(a, b, index, _): addIntersectionPoint(a, b, index: index, name: name)
        case let .on(curve, t, _): addPointOn(curve, t: t, name: name)
        case .free(let pos): addFreePoint(pos, name: name)
        }
    }

    /// Point tool: places a point at the snap. A free point keeps its own protocol step.
    /// Returns nil when the snap is an existing point, since nothing new is placed.
    @discardableResult
    public mutating func placePoint(_ snap: Snap) -> Id? {
        if case .point = snap { return nil }
        let id = materializeSnap(snap)
        markOwnStep(id)
        return id
    }
}
