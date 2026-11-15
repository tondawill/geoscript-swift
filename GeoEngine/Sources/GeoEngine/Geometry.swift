import Foundation

/// Tolerances from the specification (§6).
public let epsWorld = 0.01
public let epsPosPx = 1.5

public func dist(_ a: Vec, _ b: Vec) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}

public func angleOf(_ from: Vec, _ to: Vec) -> Double {
    atan2(to.y - from.y, to.x - from.x)
}

public func polar(_ origin: Vec, _ distance: Double, _ angle: Double) -> Vec {
    Vec(x: origin.x + distance * cos(angle), y: origin.y + distance * sin(angle))
}

public func pointToSegmentDist(_ p: Vec, _ a: Vec, _ b: Vec) -> Double {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lenSq = dx * dx + dy * dy
    if lenSq == 0 { return dist(p, a) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
    return dist(p, Vec(x: a.x + t * dx, y: a.y + t * dy))
}

/// Distance of a point from the circumference of k(S, r).
public func pointToCircleDist(_ p: Vec, _ center: Vec, _ radius: Double) -> Double {
    abs(dist(p, center) - radius)
}

/// Point-on-circle incidence: | ||P − S|| − r | < ε
public func isOnCircle(_ p: Vec, _ center: Vec, _ radius: Double, eps: Double = epsWorld) -> Bool {
    pointToCircleDist(p, center, radius) < eps
}

/// Distance of a point from a ray (origin `a`, through `b`) or, when `infinite`, from the whole line.
public func pointToRayDist(_ p: Vec, _ a: Vec, _ b: Vec, infinite: Bool = false) -> Double {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lenSq = dx * dx + dy * dy
    if lenSq == 0 { return dist(p, a) }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
    if !infinite { t = max(0, t) }
    return dist(p, Vec(x: a.x + t * dx, y: a.y + t * dy))
}

/// Wraps an angle to (−π, π].
public func wrapAngle(_ a: Double) -> Double {
    let twoPi = 2 * Double.pi
    var r = a.truncatingRemainder(dividingBy: twoPi)
    if r > .pi { r -= twoPi }
    if r <= -.pi { r += twoPi }
    return r
}
