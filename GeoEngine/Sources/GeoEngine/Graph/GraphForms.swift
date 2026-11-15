import Foundation

// The functions placed from the sidebar, written the way it's done in school: the parabola, the
// cubic, sine, cosine and tangent, the hyperbola, the circle and the ellipse through clicked points.
// A port of the web app's quadratic.ts, cubic.ts, trig.ts, hyperbola.ts, circle.ts and ellipse.ts.

/// Float noise from the grid (0.30000000000000004) counts as zero.
public func cleanZero(_ v: Double) -> Double { abs(v) < graphEps ? 0 : v }

/// The leading coefficient written before a bracket or x: "" for 1, "-" for −1, else "1/2", "-3".
private func coef(_ a: Double, _ comma: Bool) -> String {
    (a < 0 ? "-" : "") + (abs(abs(a) - 1) < graphEps ? "" : formatAbs(a, comma: comma))
}

/// A term added on: " + 3", " - 1/2x", or "" when the number is zero.
public func signedTerm(_ v: Double, _ comma: Bool, after: String = "") -> String {
    if v == 0 { return "" }
    let number = !after.isEmpty && abs(abs(v) - 1) < graphEps ? "" : formatAbs(v, comma: comma)
    return " \(v < 0 ? "-" : "+") \(number)\(after)"
}

/// x − r written as a factor: "x" for 0, else "(x - 2)", "(x + 2)" (or y − r).
public func factor(_ r: Double, _ comma: Bool, _ v: String = "x") -> String {
    r == 0 ? v : "(\(v) \(r < 0 ? "+" : "-") \(formatAbs(r, comma: comma)))"
}

private func sameX(_ xs: [Double]) -> Bool {
    for i in xs.indices {
        for j in xs.indices where i < j && abs(xs[i] - xs[j]) < 1e-12 { return true }
    }
    return false
}

// MARK: Parabola

/// The a of the parabola with turning point v through p, or nil (same x, or flat).
public func parabolaThrough(_ v: Vec, _ p: Vec) -> Double? {
    let dx = p.x - v.x
    if abs(dx) < 1e-12 { return nil }
    let a = (p.y - v.y) / (dx * dx)
    return abs(a) < graphEps ? nil : a
}

/// y = a(x − m)^2 + n through the turning point v and p.
public func vertexThrough(_ v: Vec, _ p: Vec, comma: Bool) -> String? {
    guard let a = parabolaThrough(v, p) else { return nil }
    let m = cleanZero(v.x)
    return "y = \(coef(a, comma))\(m == 0 ? "x^2" : "\(factor(m, comma))^2")\(signedTerm(cleanZero(v.y), comma))"
}

/// y = a(x − x₁)(x − x₂), smaller root first; a double root squared.
public func interceptForm(_ a: Double, _ r1: Double, _ r2: Double, comma: Bool) -> String {
    let lo = min(cleanZero(r1), cleanZero(r2)), hi = max(cleanZero(r1), cleanZero(r2))
    let factors = abs(hi - lo) < graphEps ? (lo == 0 ? "x^2" : "\(factor(lo, comma))^2") : factor(lo, comma) + factor(hi, comma)
    return "y = \(coef(a, comma))\(factors)"
}

/// The a of the parabola with roots x₁, x₂ through p, or nil (p on the x-axis or above a root).
public func interceptA(_ x1: Double, _ x2: Double, _ p: Vec) -> Double? {
    let d = (p.x - x1) * (p.x - x2)
    if abs(p.y) < graphEps || abs(d) < 1e-12 { return nil }
    return p.y / d
}

public func interceptThrough(_ r1: Vec, _ r2: Vec, _ p: Vec, comma: Bool) -> String? {
    interceptA(r1.x, r2.x, p).map { interceptForm($0, r1.x, r2.x, comma: comma) }
}

