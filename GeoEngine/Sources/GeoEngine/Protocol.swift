import Foundation

/// The construction protocol ("zápis konstrukce"): one numbered step per object, in the notation of the
/// spec, with conditions joined by ∧. It is derived from the drawing, never stored.

public struct ProtocolStep: Equatable, Sendable, Identifiable {
    public var objectId: Id
    public var text: String
    /// Everything shown when hovering the step, if more than its own object (a triangle's sides).
    public var highlight: [Id]?
    /// All objects the step stands for: folded endpoints, absorbed sides and hidden helper points.
    public var objects: [Id]
    /// Part of the exercise ("zadání").
    public var exercise = false

    public var id: Id { objectId }
}

public struct ProtocolFormat: Sendable {
    /// Formats a length (6 / 6,5).
    public var dim: @Sendable (Double) -> String
    /// Formats an angle in degrees.
    public var deg: @Sendable (Double) -> String

    public init(dim: @escaping @Sendable (Double) -> String, deg: @escaping @Sendable (Double) -> String) {
        self.dim = dim
        self.deg = deg
    }
}

extension GeoObject {
    /// The two ends of a straight object.
    fileprivate var ends: (a: Id, b: Id)? {
        switch self {
        case .segment(let s): (s.a, s.b)
        case .line(let l), .ray(let l): (l.a, l.b)
        default: nil
        }
    }

    fileprivate var isSegmentOrRay: Bool {
        switch self {
        case .segment, .ray: true
        default: false
        }
    }

    fileprivate var hasName: Bool {
        !(name ?? "").isEmpty
    }
}

extension Construction {
    private func sub(_ id: Id) -> String {
        object(id).map(displayName) ?? "?"
    }

    private func relationText(_ rel: Relation, _ n: String, _ f: ProtocolFormat) -> String {
        let ref = sub(rel.p)
        let smaller = min(rel.angle, .pi - rel.angle)
        switch rel.kind {
        case .perpendicular: return "\(n) ⊥ \(ref)"
        case .parallel: return "\(n) ∥ \(ref)"
        case .angle: return "|∠(\(n), \(ref))| = \(f.deg(smaller * 180 / .pi))°"
        }
    }

    /// A segment / ray turned about a hidden point where it crosses p: its step is "AB; AB ⊥ p".
    private func crossingOf(_ o: GeoObject) -> Relation? {
        guard let rel = relationOf(o), rel.points.count == 2, case .pointOn(let x)? = object(rel.pivot),
              x.hidden, x.on == rel.p else { return nil }
        return rel
    }

    private func isCrossingEnd(_ o: GeoObject?) -> Bool {
        guard case .directionPoint(let p)? = o, p.onCurve == nil, !p.lengthLocked,
              case .pointOn(let x)? = object(p.parent) else { return false }
        return x.hidden && x.on == p.ref
    }

    /// Segment AB around its midpoint M: both ends locked at the same distance from M, on either side.
    private func halvesOf(_ o: GeoObject) -> (rel: Relation, mid: Id, half: Double)? {
        guard case .segment = o, !o.hasName, let rel = relationOf(o), rel.points.count == 2 else { return nil }
        let da = rel.points[0], db = rel.points[1]
        guard let m = object(rel.pivot), !m.isHidden, da.lengthLocked, db.lengthLocked, da.onCurve == nil, db.onCurve == nil,
              abs(da.distance - db.distance) <= 1e-9, abs(wrapAngle(da.offset - db.offset - .pi)) <= 1e-9 else { return nil }
        return (rel, m.id, da.distance)
    }

    private func isHalfEnd(_ o: GeoObject?) -> Bool {
        guard case .directionPoint(let p)? = o else { return false }
        return objects.contains { q in
            guard let e = q.ends, e.a == p.id || e.b == p.id else { return false }
            return halvesOf(q) != nil
        }
    }

    private func isLoosePoint(_ o: GeoObject?) -> Bool {
        if case .freePoint(let p)? = o { return !p.ownStep }
        return false
    }

