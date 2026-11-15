import Foundation

/// Turns a typed step into objects. Names that don't exist yet are created as free points at automatic
/// spots; a step being edited keeps the ids of its objects so everything built on them follows.

public enum TypingError: String, Error, Sendable {
    case unknown = "typing.unknown"
    case unknownObject = "typing.unknownObject"
    case notLine = "typing.notLine"
    case breaks = "typing.breaks"
    case exerciseLocked = "exercise.locked"
    case nameTaken = "error.nameTaken"
    case number = "error.number"
    case angle = "error.angle"
    case noIntersection = "error.noIntersection"
    case cannotRotate = "error.cannotRotate"
    case cannotEditSegment = "error.cannotEditSegment"
    case cannotEditCircle = "error.cannotEditCircle"
}

public struct TypingFailure: Error, Equatable, Sendable {
    public let error: TypingError
    public let name: String?

    init(_ error: TypingError, _ name: String? = nil) {
        self.error = error
        self.name = name
    }
}

public struct TypingResult: Sendable {
    public let construction: Construction
    public let select: Id?

    public init(construction: Construction, select: Id?) {
        self.construction = construction
        self.select = select
    }
}

public struct TypingContext: Sendable {
    /// Where new points go: around the centre of the visible area.
    public var center: Vec
    /// Positions the points had before an edit, by name, so an edited step doesn't jump.
    public var prior: [String: Vec] = [:]

    public init(center: Vec, prior: [String: Vec] = [:]) {
        self.center = center
        self.prior = prior
    }
}

private let defaultLength = 3.0
private let spacing = 3.0
private let degrees = Double.pi / 180

private func category(_ o: GeoObject) -> Int {
    o.isPoint ? 0 : (o.isLinear ? 1 : 2)
}

private func numericId(_ id: Id) -> Int {
    Int(id.dropFirst()) ?? 0
}

/// Applies `f` to every id the object refers to.
private func remap(_ o: GeoObject, _ f: (Id) -> Id) -> GeoObject {
    switch o {
    case .freePoint:
        return o
    case .distancePoint(var p):
        p.parent = f(p.parent)
        return .distancePoint(p)
    case .intersectionPoint(var p):
        p.a = f(p.a)
        p.b = f(p.b)
        return .intersectionPoint(p)
    case .pointOn(var p):
        p.on = f(p.on)
        return .pointOn(p)
    case .directionPoint(var p):
        p.parent = f(p.parent)
        p.ref = f(p.ref)
        if let onCurve = p.onCurve { p.onCurve = OnCurve(id: f(onCurve.id), index: onCurve.index) }
        return .directionPoint(p)
    case .segment(var s):
        s.a = f(s.a)
        s.b = f(s.b)
        return .segment(s)
    case .line(var l):
        l.a = f(l.a)
        l.b = f(l.b)
        return .line(l)
    case .ray(var l):
        l.a = f(l.a)
        l.b = f(l.b)
        return .ray(l)
    case .circle(var k):
        k.center = f(k.center)
        k.through = k.through.map(f)
        k.span = k.span?.map(f)
        return .circle(k)
    }
}

private func withId(_ o: GeoObject, _ id: Id) -> GeoObject {
    switch o {
    case .freePoint(var p): p.id = id; return .freePoint(p)
    case .distancePoint(var p): p.id = id; return .distancePoint(p)
    case .intersectionPoint(var p): p.id = id; return .intersectionPoint(p)
    case .pointOn(var p): p.id = id; return .pointOn(p)
    case .directionPoint(var p): p.id = id; return .directionPoint(p)
    case .segment(var s): s.id = id; return .segment(s)
    case .line(var l): l.id = id; return .line(l)
    case .ray(var l): l.id = id; return .ray(l)
    case .circle(var k): k.id = id; return .circle(k)
    }
}

private func ends(_ o: GeoObject) -> (a: Id, b: Id)? {
    guard o.isLinear else { return nil }
    let p = parentsOf(o)
    return (p[0], p[1])
}

private enum LineRelation {
    case perp(Ref)
    case par(Ref)
    case angle(Ref, Double)

    var ref: Ref {
        switch self {
        case .perp(let r), .par(let r), .angle(let r, _): r
        }
    }
}

private enum Direction {
    case perp(Ref)
    case par(Ref)
    case angle3(a: String, deg: Double)
    case angle2(Ref, deg: Double)
}

private final class Builder {
    var c: Construction
    let ctx: TypingContext
    var taken: [Vec] = []
    /// The object the step is about, selected afterwards.
    var main: Id?

    init(_ c: Construction, _ ctx: TypingContext) {
        self.c = c
        self.ctx = ctx
    }

    var res: Resolved { c.resolve() }

    func byName(_ name: String) -> GeoObject? {
        c.objects.first { $0.name == name && !$0.isHidden }
    }

    func exists(_ name: String) -> Bool { byName(name) != nil }

    func fresh(_ name: String) throws {
        if exists(name) { throw TypingFailure(.nameTaken, name) }
    }

    func posOf(_ id: Id) throws -> Vec {
        guard let p = res[id] else { throw TypingFailure(.noIntersection) }
        return p
    }