/// a, b, c of y = ax² + bx + c through three points, or nil (two share an x, or on a line).
public func generalCoefficients(_ p1: Vec, _ p2: Vec, _ p3: Vec) -> (a: Double, b: Double, c: Double)? {
    if sameX([p1.x, p2.x, p3.x]) { return nil }
    let d12 = (p2.y - p1.y) / (p2.x - p1.x)
    let d23 = (p3.y - p2.y) / (p3.x - p2.x)
    let a = (d23 - d12) / (p3.x - p1.x)
    if abs(a) < graphEps { return nil }
    let b = d12 - a * (p1.x + p2.x)
    return (a, b, p1.y - a * p1.x * p1.x - b * p1.x)
}

public func generalThrough(_ p1: Vec, _ p2: Vec, _ p3: Vec, comma: Bool) -> String? {
    guard let k = generalCoefficients(p1, p2, p3) else { return nil }
    return "y = \(coef(k.a, comma))x^2\(signedTerm(cleanZero(k.b), comma, after: "x"))\(signedTerm(cleanZero(k.c), comma))"
}

// MARK: Cubic

public func cubicThrough(_ i: Vec, _ p: Vec) -> Double? {
    let dx = p.x - i.x
    if abs(dx) < 1e-12 { return nil }
    let a = (p.y - i.y) / (dx * dx * dx)
    return abs(a) < graphEps ? nil : a
}

/// y = a(x − m)^3 + n through the inflection point i and p.
public func inflectionThrough(_ i: Vec, _ p: Vec, comma: Bool) -> String? {
    guard let a = cubicThrough(i, p) else { return nil }
    let m = cleanZero(i.x)
    return "y = \(coef(a, comma))\(m == 0 ? "x" : factor(m, comma))^3\(signedTerm(cleanZero(i.y), comma))"
}

/// y = a(x − x₁)(x − x₂)(x − x₃), roots from the smallest; a repeated root as a power.
public func cubicInterceptForm(_ a: Double, _ roots: [Double], comma: Bool) -> String {
    var groups: [(r: Double, n: Int)] = []
    for r in roots.map(cleanZero).sorted() {
        if let last = groups.last, abs(r - last.r) < graphEps { groups[groups.count - 1].n += 1 } else { groups.append((r, 1)) }
    }
    return "y = \(coef(a, comma))" + groups.map { factor($0.r, comma) + ($0.n > 1 ? "^\($0.n)" : "") }.joined()
}

public func cubicInterceptA(_ roots: [Double], _ p: Vec) -> Double? {
    let d = roots.reduce(1.0) { $0 * (p.x - $1) }
    if abs(p.y) < graphEps || abs(d) < 1e-12 { return nil }
    return p.y / d
}

public func cubicInterceptThrough(_ roots: [Vec], _ p: Vec, comma: Bool) -> String? {
    let xs = roots.map(\.x)
    return cubicInterceptA(xs, p).map { cubicInterceptForm($0, xs, comma: comma) }
}

/// a, b, c, d of y = ax³ + bx² + cx + d through four points, or nil (two share an x, or a = 0).
public func cubicCoefficients(_ ps: [Vec]) -> (a: Double, b: Double, c: Double, d: Double)? {
    let xs = ps.map(\.x)
    if sameX(xs) { return nil }
    let (x0, x1, x2, x3) = (xs[0], xs[1], xs[2], xs[3])
    let (y0, y1, y2, y3) = (ps[0].y, ps[1].y, ps[2].y, ps[3].y)
    let f01 = (y1 - y0) / (x1 - x0)
    let f12 = (y2 - y1) / (x2 - x1)
    let f23 = (y3 - y2) / (x3 - x2)
    let f012 = (f12 - f01) / (x2 - x0)
    let f123 = (f23 - f12) / (x3 - x1)
    let a = (f123 - f012) / (x3 - x0)
    if abs(a) < graphEps { return nil }
    let b = f012 - a * (x0 + x1 + x2)
    let c = f01 - f012 * (x0 + x1) + a * (x0 * x1 + x0 * x2 + x1 * x2)
    let d = y0 - f01 * x0 + f012 * x0 * x1 - a * x0 * x1 * x2
    return (a, b, c, d)
}

public func cubicGeneralThrough(_ ps: [Vec], comma: Bool) -> String? {
    guard let k = cubicCoefficients(ps) else { return nil }
    return "y = \(coef(k.a, comma))x^3\(signedTerm(cleanZero(k.b), comma, after: "x^2"))\(signedTerm(cleanZero(k.c), comma, after: "x"))\(signedTerm(cleanZero(k.d), comma))"
}