    private func describe(_ o: GeoObject, _ f: ProtocolFormat) -> String {
        let n = displayName(o)
        switch o {
        case .freePoint:
            return n
        case .distancePoint(let p):
            if let toward = p.toward {
                return "\(n); \(n) ∈ ↦\(sub(p.parent))\(sub(toward)) ∧ |\(sub(p.parent))\(n)| = \(f.dim(p.distance)) cm"
            }
            return "\(n); |\(sub(p.parent))\(n)| = \(f.dim(p.distance)) cm"
        case .pointOn(let p):
            return "\(n); \(n) ∈ \(sub(p.on))"
        case .intersectionPoint(let p):
            return "\(n); \(n) ∈ \(sub(p.a)) ∩ \(sub(p.b))"
        case .directionPoint(let p):
            if isCrossingEnd(o) || isHalfEnd(o) { return n }
            let arm = "\(sub(p.parent))\(n)"
            let ref = sub(p.ref)
            let kind = kindOfOffset(p.offset)
            // ∠BAC when the reference line starts at the same point (A), otherwise ∠(arm, line).
            let refEnds = object(p.ref)?.ends
            let refEnd: Id? = refEnds.flatMap { $0.a == p.parent ? $0.b : ($0.b == p.parent ? $0.a : nil) }
            let angleName = refEnd.map { "|∠\(sub($0))\(sub(p.parent))\(n)|" } ?? "|∠(\(arm), \(ref))|"
            // ∠BAC is the angle between the rays AB and AC (up to 180°); ∠(arm, line) is modulo 180°.
            let towardEnd = refEnds?.a == p.parent ? 0 : Double.pi
            let angle = refEnd != nil ? abs(wrapAngle(p.offset - towardEnd)) : modPi(p.offset)
            // Parallel to a line it starts on: the point lies on that line ("E ∈ AB ∧ |AE| = 2 cm").
            let onRef = kind == .parallel && refEnds != nil && (refEnds!.a == p.parent || refEnds!.b == p.parent)
            let rel: String
            if onRef {
                rel = "\(n) ∈ \(ref)"
            } else {
                switch kind {
                case .perpendicular: rel = "\(arm) ⊥ \(ref)"
                case .parallel: rel = "\(arm) ∥ \(ref)"
                case .angle: rel = "\(angleName) = \(f.deg(angle * 180 / .pi))°"
                }
            }
            var parts = [rel]
            if let onCurve = p.onCurve {
                parts.insert("\(n) ∈ \(sub(onCurve.id))", at: 0)
            } else if p.lengthLocked {
                parts.append("|\(arm)| = \(f.dim(p.distance)) cm")
            }
            return "\(n); \(parts.joined(separator: " ∧ "))"
        case .segment, .ray:
            if !o.hasName, let rel = crossingOf(o) { return "\(n); \(relationText(rel, n, f))" }
            if let halves = halvesOf(o), let e = o.ends {
                let m = sub(halves.mid)
                let parts = [relationText(halves.rel, n, f), "|\(n)| = \(f.dim(2 * halves.half)) cm", "|\(m)\(sub(e.a))| = |\(m)\(sub(e.b))|"]
                return "\(n); \(parts.joined(separator: " ∧ "))"
            }
            guard o.hasName, let e = o.ends, let name = o.name else { return n }
            if case .ray = o { return "\(name) = ↦\(sub(e.a))\(sub(e.b))" }
            return "\(name) = \(sub(e.a))\(sub(e.b))"
        case .line(let l):
            // Its helper points are hidden, so only existing points are mentioned.
            let rel = relationOf(o)
            var through: [Id] = []
            for id in [l.a, l.b] {
                if let q = object(id), !q.isHidden, !through.contains(q.id) { through.append(q.id) }
            }
            if let rel, let pivot = object(rel.pivot), !pivot.isHidden, !through.contains(rel.pivot) { through.append(rel.pivot) }
            var parts: [String] = []
            if !through.isEmpty { parts.append("\(through.map(sub).joined(separator: ", ")) ∈ \(n)") }
            if let rel {
                let ref = sub(rel.p)
                parts.append(relationText(rel, n, f))
                // A parallel through a hidden foot point at a set distance: "|p q| = 4 cm".
                if rel.kind == .parallel, case .directionPoint(let foot)? = object(rel.pivot), foot.hidden, foot.lengthLocked,
                   foot.ref == rel.p, kindOfOffset(foot.offset) == .perpendicular {
                    parts.append("|\(n) \(ref)| = \(f.dim(foot.distance)) cm")
                }
            }
            return parts.isEmpty ? n : "\(n); \(parts.joined(separator: " ∧ "))"
        case .circle(let k):
            let center = sub(k.center)
            let radius: String
            if let through = k.through {
                radius = "|\(center)\(sub(through))|"
            } else if let span = k.span {
                radius = "|\(sub(span[0]))\(sub(span[1]))|"
            } else {
                radius = "\(f.dim(k.radius)) cm"
            }
            return "\(n); \(n)(\(center), r = \(radius))"
        }
    }