    /// A free spot near the centre of the view, away from existing points.
    func spot() -> Vec {
        let used = Array(res.values) + taken
        func isFree(_ p: Vec) -> Bool { used.allSatisfy { dist(p, $0) >= spacing * 0.9 } }
        for ring in 0..<12 {
            let n = ring == 0 ? 1 : ring * 6
            for k in 0..<n {
                let angle = Double.pi + 2 * .pi * Double(k) / Double(n)
                let p = ring == 0 ? ctx.center : polar(ctx.center, Double(ring) * spacing, angle)
                if isFree(p) { return reserve(p) }
            }
        }
        return reserve(ctx.center)
    }

    @discardableResult
    func reserve(_ p: Vec) -> Vec {
        taken.append(p)
        return p
    }

    func prior(_ name: String) -> Vec? { ctx.prior[name] }

    /// Id of point `name`, created as a free point when it doesn't exist.
    func point(_ name: String) throws -> Id {
        if let o = byName(name) {
            guard o.isPoint else { throw TypingFailure(.unknownObject, name) }
            return o.id
        }
        let pos = prior(name).map(reserve) ?? spot()
        return c.addFreePoint(pos, name: name)
    }

    func curve(_ ref: Ref) throws -> Id {
        guard let found = findCurve(ref) else { throw TypingFailure(.unknownObject, ref.text) }
        return found.id
    }

    func linear(_ ref: Ref) throws -> Id {
        let id = try curve(ref)
        guard let o = c.object(id), o.isLinear else { throw TypingFailure(.notLine, ref.text) }
        return o.id
    }

    func findCurve(_ ref: Ref) -> GeoObject? {
        if case .name(let name) = ref {
            return byName(name).flatMap { $0.isCurve ? $0 : nil }
        }
        guard let points = ref.points, let a = byName(points.a), let b = byName(points.b) else { return nil }
        func from(_ o: GeoObject) -> Bool { ends(o).map { $0.a == a.id && $0.b == b.id } ?? false }
        func either(_ o: GeoObject) -> Bool { from(o) || (ends(o).map { $0.a == b.id && $0.b == a.id } ?? false) }
        func isRay(_ o: GeoObject) -> Bool { if case .ray = o { true } else { false } }
        func isSegment(_ o: GeoObject) -> Bool { if case .segment = o { true } else { false } }
        func isLine(_ o: GeoObject) -> Bool { if case .line = o { true } else { false } }
        if case .ray = ref { return c.objects.first { isRay($0) && from($0) } }
        // "AX" is segment AX or, when there is none, ray ↦AX or a line through A and X.
        return c.objects.first { isSegment($0) && either($0) }
            ?? c.objects.first { isRay($0) && from($0) }
            ?? c.objects.first { isLine($0) && either($0) }
    }