// MARK: Sine, cosine, tangent

public enum TrigFn: String, Sendable {
    case sin, cos, tan
}

/// |v| as a simple multiple of π (π, 2π, π/2, 3π/4), or nil.
public func piFraction(_ v: Double) -> String? {
    let r = abs(v) / .pi
    for q in 1...64 {
        let p = jsRound(r * Double(q))
        if p > 0 && abs(r - p / Double(q)) < 1e-9 { return "\(p == 1 ? "" : jsString(p))π\(q == 1 ? "" : "/\(q)")" }
    }
    return nil
}

private func piAbs(_ v: Double, _ comma: Bool) -> String { piFraction(v) ?? formatAbs(v, comma: comma) }

/// y = a·fn(b(x − c)) + d, with b > 0.
public func trigForm(_ fn: TrigFn, _ a: Double, _ b: Double, _ c: Double, _ d: Double, comma: Bool) -> String {
    let shift = cleanZero(c)
    let x = shift == 0 ? "x" : "x \(shift < 0 ? "+" : "-") \(piAbs(shift, comma))"
    let inner = abs(b - 1) < graphEps ? x : "\(piAbs(b, comma))\(shift == 0 ? "x" : "(\(x))")"
    return "y = \(coef(a, comma))\(fn.rawValue)(\(inner))\(signedTerm(cleanZero(d), comma))"
}

/// The sine through s (its middle line, going up) with the top of the wave at m.
public func sineThrough(_ s: Vec, _ m: Vec, comma: Bool) -> String? {
    let quarter = m.x - s.x
    let a = m.y - s.y
    if abs(quarter) < 1e-12 || abs(a) < graphEps { return nil }
    // The top to the left of s: the wave runs backwards, sin(−t) = −sin t.
    return quarter > 0 ? trigForm(.sin, a, .pi / (2 * quarter), s.x, s.y, comma: comma)
        : trigForm(.sin, -a, .pi / (-2 * quarter), s.x, s.y, comma: comma)
}

/// The cosine starting from its top m, crossing its middle line next at p.
public func cosineThrough(_ m: Vec, _ p: Vec, comma: Bool) -> String? {
    let quarter = abs(p.x - m.x)
    let a = m.y - p.y
    if quarter < 1e-12 || abs(a) < graphEps { return nil }
    return trigForm(.cos, a, .pi / (2 * quarter), m.x, p.y, comma: comma)
}

public func tangentB(_ c: Vec, _ asymptote: Double) -> Double? {
    let half = abs(asymptote - c.x)
    return half < 1e-12 ? nil : .pi / (2 * half)
}

public func tangentA(_ c: Vec, _ b: Double, _ p: Vec) -> Double? {
    let t = Foundation.tan(b * (p.x - c.x))
    if abs(p.x - c.x) < 1e-12 || !t.isFinite || abs(t) > 1e9 || abs(t) < 1e-12 { return nil }
    let a = (p.y - c.y) / t
    return abs(a) < graphEps ? nil : a
}

public func tangentThrough(_ c: Vec, _ asymptote: Double, _ p: Vec, comma: Bool) -> String? {
    guard let b = tangentB(c, asymptote), let a = tangentA(c, b, p) else { return nil }
    return trigForm(.tan, a, b, c.x, c.y, comma: comma)
}

/// The asymptotes x = c + (2k + 1)·half of a tangent, from xMin to xMax (at most `max`).
public func tangentAsymptotes(_ c: Double, _ half: Double, _ xMin: Double, _ xMax: Double, max: Int = 200) -> [Double] {
    let period = 2 * abs(half)
    if period < 1e-12 { return [] }
    var out: [Double] = []
    var k = ((xMin - c - half) / period).rounded(.up)
    while out.count < max {
        let x = c + half + k * period
        if x > xMax { break }
        out.append(x)
        k += 1
    }
    return out
}

