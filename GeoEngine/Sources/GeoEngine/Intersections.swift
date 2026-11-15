import Foundation

public enum Extent: Sendable {
    case segment, ray, line

    fileprivate var bounds: ClosedRange<Double> {
        switch self {
        case .segment: 0...1
        case .ray: 0...Double.infinity
        case .line: -Double.infinity...Double.infinity
        }
    }
}

/// Resolved geometry of a curve. Straight objects are parametrised by t (a at 0, b at 1);
/// `ext` says which t are on the object.
public enum CurveGeom: Sendable {
    case straight(a: Vec, b: Vec, ext: Extent)
    case circle(center: Vec, radius: Double)
}

/// Geometry of a curve object, or nil when it is not a curve or a point it needs is undefined.
public func curveGeom(_ o: GeoObject, _ resolved: Resolved) -> CurveGeom? {
    func straight(_ a: Id, _ b: Id, _ ext: Extent) -> CurveGeom? {
        guard let pa = resolved[a], let pb = resolved[b] else { return nil }
        return .straight(a: pa, b: pb, ext: ext)
    }
    switch o {
    case .segment(let s): return straight(s.a, s.b, .segment)
    case .line(let l): return straight(l.a, l.b, .line)
    case .ray(let r): return straight(r.a, r.b, .ray)
    case .circle(let k):
        guard let center = resolved[k.center] else { return nil }
        if let through = k.through {
            guard let p = resolved[through] else { return nil }
            return .circle(center: center, radius: dist(center, p))
        }
        if let span = k.span, span.count == 2 {
            guard let a = resolved[span[0]], let b = resolved[span[1]] else { return nil }
            return .circle(center: center, radius: dist(a, b))
        }
        return .circle(center: center, radius: k.radius)
    default:
        return nil
    }
}

private let tEps = 1e-9

private func within(_ t: Double, _ bounds: ClosedRange<Double>) -> Bool {
    t >= bounds.lowerBound - tEps && t <= bounds.upperBound + tEps
}

/// Intersection of two straight objects (at most one).
private func straightStraight(_ p1: Vec, _ p2: Vec, _ pb: ClosedRange<Double>,
                              _ q1: Vec, _ q2: Vec, _ qb: ClosedRange<Double>) -> [Vec?] {
    let r = Vec(x: p2.x - p1.x, y: p2.y - p1.y)
    let s = Vec(x: q2.x - q1.x, y: q2.y - q1.y)
    let denom = r.x * s.y - r.y * s.x
    if abs(denom) < 1e-12 { return [nil] } // parallel or collinear
    let qp = Vec(x: q1.x - p1.x, y: q1.y - p1.y)
    let t = (qp.x * s.y - qp.y * s.x) / denom
    let u = (qp.x * r.y - qp.y * r.x) / denom
    if !within(t, pb) || !within(u, qb) { return [nil] }
    return [Vec(x: p1.x + t * r.x, y: p1.y + t * r.y)]
}

/// Solutions are indexed by their order along the straight object (index 0 is closer to `a`),
/// so the index stays stable while things move. A solution outside the object is nil.
private func straightCircle(_ a: Vec, _ b: Vec, _ bounds: ClosedRange<Double>,
                            _ center: Vec, _ radius: Double) -> [Vec?] {
    let d = Vec(x: b.x - a.x, y: b.y - a.y)
    let f = Vec(x: a.x - center.x, y: a.y - center.y)
    let qa = d.x * d.x + d.y * d.y
    if qa == 0 { return [nil, nil] }
    let qb = 2 * (f.x * d.x + f.y * d.y)
    let qc = f.x * f.x + f.y * f.y - radius * radius
    let disc = qb * qb - 4 * qa * qc
    if disc < 0 { return [nil, nil] }
    let sq = disc.squareRoot()
    return [(-qb - sq) / (2 * qa), (-qb + sq) / (2 * qa)].map { t in
        within(t, bounds) ? Vec(x: a.x + t * d.x, y: a.y + t * d.y) : nil
    }
}

/// Index 0 lies to the left of the direction c1 → c2, index 1 to the right.
private func circleCircle(_ c1: Vec, _ r1: Double, _ c2: Vec, _ r2: Double) -> [Vec?] {
    let d = dist(c1, c2)
    if d == 0 || d > r1 + r2 || d < abs(r1 - r2) { return [nil, nil] }
    let along = (d * d + r1 * r1 - r2 * r2) / (2 * d)
    let h = max(0, r1 * r1 - along * along).squareRoot()
    let ux = (c2.x - c1.x) / d
    let uy = (c2.y - c1.y) / d
    let mx = c1.x + along * ux
    let my = c1.y + along * uy
    return [Vec(x: mx - h * uy, y: my + h * ux), Vec(x: mx + h * uy, y: my - h * ux)]
}

/// All intersection solutions of two curves, by index. Argument order matters for circle–circle.
public func intersect(_ g1: CurveGeom, _ g2: CurveGeom) -> [Vec?] {
    switch (g1, g2) {
    case let (.straight(a1, b1, e1), .straight(a2, b2, e2)):
        straightStraight(a1, b1, e1.bounds, a2, b2, e2.bounds)
    case let (.straight(a, b, e), .circle(c, r)), let (.circle(c, r), .straight(a, b, e)):
        straightCircle(a, b, e.bounds, c, r)
    case let (.circle(c1, r1), .circle(c2, r2)):
        circleCircle(c1, r1, c2, r2)
    }
}

/// Position of parameter `t` on a curve (straight: 0..1 between its points, circle: angle).
public func pointAt(_ g: CurveGeom, _ t: Double) -> Vec {
    switch g {
    case let .straight(a, b, _): Vec(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
    case let .circle(center, radius): Vec(x: center.x + radius * cos(t), y: center.y + radius * sin(t))
    }
}

/// Parameter of the closest point on the curve to `p`.
public func project(_ g: CurveGeom, _ p: Vec) -> Double {
    switch g {
    case let .straight(a, b, ext):
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return 0 }
        return max(ext.bounds.lowerBound, min(ext.bounds.upperBound, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
    case let .circle(center, _):
        return atan2(p.y - center.y, p.x - center.x)
    }
}