    /// The straight object through two points (either order), made as a segment if there is none.
    func linearThrough(_ a: Id, _ b: Id) -> Id {
        if let found = c.objects.first(where: { o in
            ends(o).map { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) } ?? false
        }) { return found.id }
        return c.addSegment(a, b)
    }

    func join(_ a: Id, _ b: Id, _ shape: NamedShape) throws -> Id {
        if a == b { throw TypingFailure(.unknown) }
        switch shape {
        case .segment:
            if let found = c.objects.first(where: { o in
                guard case .segment(let s) = o else { return false }
                return (s.a == a && s.b == b) || (s.a == b && s.b == a)
            }) { return found.id }
            return c.addSegment(a, b)
        case .line:
            return c.addLine(a, b)
        case .ray:
            return c.addRay(a, b)
        }
    }

    // MARK: Steps

    func run(_ st: Statement) throws {
        guard let head = st.head else {
            if st.clauses.count == 1 { return try single(st.clauses[0]) }
            // "|AB| = 3, AB ⊥ p" without a head: the segment of the first clause is the head.
            for cl in st.clauses {
                if case let .length(a, b, _, _) = cl { return try headed(.seg(a, b), st.clauses) }
                if case let .rel(_, left, _) = cl, let h = left.head { return try headed(h, st.clauses) }
            }
            throw TypingFailure(.unknown)
        }
        try headed(head, st.clauses)
    }

    func single(_ cl: Clause) throws {
        switch cl {
        case let .names(raw, lower):
            if lower, raw.count == 1 { return try line(raw[0], [], nil) }
            let names = raw.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            if names.count == 1 {
                try fresh(names[0])
                let id = try point(names[0])
                main = id
                c.markOwnStep(id)
                return
            }
            if names.count == 2 {
                main = try join(try point(names[0]), try point(names[1]), .segment)
                return
            }
            // ABC is a triangle, ABCD… a polygon.
            try polygon(names)
        case let .length(a, b, value, _):
            try length(a, b, value, .segment)
        case let .within(points, target):
            if points.count != 1 { throw TypingFailure(.unknown) }
            try pointOn(points[0], target)
        case let .cap(p, a, b):
            try intersection(p, a, b)
        case let .rel(_, left, right), let .angle2(left, right, _):
            // Both lines exist: turn the left one. Otherwise the left one is a new arm (AB ⊥ p).
            if let h = left.head, findCurve(left) == nil { return try headed(h, [cl]) }
            let q = try linear(left)
            let p = try linear(right)
            let result: RelationResult
            if case .rel(let symbol, _, _) = cl {
                result = c.finishRelation(symbol == .perp ? .perpendicular : .parallel, p, target: q, turn: .second, res)
            } else if case .angle2(_, _, let deg) = cl {
                try checkedAngle(deg)
                result = c.finishAngle(p, q, angle: deg * degrees, turn: .second, res)
            } else {
                throw TypingFailure(.unknown)
            }
            switch result {
            case .success(let next): c = next
            case .failure(let e): throw TypingFailure(e == .noIntersection ? .noIntersection : .cannotRotate)
            }
            main = q
        case let .angle3(_, v, b, _):
            // ∠BAC = 60° on its own: C is the new end of segment AC.
            try headed(.seg(v, b), [cl])
        case let .circle(name, center, radius):
            try circle(name, center, radius)
        case let .named(name, shape, a, b):
            try fresh(name)
            let pa = try point(a)
            let pb = try point(b)
            let id = try join(pa, pb, shape)
            c.renameObject(id, name)
            main = id
        case let .linear(shape, a, b):
            let pa = try point(a)
            main = try join(pa, try point(b), shape)
        case let .triangle(pts):
            try polygon(pts)
        case .equal, .dist:
            throw TypingFailure(.unknown)
        }
    }

    func headed(_ head: Head, _ clauses: [Clause]) throws {
        switch head {
        case .name(let name):
            try headedName(name, clauses)
        case .point(let p):
            if clauses.count == 1 {
                let cl = clauses[0]
                switch cl {
                case let .names(names, _) where names.count == 1 && names[0].uppercased() == p.uppercased():
                    return try single(cl)
                case let .within(points, target) where points.count == 1 && points[0] == p:
                    return try pointOn(p, target)
                case let .cap(point, a, b) where point == p:
                    return try intersection(p, a, b)
                case let .length(a, b, value, _) where a == p || b == p:
                    return try distancePoint(a == p ? b : a, p, value)
                default:
                    break
                }
            }
            try direction(nil, p, clauses, nil)
        case let .seg(a, b), let .ray(a, b):
            // AB; … or ↦AB; … : B is the new end.
            var shape = NamedShape.segment
            if case .ray = head { shape = .ray }
            if clauses.count == 1, case let .length(la, lb, value, _) = clauses[0] {
                guard (la == a && lb == b) || (la == b && lb == a) else { throw TypingFailure(.unknown) }
                return try length(a, b, value, shape)
            }
            try direction(a, b, clauses, shape)
        }
    }

    /// p; …  or  k; k(S, r)  or  a = BC
    func headedName(_ name: String, _ clauses: [Clause]) throws {
        if clauses.count == 1 {
            switch clauses[0] {
            case let .circle(n, center, radius):
                if n != name { throw TypingFailure(.unknown) }
                return try circle(name, center, radius)
            case let .names(names, _) where names.count == 1 && names[0] == name:
                return try line(name, [], nil)
            default:
                break
            }
        }
        var points: [String] = []
        var rel: LineRelation?
        var away: (ref: Ref, d: Double)?
        for cl in clauses {
            switch cl {
            case let .dist(l, ref, value) where l == name && away == nil:
                away = (ref, value)
            case let .length(_, _, value, lines?) where (lines.0 == name || lines.1 == name) && away == nil:
                away = (.name(lines.0 == name ? lines.1 : lines.0), value)
            case let .within(pts, .name(target)) where target == name:
                points += pts
            case let .rel(symbol, .name(left), right) where left == name && rel == nil:
                rel = symbol == .perp ? .perp(right) : .par(right)
            case let .angle2(.name(left), right, deg) where left == name && rel == nil:
                rel = .angle(right, deg)
            default:
                throw TypingFailure(.unknown)
            }
        }
        if let away {
            // "p; p ∥ q ∧ |p q| = 4 cm": the distance needs no ∥, but any other relation or point contradicts it.
            if !points.isEmpty { throw TypingFailure(.unknown) }
            if let rel {
                guard case .par(let r) = rel, findCurve(r)?.id == findCurve(away.ref)?.id else { throw TypingFailure(.unknown) }
            }
            return try parallelAt(name, away.ref, away.d)
        }
        try line(name, points, rel)
    }

    /// Line p ∥ ref at distance d: through a hidden foot point at d from ref's first point.
    func parallelAt(_ name: String, _ refRef: Ref, _ d: Double) throws {
        try fresh(name)
        if !(d > 0) { throw TypingFailure(.number) }
        let ref = try linear(refRef)
        guard let r = c.object(ref), let re = ends(r), case let .straight(ga, gb, _)? = curveGeom(r, res) else {
            throw TypingFailure(.cannotRotate)
        }
        let center = ctx.center
        let cross = (gb.x - ga.x) * (center.y - ga.y) - (gb.y - ga.y) * (center.x - ga.x)
        let side = cross < 0 ? -Double.pi / 2 : Double.pi / 2
        let foot = c.addDirectionPoint(parent: re.a, ref: ref, offset: side, distance: d, lengthLocked: true, name: "")
        c.hidePoint(foot)
        let b = c.addDirectionPoint(parent: foot, ref: ref, offset: 0, distance: defaultLength, lengthLocked: false, name: "")
        c.hidePoint(b)
        let id = c.addLine(foot, b)
        c.renameObject(id, name)
        main = id
    }

    /// Line p through up to two points, or through one point with a relation to another line.
    func line(_ name: String, _ points: [String], _ rel: LineRelation?) throws {
        try fresh(name)
        if points.count > 2 { throw TypingFailure(.unknown) }
        let a: Id
        let b: Id
        if let rel {
            let ref = try linear(rel.ref)
            if case .angle(_, let deg) = rel { try checkedAngle(deg) }
            a = try points.isEmpty ? hiddenPoint(spot()) : point(points[0])
            let offset: Double
            switch rel {
            case .perp: offset = .pi / 2
            case .par: offset = 0
            case .angle(_, let deg): offset = deg * degrees
            }
            // "q; B, E ∈ q, q ⊥ p": the second point is the visible point that sets q's direction.
            let helper = points.count > 1 ? points[1] : nil
            if let helper, exists(helper) {
                let existing = try point(helper)
                guard case .directionPoint(let e)? = c.object(existing), e.parent == a, e.ref == ref else { throw TypingFailure(.unknown) }
                let id = c.addLine(a, existing)
                c.renameObject(id, name)
                main = id
                return
            }
            let priorPos = helper.flatMap(prior)
            let from = try posOf(a)
            var side = offset
            if let priorPos, let refObject = c.object(ref), case let .straight(ga, gb, _)? = curveGeom(refObject, res),
               abs(wrapAngle(angleOf(ga, gb) + offset - angleOf(from, priorPos))) > .pi / 2 {
                side += .pi
            }
            let distance = priorPos.map { max(0.01, dist(from, $0)) } ?? defaultLength
            b = c.addDirectionPoint(parent: a, ref: ref, offset: side, distance: distance, lengthLocked: false, name: helper ?? "")
            if helper == nil { c.hidePoint(b) }
        } else {
            a = try points.isEmpty ? hiddenPoint(spot()) : point(points[0])
            if points.count == 2 {
                b = try point(points[1])
            } else {
                let from = try posOf(a)
                b = hiddenPoint(reserve(polar(from, defaultLength, points.isEmpty ? 0 : .pi / 4)))
            }
        }
        let id = c.addLine(a, b)
        c.renameObject(id, name)
        main = id
    }

    func hiddenPoint(_ pos: Vec) -> Id {
        let id = c.addFreePoint(pos, name: "")
        c.hidePoint(id)
        return id
    }

    func circle(_ name: String, _ center: String, _ radius: Radius) throws {
        try fresh(name)
        let s = try point(center)
        switch radius {
        case .value(let r):
            if !(r > 0) { throw TypingFailure(.number) }
            main = c.addCircle(center: s, radius: r, locked: true, name: name)
        case let .span(a, b):
            if a == b { throw TypingFailure(.unknown) }
            if a == center || b == center {
                // k(S, r = |SB|): through B.
                let through = try point(a == center ? b : a)
                main = c.addCircle(center: s, through: through, name: name)
            } else {
                // k(C, r = |AD|): the radius follows AD.
                let pa = try point(a)
                let pb = try point(b)
                main = c.addCircle(center: s, span: (pa, pb), name: name)
            }
        }
    }

    /// |AB| = d: B (or A) becomes a point at that distance, or the existing segment gets that length.
    func length(_ a: String, _ b: String, _ d: Double, _ shape: NamedShape) throws {
        if !(d > 0) { throw TypingFailure(.number) }
        if exists(a), exists(b) {
            // An existing ray ↦AB gets the length; `join` only reuses segments.
            var seg = shape == .ray ? findCurve(.ray(a, b))?.id : nil
            if seg == nil {
                let pa = try point(a)
                seg = try join(pa, try point(b), shape)
            }
            if let error = c.setSegmentLength(seg!, d) { throw TypingFailure(Self.map(error)) }
            main = seg
            return
        }
        let (from, to) = exists(b) ? (b, a) : (a, b)
        try distancePoint(from, to, d)
        let pa = try point(a)
        main = try join(pa, try point(b), shape)
    }

    static func map(_ e: DimensionError) -> TypingError {
        switch e {
        case .cannotEditSegment: .cannotEditSegment
        case .cannotEditCircle: .cannotEditCircle
        case .exerciseLocked: .exerciseLocked
        }
    }

    func distancePoint(_ from: String, _ name: String, _ d: Double) throws {
        if !(d > 0) { throw TypingFailure(.number) }
        try fresh(name)
        let parent = try point(from)
        let start = try posOf(parent)
        var angle = freeAngle(start, d)
        if let p = prior(name), dist(p, start) > 0 { angle = angleOf(start, p) }
        main = c.addDistancePoint(parent: parent, distance: d, angle: angle, name: name)
    }

    /// "C ∈ ↦AB ∧ |AC| = d": C on the ray from A through B, d from A.
    func aimedPoint(_ from: String, _ through: String, _ name: String, _ d: Double) throws {
        if !(d > 0) { throw TypingFailure(.number) }
        try fresh(name)
        let parent = try point(from)
        let target = try point(through)
        let start = try posOf(parent)
        let aim = try posOf(target)
        guard dist(start, aim) > 0 else { throw TypingFailure(.unknown) }
        main = c.addDistancePoint(parent: parent, distance: d, angle: angleOf(start, aim), toward: target, name: name)
    }

    /// A direction from `from` whose end (at distance d) is away from other points: right if possible.
    func freeAngle(_ from: Vec, _ d: Double) -> Double {
        let used = Array(res.values) + taken
        for k in 0..<8 {
            let angle = Double(k) * .pi / 4
            let p = polar(from, d, angle)
            if used.allSatisfy({ dist(p, $0) >= spacing * 0.5 }) { return angle }
        }
        return 0
    }

    func pointOn(_ name: String, _ target: Ref) throws {
        try fresh(name)
        let on = try curve(target)
        guard let object = c.object(on), let g = curveGeom(object, res) else { throw TypingFailure(.noIntersection) }
        var t: Double
        if case .circle = g { t = .pi / 4 } else { t = 0.5 }
        if let p = prior(name) { t = project(g, p) }
        main = c.addPointOn(on, t: t, name: name)
    }

    func intersection(_ name: String, _ ra: Ref, _ rb: Ref) throws {
        try fresh(name)
        let a = try curve(ra)
        let b = try curve(rb)
        if a == b { throw TypingFailure(.unknown) }
        var hits: [Vec?] = []
        if let oa = c.object(a), let ob = c.object(b), let ga = curveGeom(oa, res), let gb = curveGeom(ob, res) { hits = intersect(ga, gb) }
        let used = Set(c.objects.compactMap { o -> Int? in
            guard case .intersectionPoint(let p) = o, (p.a == a && p.b == b) || (p.a == b && p.b == a) else { return nil }
            return p.index
        })
        let candidates = hits.enumerated().compactMap { index, p in p.map { (p: $0, index: index) } }
        guard let first = candidates.first else { throw TypingFailure(.noIntersection) }
        let pick: (p: Vec, index: Int)
        if let priorPos = prior(name) {
            pick = candidates.dropFirst().reduce(first) { best, h in dist(h.p, priorPos) < dist(best.p, priorPos) ? h : best }
        } else {
            pick = candidates.first { !used.contains($0.index) } ?? first
        }
        main = c.addIntersectionPoint(a, b, index: pick.index, name: name)
    }

    /// A point P whose direction from its parent is tied to a line: "AB ⊥ p", "AB ∥ p", "∠CAB = 30°",
    /// "∠(AB, p) = 30°", optionally with "|AB| = 3 cm" or "B ∈ k". With a shape, segment / ray AP follows.
    func direction(_ parentName: String?, _ name: String, _ clauses: [Clause], _ shape: NamedShape?) throws {
        var parentOpt = parentName
        var length: Double?
        var onCurve: Ref?
        var mid: (a: [String], b: [String])?
        var dir: Direction?
        func setParent(_ p: String) throws {
            if let parentOpt, parentOpt != p { throw TypingFailure(.unknown) }
            parentOpt = p
        }
        for cl in clauses {
            switch cl {
            case let .rel(symbol, left, right) where left.points?.b == name && dir == nil:
                try setParent(left.points!.a)
                dir = symbol == .perp ? .perp(right) : .par(right)
            case let .angle2(left, right, deg) where left.points?.b == name && dir == nil:
                try setParent(left.points!.a)
                dir = .angle2(right, deg: deg)
            case let .angle3(a, v, b, deg) where b == name && dir == nil:
                try setParent(v)
                dir = .angle3(a: a, deg: deg)
            case let .length(a, b, value, _) where (b == name || a == name) && length == nil:
                try setParent(a == name ? b : a)
                length = value
            case let .within(points, target) where points.count == 1 && points[0] == name && onCurve == nil:
                onCurve = target
            case let .equal(a, b) where mid == nil:
                mid = (a, b)
            default:
                throw TypingFailure(.unknown)
            }
        }
        guard let parent = parentOpt else { throw TypingFailure(.unknown) }
        // "E ∈ AB ∧ |AE| = 2 cm": E lies on AB at that distance from its end A.
        var along: Ref?
        if dir == nil, length != nil, let target = onCurve, let o = findCurve(target), let p = byName(parent), let e = ends(o), e.a == p.id || e.b == p.id {
            along = target
            dir = .par(target)
            onCurve = nil
        }
        // "C ∈ ↦AB ∧ |AC| = 5 cm" with no ray AB drawn: C sits on the ray through B at that distance.
        if dir == nil, let length, case let .ray(ra, rb)? = onCurve, ra == parent, rb != name, findCurve(.ray(ra, rb)) == nil {
            try aimedPoint(parent, rb, name, length)
            if let shape {
                let pa = try point(parent)
                main = try join(pa, try point(name), shape)
            }
            return
        }
        guard let direction = dir else {
            if let length, onCurve == nil, let shape { return try self.length(parent, name, length, shape) }
            if let length, onCurve == nil { return try distancePoint(parent, name, length) }
            throw TypingFailure(.unknown)
        }
        if let mid {
            // "AB; AB ⊥ p ∧ |AB| = 3 cm ∧ |CA| = |CB|": C is the midpoint of AB.
            guard let m = mid.a.first(where: mid.b.contains) else { throw TypingFailure(.unknown) }
            let others = (mid.a + mid.b).filter { $0 != m }
            guard others.count == 2, others.contains(parent), others.contains(name) else { throw TypingFailure(.unknown) }
            if case .angle3 = direction { throw TypingFailure(.unknown) }
            guard let length, onCurve == nil, shape == .segment else { throw TypingFailure(.unknown) }
            if !(length > 0) { throw TypingFailure(.number) }
            try fresh(parent)
            try fresh(name)
            let (refValue, theta) = try thetaOf(direction)
            return try halves(m, parent, name, try linear(refValue), theta, length)
        }
        if length != nil, onCurve != nil { throw TypingFailure(.unknown) }
        if let length, !(length > 0) { throw TypingFailure(.number) }
        try fresh(name)
        // "AB; AB ⊥ p" with no A yet: AB crosses p in the middle.
        var isAngle3 = false
        if case .angle3 = direction { isAngle3 = true }
        var isPar = false
        if case .par = direction { isPar = true }
        if !isAngle3, onCurve == nil, !exists(parent) {
            let (refValue, theta) = try thetaOfUnchecked(direction)
            let refId = try linear(refValue)
            if let refObject = c.object(refId), case let .straight(ga, gb, ext)? = curveGeom(refObject, res) {
                if let shape, length == nil, !isPar, shape != .line { return try crossing(parent, name, refId, theta, shape) }
                if prior(parent) == nil {
                    let t = project(.straight(a: ga, b: gb, ext: ext), spot())
                    let foot = Vec(x: ga.x + t * (gb.x - ga.x), y: ga.y + t * (gb.y - ga.y))
                    let pos = isPar ? polar(foot, spacing, angleOf(ga, gb) - .pi / 2)
                        : polar(foot, (length ?? defaultLength) / 2, angleOf(ga, gb) + theta + .pi)
                    c.addFreePoint(reserve(pos), name: parent)
                }
            }
        }

        let pid = try point(parent)
        let ref: Id
        var offsets: [Double]
        if case let .angle3(a, deg) = direction {
            try checkedAngle(deg)
            ref = linearThrough(pid, try point(a))
            // Measured from the ray parent → a.
            let base = c.object(ref).flatMap(ends)?.a == pid ? 0 : Double.pi
            offsets = [base + deg * degrees, base - deg * degrees]
        } else {
            let (refValue, theta) = try thetaOf(direction)
            ref = try linear(refValue)
            offsets = [theta, theta + .pi]
            // Along a line from its end b: towards a.
            if along != nil, c.object(ref).flatMap(ends)?.b == pid { offsets.reverse() }
        }
        let from = try posOf(pid)
        guard let refObject = c.object(ref), case let .straight(ga, gb, _)? = curveGeom(refObject, res) else { throw TypingFailure(.cannotRotate) }
        let refDir = angleOf(ga, gb)
        let priorPos = prior(name)
        // The side the point was on before an edit, otherwise the first candidate.
        func score(_ offset: Double, _ p: Vec?) -> Double {
            guard let priorPos else { return 0 }
            if let p { return dist(p, priorPos) }
            return abs(wrapAngle(refDir + offset - angleOf(from, priorPos)))
        }

        var curveTarget: OnCurve?
        var offset = offsets[0]
        if let target = onCurve {
            let cid = try curve(target)
            let g = c.object(cid).flatMap { curveGeom($0, res) }
            var best: (offset: Double, index: Int, s: Double)?
            for o in offsets {
                guard let g else { continue }
                let ray = CurveGeom.straight(a: from, b: polar(from, 1, refDir + o), ext: .ray)
                for (index, p) in intersect(ray, g).enumerated() {
                    guard let p else { continue }
                    let s = score(o, p)
                    if best == nil || s < best!.s { best = (o, index, s) }
                }
            }
            guard let best else { throw TypingFailure(.noIntersection) }
            offset = best.offset
            curveTarget = OnCurve(id: cid, index: best.index)
        } else if priorPos != nil {
            offset = offsets.dropFirst().reduce(offsets[0]) { a, b in score(b, nil) < score(a, nil) ? b : a }
        }
        let distance = length ?? priorPos.map { max(0.01, dist(from, $0)) } ?? defaultLength
        let id = c.addDirectionPoint(parent: pid, ref: ref, offset: offset, distance: distance, lengthLocked: length != nil,
                                     onCurve: curveTarget, name: name)
        main = try shape.map { try join(pid, id, $0) } ?? id
    }

    private func thetaOf(_ d: Direction) throws -> (Ref, Double) {
        if case .angle2(_, let deg) = d { try checkedAngle(deg) }
        return try thetaOfUnchecked(d)
    }

    private func thetaOfUnchecked(_ d: Direction) throws -> (Ref, Double) {
        switch d {
        case .perp(let r): (r, .pi / 2)
        case .par(let r): (r, 0)
        case let .angle2(r, deg): (r, deg * degrees)
        case .angle3: throw TypingFailure(.unknown)
        }
    }

    /// Segment / ray AB turning about a hidden point X on line `ref`, with A and B on either side of X.
    func crossing(_ aName: String, _ bName: String, _ ref: Id, _ theta: Double, _ shape: NamedShape) throws {
        guard let refObject = c.object(ref), let g = curveGeom(refObject, res), case let .straight(ga, gb, _) = g else { throw TypingFailure(.cannotRotate) }
        let pa = prior(aName)
        let pb = prior(bName)
        let x = c.addPointOn(ref, t: project(g, pa ?? spot()), name: "")
        c.hidePoint(x)
        let foot = try posOf(x)
        // B's side of p: where it was before an edit, otherwise the first one.
        let flip = pb.map { abs(wrapAngle(angleOf(ga, gb) + theta - angleOf(foot, $0))) > .pi / 2 ? Double.pi : 0 } ?? 0
        func arm(_ p: Vec?) -> Double { p.map { max(0.01, dist(foot, $0)) } ?? defaultLength / 2 }
        let a = c.addDirectionPoint(parent: x, ref: ref, offset: theta + flip + .pi, distance: arm(pa), lengthLocked: false, name: aName)
        let b = c.addDirectionPoint(parent: x, ref: ref, offset: theta + flip, distance: arm(pb), lengthLocked: false, name: bName)
        main = try join(a, b, shape)
    }

    /// Segment AB of length `d` with its midpoint M: both halves are locked to d / 2, on either side of M.
    func halves(_ mName: String, _ aName: String, _ bName: String, _ ref: Id, _ theta: Double, _ d: Double) throws {
        let m = try point(mName)
        guard let refObject = c.object(ref), case let .straight(ga, gb, _)? = curveGeom(refObject, res) else { throw TypingFailure(.cannotRotate) }
        let at = try posOf(m)
        // B's side: where it was before an edit, otherwise the first one.
        let flip = prior(bName).map { abs(wrapAngle(angleOf(ga, gb) + theta - angleOf(at, $0))) > .pi / 2 ? Double.pi : 0 } ?? 0
        let a = c.addDirectionPoint(parent: m, ref: ref, offset: theta + flip + .pi, distance: d / 2, lengthLocked: true, name: aName)
        let b = c.addDirectionPoint(parent: m, ref: ref, offset: theta + flip, distance: d / 2, lengthLocked: true, name: bName)
        main = try join(a, b, .segment)
    }

    /// Triangle ABC or polygon ABCD…: its sides, the closing one last.
    func polygon(_ names: [String]) throws {
        let ids = try names.map(point)
        if Set(ids).count < ids.count { throw TypingFailure(.unknown) }
        for (i, id) in ids.enumerated() {
            main = try join(id, ids[(i + 1) % ids.count], .segment)
        }
    }

    func checkedAngle(_ deg: Double) throws {
        if !(deg > 0 && deg < 180) { throw TypingFailure(.angle) }
    }
}