/// The π grid: labelled lines a power-of-two multiple of π apart, at least ~70 px; fine lines halfway.
public func piGridStep(_ scale: Double) -> (major: Double, minor: Double) {
    let major = Double.pi * pow(2, log2(70 / (.pi * scale)).rounded(.up))
    return (major, major / 2)
}

/// A π grid label: π/2, −3π/2, 2π (0 as 0).
public func piLabel(_ v: Double) -> String {
    if abs(v) < 1e-12 { return "0" }
    return (v < 0 ? "−" : "") + (piFraction(v) ?? jsString(jsToFixedNumber(abs(v) / .pi, 3)) + "π")
}

// MARK: Hyperbola

/// The k of the hyperbola centred at c through p, or nil when p is on an asymptote.
public func hyperbolaK(_ c: Vec, _ p: Vec) -> Double? {
    let dx = p.x - c.x, dy = p.y - c.y
    if abs(dx) < 1e-12 || abs(dy) < graphEps { return nil }
    return dx * dy
}

/// y = k/(x − m) + n; a fraction k = p/q is written p/(q(x − m)).
public func hyperbolaForm(_ k: Double, _ m: Double, _ n: Double, comma: Bool) -> String {
    let mc = cleanZero(m)
    let den = mc == 0 ? "x" : "x \(mc < 0 ? "+" : "-") \(formatAbs(mc, comma: comma))"
    let abs = formatAbs(k, comma: comma)
    let parts = abs.split(separator: "/", maxSplits: 1).map(String.init)
    let (top, q) = parts.count == 2 ? (parts[0], parts[1]) : (abs, "")
    let bottom = !q.isEmpty ? "(\(q)\(mc == 0 ? "x" : "(\(den))"))" : mc == 0 ? "x" : "(\(den))"
    return "y = \(k < 0 ? "-" : "")\(top)/\(bottom)\(signedTerm(cleanZero(n), comma))"
}

public func hyperbolaThrough(_ c: Vec, _ p: Vec, comma: Bool) -> String? {
    hyperbolaK(c, p).map { hyperbolaForm($0, c.x, c.y, comma: comma) }
}

// MARK: Circle and ellipse

/// r² of the circle centred at c through p, or nil when p is the centre.
public func circleR2(_ c: Vec, _ p: Vec) -> Double? {
    let r2 = (p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y)
    return r2 < graphEps * graphEps ? nil : r2
}

/// r² written as a square: 3^2, 1,5^2, (1/2)^2 when r is a short number, else (√r²)^2.
public func squared(_ r2: Double, comma: Bool) -> String {
    let r = formatAbs(r2.squareRoot(), comma: comma)
    let exact = r.firstMatch(of: #/[.,][0-9]{3,}/#) == nil
    let root = formatAbs(r2, comma: comma)
    if !exact { return "(√\(root.contains("/") ? "(\(root))" : root))^2" }
    return r.contains("/") ? "(\(r))^2" : "\(r)^2"
}

public func circleForm(_ m: Double, _ n: Double, _ r2: Double, comma: Bool) -> String {
    "\(factor(cleanZero(m), comma))^2 + \(factor(cleanZero(n), comma, "y"))^2 = \(squared(r2, comma: comma))"
}

public func circleThrough(_ c: Vec, _ p: Vec, comma: Bool) -> String? {
    circleR2(c, p).map { circleForm(c.x, c.y, $0, comma: comma) }
}

/// (x − m)²/a² + (y − n)²/b² = 1; nil when a or b is zero.
public func ellipseForm(_ m: Double, _ n: Double, _ a: Double, _ b: Double, comma: Bool) -> String? {
    if abs(a) < graphEps || abs(b) < graphEps { return nil }
    return "\(factor(cleanZero(m), comma))^2/\(squared(a * a, comma: comma)) + \(factor(cleanZero(n), comma, "y"))^2/\(squared(b * b, comma: comma)) = 1"
}

/// The ellipse centred at c reaching to `side` (level with c) and `top` (straight above or below c).
public func ellipseThrough(_ c: Vec, _ side: Vec, _ top: Vec, comma: Bool) -> String? {
    ellipseForm(c.x, c.y, side.x - c.x, top.y - c.y, comma: comma)
}