    /// Drawing a segment of a typed length creates its endpoints on the fly, so they are folded into the
    /// segment's step. Points placed on their own keep their steps.
    public func buildProtocol(_ f: ProtocolFormat) -> [ProtocolStep] {
        var steps: [ProtocolStep] = []
        let objs = objects

        func removeSteps(last count: Int) -> [Id] {
            let removed = steps.suffix(count).flatMap(\.objects)
            steps.removeLast(count)
            return removed
        }

        for (i, o) in objs.enumerated() {
            if o.isHidden { continue }
            var folded: [Id] = []
            /// A construction step never swallows an exercise step.
            func may(_ id: Id?) -> Bool {
                guard let id else { return false }
                return isExercise(o.id) || !isExercise(id)
            }
            func objectAt(_ k: Int) -> GeoObject? { k >= 0 && k < objs.count ? objs[k] : nil }
            func stepFromEnd(_ k: Int) -> ProtocolStep? { steps.count >= k && k > 0 ? steps[steps.count - k] : nil }

            var made: GeoObject?
            var madeParent: Id?
            switch objectAt(i - 1) {
            case .distancePoint(let p)?: made = objectAt(i - 1); madeParent = p.parent
            case .directionPoint(let p)? where p.onCurve == nil: made = objectAt(i - 1); madeParent = p.parent
            default: break
            }
            if o.isSegmentOrRay, !o.hasName, let made, let e = o.ends, madeParent == e.a, made.id == e.b, may(made.id) {
                var drop = 1
                if stepFromEnd(2)?.objectId == e.a, isLoosePoint(objectAt(i - 2)), may(e.a) { drop = 2 }
                let seg = displayName(o)
                let madeName = displayName(made)
                let text = describe(made, f).replacingFirst(of: "\(madeName); ", with: "\(seg); ")
                let absorbed = removeSteps(last: drop)
                steps.append(ProtocolStep(objectId: o.id, text: text, objects: absorbed + [o.id]))
                continue
            }

            if o.isSegmentOrRay, let e = o.ends {
                // Free endpoints drawn together with the segment are part of its step.
                var drop = 0
                for k in 1...2 {
                    guard let q = objectAt(i - k), isLoosePoint(q) || isCrossingEnd(q) || isHalfEnd(q), q.id == e.a || q.id == e.b,
                          stepFromEnd(k)?.objectId == q.id, may(q.id) else { break }
                    drop += 1
                }
                if drop > 0 { folded = removeSteps(last: drop) }
            }

            if case .segment(let segment) = o {
                let earlier: [Segment] = objs[..<i].compactMap { if case .segment(let s) = $0 { s } else { nil } }
                func joins(_ q: Segment, _ x: Id, _ y: Id) -> Bool { (q.a == x && q.b == y) || (q.a == y && q.b == x) }
                func absorbStep(_ matches: (ProtocolStep) -> Bool) -> [Id] {
                    guard let at = steps.firstIndex(where: matches) else { return [] }
                    return steps.remove(at: at).objects
                }

                let third = objs.first { q in
                    q.id != segment.a && q.id != segment.b && earlier.contains { joins($0, segment.a, q.id) } && earlier.contains { joins($0, segment.b, q.id) }
                }
                if let third {
                    let corners = [segment.a, segment.b, third.id]
                    let names = corners.sorted { x, y in
                        (objs.firstIndex { $0.id == x } ?? 0) < (objs.firstIndex { $0.id == y } ?? 0)
                    }.map(sub)
                    // The triangle absorbs its sides' bare steps; sides that say more stay.
                    var absorbed: [Id] = []
                    let sides = earlier.filter { corners.contains($0.a) && corners.contains($0.b) }
                    for e in sides {
                        absorbed += absorbStep { $0.objectId == e.id && $0.text == displayName(.segment(e)) && may(e.id) }
                    }
                    for v in corners {
                        absorbed += absorbStep { $0.objectId == v && isLoosePoint(object(v)) && $0.text == sub(v) && may(v) }
                    }
                    steps.append(ProtocolStep(objectId: o.id, text: "△ \(names.joined())",
                                              highlight: [o.id] + sides.map(\.id), objects: absorbed + folded + [o.id]))
                    continue
                }

                // A polygon ABCD…: this segment closes a path of earlier segments (the most recent first).
                if !o.hasName {
                    let recent = Array(earlier.reversed())
                    func path(_ from: Id, _ used: Set<Id>, _ corners: [Id]) -> [Id]? {
                        if from == segment.b { return corners.count >= 4 ? corners : nil }
                        for e in recent where !used.contains(e.id) && (e.a == from || e.b == from) {
                            let next = e.a == from ? e.b : e.a
                            if corners.contains(next), next != segment.b { continue }
                            if let found = path(next, used.union([e.id]), corners + [next]) { return found }
                        }
                        return nil
                    }
                    if let found = path(segment.a, [], [segment.a]) {
                        let order = Array(found.reversed())
                        let sideIds = earlier.filter { e in
                            order.indices.contains { k in joins(e, order[k], order[(k + 1) % order.count]) }
                        }.map(\.id)
                        var absorbed: [Id] = []
                        for id in sideIds {
                            guard let e = object(id) else { continue }
                            absorbed += absorbStep { $0.objectId == id && $0.text == displayName(e) && may(id) }
                        }
                        for v in order {
                            absorbed += absorbStep { $0.objectId == v && isLoosePoint(object(v)) && $0.text == sub(v) && may(v) }
                        }
                        steps.append(ProtocolStep(objectId: o.id, text: order.map(sub).joined(),
                                                  highlight: sideIds + [o.id], objects: absorbed + folded + [o.id]))
                        continue
                    }
                }
            }
            steps.append(ProtocolStep(objectId: o.id, text: describe(o, f), objects: folded + [o.id]))
        }

        // A hidden helper point belongs to the step of the first object built on it (its line).
        for o in objs.reversed() where o.isHidden {
            guard let user = objs.first(where: { parentsOf($0).contains(o.id) }),
                  let at = steps.firstIndex(where: { $0.objects.contains(user.id) }) else { continue }
            steps[at].objects.insert(o.id, at: 0)
        }
        for i in steps.indices where isExercise(steps[i].objectId) { steps[i].exercise = true }
        return steps
    }
}

extension String {
    func replacingFirst(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}