extension Construction {
    /// Applies a typed step to the construction, appending what it creates.
    public func applyStep(_ text: String, _ ctx: TypingContext) -> Result<TypingResult, TypingFailure> {
        guard let statement = parseStep(text) else { return .failure(TypingFailure(.unknown)) }
        let b = Builder(self, ctx)
        do {
            try b.run(statement)
        } catch let failure as TypingFailure {
            return .failure(failure)
        } catch {
            return .failure(TypingFailure(.unknown))
        }
        // The exercise can't be changed by a typed step.
        if touchesExercise(after: b.c) { return .failure(TypingFailure(.exerciseLocked)) }
        return .success(TypingResult(construction: b.c, select: b.main))
    }

    /// A new step typed in a row inserted after object position `index` (default: at the end).
    public func insertStep(_ text: String, _ ctx: TypingContext, index: Int? = nil) -> Result<TypingResult, TypingFailure> {
        let at = index ?? objects.count
        let result = applyStep(text, ctx)
        guard case .success(let r) = result, at < objects.count else { return result }
        func isNew(_ o: GeoObject) -> Bool { numericId(o.id) >= nextId }
        let old = r.construction.objects.filter { !isNew($0) }
        let made = r.construction.objects.filter(isNew)
        guard let ordered = toposort(Array(old[..<at]) + made + Array(old[at...])) else { return .failure(TypingFailure(.breaks)) }
        var placed = r.construction
        placed.objects = ordered
        return .success(TypingResult(construction: placed, select: r.select))
    }

    /// Replaces the objects of one protocol step by what `text` describes. Objects that come back under
    /// the same name (or the step's main object) keep their ids. Empty text deletes the step.
    public func editStep(_ step: ProtocolStep, _ text: String, _ ctx: TypingContext) -> Result<TypingResult, TypingFailure> {
        if step.objects.contains(where: isExercise) { return .failure(TypingFailure(.exerciseLocked)) }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var next = self
            next.removeKeepingPoints(step.objects)
            return .success(TypingResult(construction: next, select: nil))
        }
        let own = Set(step.objects)
        let resolved = resolve()
        var prior = ctx.prior
        for o in objects where own.contains(o.id) && o.isPoint {
            if let name = o.name, !name.isEmpty, let pos = resolved[o.id] { prior[name] = pos }
        }
        let index = objects.firstIndex { own.contains($0.id) } ?? -1
        var without = self
        without.objects = objects.filter { !own.contains($0.id) }
        let result = without.applyStep(text, TypingContext(center: ctx.center, prior: prior))
        guard case .success(let r) = result else { return result }

        func isNew(_ o: GeoObject) -> Bool { numericId(o.id) >= nextId }
        let made = r.construction.objects.filter(isNew)
        let oldOwn = objects.filter { own.contains($0.id) }
        var map: [Id: Id] = [:]
        var claimed = Set<Id>()
        func link(_ n: GeoObject, _ o: GeoObject) {
            map[n.id] = o.id
            claimed.insert(o.id)
        }
        // 1. Same name and the same sort of object.
        for n in made {
            guard let name = n.name, !name.isEmpty else { continue }
            if let o = oldOwn.first(where: { !claimed.contains($0.id) && $0.name == name && category($0) == category(n) }) { link(n, o) }
        }
        // 2. The step's main object (renamed, or redefined).
        if let mainOld = object(step.objectId), let mainNew = made.first(where: { $0.id == r.select }),
           map[mainNew.id] == nil, !claimed.contains(mainOld.id), category(mainOld) == category(mainNew) {
            link(mainNew, mainOld)
        }
        // 3. Unnamed objects with the same ends (segments, rays, hidden line points by order).
        func f(_ id: Id) -> Id { map[id] ?? id }
        func kindKey(_ o: GeoObject) -> String { String(String(describing: o).prefix { $0 != "(" }) }
        for n in made where map[n.id] == nil {
            let o = oldOwn.first { q in
                if claimed.contains(q.id) || kindKey(q) != kindKey(n) { return false }
                if let qe = ends(q), let ne = ends(n) {
                    return (qe.a == f(ne.a) && qe.b == f(ne.b)) || (qe.a == f(ne.b) && qe.b == f(ne.a))
                }
                return q.isHidden && n.isHidden
            }
            if let o { link(n, o) }
        }

        let remapped = r.construction.objects.map { o -> GeoObject in
            let moved = remap(o, f)
            return map[o.id].map { withId(moved, $0) } ?? moved
        }
        // Everything outside the step must still find what it was built on.
        let ids = Set(remapped.map(\.id))
        if remapped.contains(where: { o in parentsOf(o).contains { !ids.contains($0) } }) { return .failure(TypingFailure(.breaks)) }
        let madeIds = Set(made.map { f($0.id) })
        let old = remapped.filter { !madeIds.contains($0.id) }
        let fresh = remapped.filter { madeIds.contains($0.id) }
        let at = max(0, min(index, old.count))
        guard let ordered = toposort(Array(old[..<at]) + fresh + Array(old[at...])) else { return .failure(TypingFailure(.breaks)) }
        var next = r.construction
        next.objects = ordered
        next.styles = styles.filter { ids.contains($0.key) }
        return .success(TypingResult(construction: next, select: r.select.map(f)))
    }
}

// MARK: Autocorrect and suggestions

private let digitSubscripts = Array("₀₁₂₃₄₅₆₇₈₉")

/// Live autocorrect for typed steps: plain-keyboard spellings become the notation's symbols.
/// The caret stays where it was.
public func autocorrect(_ input: String, caret: Int) -> (text: String, caret: Int) {
    // ICU regular expressions need a bounded look-behind.
    let name = "[A-Za-z][₀-₉]{0,8}'{0,8}"
    let rules: [(pattern: String, replace: (String) -> String)] = [
        ("<->", { _ in "↔" }),
        ("->", { _ in "↦" }),
        ("_\\|_", { _ in "⊥" }),
        ("\\^", { _ in "∧" }),
        // "p || q": not the bars of |AB|.
        ("(?<=\\s)\\|\\|(?=\\s|$)", { _ in "∥" }),
        ("<(?=[A-Za-z(])", { _ in "∠" }),
        ("deg", { _ in "°" }),
        // "C e p", "k n l": a lone e / n between two names.
        ("(?<=\(name) )[eE](?= )", { _ in "∈" }),
        ("(?<=\(name) )n(?= )", { _ in "∩" }),
        // Digits right after a letter are an index: k1 → k₁.
        ("(?<=[A-Za-z₀-₉])[0-9]", { d in String(digitSubscripts[Int(d)!]) }),
    ]
    var text = input as NSString
    var caret = caret
    for rule in rules {
        guard let re = try? NSRegularExpression(pattern: rule.pattern) else { continue }
        let matches = re.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        if matches.isEmpty { continue }
        let out = NSMutableString()
        var last = 0
        var shift = 0
        for m in matches {
            let replacement = rule.replace(text.substring(with: m.range))
            out.append(text.substring(with: NSRange(location: last, length: m.range.location - last)))
            out.append(replacement)
            last = m.range.location + m.range.length
            if last <= caret { shift += (replacement as NSString).length - m.range.length }
        }
        out.append(text.substring(from: last))
        text = out
        caret += shift
    }
    return (text as String, caret)
}

public struct Suggestions: Equatable, Sendable {
    /// The typed word spans text[from, to).
    public let from: Int
    public let to: Int
    public let items: [String]
}

/// Existing names that start with the word at the caret.
public func suggest(_ text: String, caret: Int, names: [String]) -> Suggestions? {
    let ns = text as NSString
    if caret < ns.length, let c = ns.substring(with: NSRange(location: caret, length: 1)).first,
       (c.isASCII && (c.isLetter || c.isNumber)) || digitSubscripts.contains(c) || c == "'" { return nil }
    let head = ns.substring(to: caret) as NSString
    guard let re = try? NSRegularExpression(pattern: "([A-Za-z][₀-₉0-9]*'*)$"),
          let m = re.firstMatch(in: head as String, range: NSRange(location: 0, length: head.length)) else { return nil }
    let raw = head.substring(with: m.range(at: 1))
    let word = String(raw.map { c in c.isASCII && c.isNumber ? digitSubscripts[c.wholeNumberValue!] : c })
    let from = caret - (raw as NSString).length
    // A lowercase letter can stand for a point (it is read as a capital there).
    func matches(_ n: String) -> Bool {
        if n.hasPrefix(word) { return true }
        guard let first = word.first, first.isLowercase else { return false }
        return n.hasPrefix(first.uppercased() + word.dropFirst())
    }
    let items = Array(Set(names)).filter { !$0.isEmpty && matches($0) }
        .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    if items.isEmpty || (items.count == 1 && items[0] == word) { return nil }
    return Suggestions(from: from, to: caret, items: Array(items.prefix(8)))
}
