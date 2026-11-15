import Foundation

// Where graphs cross each other or the axes. Each pair of functions is sampled across the view; a
// sign change of f − g is narrowed down by bisection, and a dip of |f − g| down to zero (a tangent
// touching a parabola) by a ternary search. A port of src/engine/graph/intersect.ts, circle.ts (the
// crossings of circles) and crossings.ts.

private func sign(_ v: Double) -> Double { v > 0 ? 1 : v < 0 ? -1 : v }

/// Crossings of every pair of functions with x in [xMin, xMax], about `samples` probes per pair.
public func intersections(_ fns: [Fn], _ xMin: Double, _ xMax: Double, samples: Double) -> [Vec] {
    var out: [Vec] = []
    let n = max(2, Int(samples.rounded(.up)))
    let dx = (xMax - xMin) / Double(n)
    let xs = (0...n).map { xMin + Double($0) * dx }
    let values = fns.map { f in xs.map(f) }
    for i in fns.indices {
        for j in fns.indices where j > i {
            let f = fns[i], g = fns[j]
            let h: Fn = { f($0) - g($0) }
            let hs = xs.indices.map { values[i][$0] - values[j][$0] }
            // The same graph twice (y = 2x and y = x + x, or one restricted to a piece of it) touches
            // everywhere they're both drawn, not at points.
            if hs.allSatisfy({ !(abs($0) >= 1e-12) }) { continue }
            /// Keeps x if f and g really meet there (not a jump of tan x or 1/x across zero). A touch is
            /// only found to about 1e-8, so it may be rounded off more (`slack`).
            func accept(_ x: Double, _ slack: Double = 1e-12) {
                let y = f(x)
                let d = abs(h(x))
                if !y.isFinite || !(d <= 1e-7 * (1 + abs(y))) { return }
                if !out.contains(where: { abs($0.x - x) < dx / 4 && abs($0.y - y) < 1e-6 * (1 + abs(y)) }) {
                    out.append(Vec(x: clean(x, slack), y: clean(y, slack)))
                }
            }
            for k in 0...n {
                let a = hs[k]
                if !a.isFinite { continue }
                if a == 0 {
                    accept(xs[k])
                    continue
                }
                let b = k < n ? hs[k + 1] : .nan
                if k < n && b.isFinite && b != 0 && sign(a) != sign(b) {
                    accept(bisect(h, xs[k], xs[k + 1]))
                }
                // A local dip of |h| without a sign change: maybe a touch.
                if k > 0 && k < n {
                    let prev = hs[k - 1]
                    if prev.isFinite && b.isFinite && sign(prev) == sign(a) && sign(b) == sign(a)
                        && abs(a) <= abs(prev) && abs(a) <= abs(b) {
                        accept(dip(h, xs[k - 1], xs[k + 1], sign(a)), 1e-7)
                    }
                }
            }
        }
    }
    return out
}

public func bisect(_ h: Fn, _ a0: Double, _ b0: Double) -> Double {
    var a = a0, b = b0
    var ha = h(a)
    var i = 0
    while i < 80 && a != b {
        let m = (a + b) / 2
        if m == a || m == b { break }
        let hm = h(m)
        if hm == 0 { return m }
        if sign(hm) == sign(ha) {
            a = m
            ha = hm
        } else {
            b = m
        }
        i += 1
    }
    return abs(h(a)) < abs(h(b)) ? a : b
}

/// The x in [a, b] where sign · h is smallest.
public func dip(_ h: Fn, _ a0: Double, _ b0: Double, _ sign: Double) -> Double {
    var a = a0, b = b0
    for _ in 0..<100 {
        let m1 = a + (b - a) / 3
        let m2 = b - (b - a) / 3
        if sign * h(m1) < sign * h(m2) { b = m2 } else { a = m1 }
    }
    return (a + b) / 2
}

/// Float noise off a round number (1.9999999999999998, 3.0000000071 from a touch) goes.
public func clean(_ v: Double, _ slack: Double) -> Double {
    let r = jsToFixedNumber(v, 6)
    return abs(v - r) < slack * (1 + abs(v)) ? r : v
}

/// The points a click snaps to: where graphs cross each other, the x-axis (roots) and the y-axis
/// (where x = 0), for x in [xMin, xMax].
public func snapPoints(_ fns: [Fn], _ xMin: Double, _ xMax: Double, samples: Double) -> [Vec] {
    var out = intersections(fns + [{ _ in 0 }], xMin, xMax, samples: samples)
    if xMin > 0 || xMax < 0 { return out }
    for f in fns {
        let y = clean(f(0), 1e-12)
        if y.isFinite && !out.contains(where: { $0.x == 0 && abs($0.y - y) < 1e-9 }) { out.append(Vec(x: 0, y: y)) }
    }
    return out
}

/// Where h changes sign (or is 0) for t in [a, b], about `samples` probes; `exact` keeps a root (a jump of tan isn't one).
private func signChanges(_ h: Fn, _ a: Double, _ b: Double, _ samples: Double, _ exact: (Double) -> Bool) -> [Double] {
    let n = max(2, Int(samples.rounded(.up)))
    let dt = (b - a) / Double(n)
    var out: [Double] = []
    var prev = h(a)
    for k in 1...n {
        let t0 = a + Double(k - 1) * dt
        let t1 = a + Double(k) * dt
        let cur = h(t1)
        if prev == 0 && exact(t0) {
            out.append(t0)
        } else if prev.isFinite && cur.isFinite && cur != 0 && sign(prev) != sign(cur) {
            let t = bisect(h, t0, t1)
            if exact(t) { out.append(t) }
        }
        prev = cur
    }
    return out
}

private func isNear(_ out: [Vec], _ p: Vec) -> Bool {
    out.contains { abs($0.x - p.x) < 1e-6 * (1 + abs(p.x)) && abs($0.y - p.y) < 1e-6 * (1 + abs(p.y)) }
}

/// The snap points of the sideways rows x = g(y), for y in [yMin, yMax]: where they cross each
/// other, (`axes`) the axes, the functions y = f(x) and the circles (only their arcs that are drawn).
public func sidewaysCrossings(_ gs: [Fn], _ fns: [Fn], _ circles: [GraphCircle], _ yMin: Double, _ yMax: Double,
                              samples: Double, axes: Bool = true) -> [Vec] {
    // Each other and the y-axis (g = 0): the same as functions of x, with the axes swapped.
    var out = intersections(axes ? gs + [{ _ in 0 }] : gs, yMin, yMax, samples: samples).map { Vec(x: $0.y, y: $0.x) }
    func add(_ x: Double, _ y: Double) {
        let p = Vec(x: clean(x, 1e-12), y: clean(y, 1e-12))
        if p.x.isFinite && p.y.isFinite && !isNear(out, p) { out.append(p) }
    }
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-7 * (1 + abs(a) + abs(b)) }
    for g in gs {
        if axes && yMin <= 0 && yMax >= 0 { add(g(0), 0) }
        for f in fns {
            let h: Fn = { f(g($0)) - $0 }
            for y in signChanges(h, yMin, yMax, samples, { near(f(g($0)), $0) }) { add(g(y), y) }
        }
        for c in circles {
            let h: Fn = { y in (g(y) - c.m) * (g(y) - c.m) + (y - c.n) * (y - c.n) - c.r * c.r }
            let onIt: (Double) -> Bool = { y in
                near(hypot(g(y) - c.m, y - c.n), c.r) && (c.inside.map { $0(g(y), y) } ?? true)
            }
            for y in signChanges(h, yMin, yMax, samples, onIt) { add(g(y), y) }
        }
    }
    return out
}

// MARK: Circles

private func addRounded(_ out: inout [Vec], _ p: Vec) {
    let q = Vec(x: clean(p.x, 1e-12), y: clean(p.y, 1e-12))
    if q.x.isFinite && q.y.isFinite && !isNear(out, q) { out.append(q) }
}

/// Where two circles cross (a touch counts once).
private func circleCircle(_ a: GraphCircle, _ b: GraphCircle, _ out: inout [Vec]) {
    let dx = b.m - a.m, dy = b.n - a.n
    let d = hypot(dx, dy)
    if d < graphEps { return }
    let along = (a.r * a.r - b.r * b.r + d * d) / (2 * d)
    let h2 = a.r * a.r - along * along
    if h2 < -graphEps * (1 + a.r * a.r) { return }
    let h = max(0, h2).squareRoot()
    let base = Vec(x: a.m + along * dx / d, y: a.n + along * dy / d)
    addRounded(&out, Vec(x: base.x - h * dy / d, y: base.y + h * dx / d))
    addRounded(&out, Vec(x: base.x + h * dy / d, y: base.y - h * dx / d))
}

/// Where a circle crosses the axes.
private func circleAxes(_ c: GraphCircle, _ out: inout [Vec]) {
    for (along, across, onX) in [(c.m, c.n, true), (c.n, c.m, false)] {
        let h2 = c.r * c.r - across * across
        if h2 < -graphEps * (1 + c.r * c.r) { continue }
        let h = max(0, h2).squareRoot()
        for t in [along - h, along + h] { addRounded(&out, onX ? Vec(x: t, y: 0) : Vec(x: 0, y: t)) }
    }
}

/// Where a circle crosses y = f(x): going round the circle by angle, h(θ) = n + r·sin θ − f(m + r·cos θ)
/// changes sign at a crossing, and dips to zero at a touch — no trouble with the steep ends.
private func circleFunction(_ c: GraphCircle, _ f: @escaping Fn, _ steps: Int, _ out: inout [Vec]) {
    func at(_ t: Double) -> Vec { Vec(x: c.m + c.r * cos(t), y: c.n + c.r * sin(t)) }
    let h: Fn = { t in
        let p = at(t)
        return p.y - f(p.x)
    }
    func accept(_ t: Double, _ out: inout [Vec]) {
        let p = at(t)
        let y = f(p.x)
        if y.isFinite && abs(p.y - y) <= 1e-7 * (1 + abs(y)) { addRounded(&out, p) }
    }
    let dt = 2 * Double.pi / Double(steps)
    let hs = (0...steps).map { h(Double($0) * dt) }
    for k in 0..<steps {
        let a = hs[k], b = hs[k + 1]
        if !a.isFinite { continue }
        if a == 0 { accept(Double(k) * dt, &out) }
        else if b.isFinite && b != 0 && sign(a) != sign(b) { accept(bisect(h, Double(k) * dt, Double(k + 1) * dt), &out) }
        // A local dip of |h| without a sign change: maybe a touch (the previous sample wraps round).
        let prev = hs[k == 0 ? steps - 1 : k - 1]
        if prev.isFinite && b.isFinite && sign(prev) == sign(a) && sign(b) == sign(a) && abs(a) <= abs(prev) && abs(a) <= abs(b) {
            let t = dip(h, Double(k - 1) * dt, Double(k + 1) * dt, sign(a))
            let p = at(t)
            let y = f(p.x)
            if y.isFinite && abs(p.y - y) <= 1e-6 * (1 + abs(y)) { addRounded(&out, Vec(x: clean(p.x, 1e-7), y: clean(p.y, 1e-7))) }
        }
    }
}

/// Where the circles cross the functions, each other and (`axes`) the axes. `perUnit`: screen pixels
/// per unit, so that each circle is probed about once a pixel round its edge.
public func circleCrossings(_ circles: [GraphCircle], _ fns: [Fn], perUnit: Double, axes: Bool = true) -> [Vec] {
    var out: [Vec] = []
    /// Keeps the points found on the arcs that are drawn (a restricted circle is only partly there).
    func keep(_ on: [GraphCircle], _ find: (inout [Vec]) -> Void) {
        var found: [Vec] = []
        find(&found)
        for p in found where on.allSatisfy({ $0.inside?(p.x, p.y) ?? true }) { addRounded(&out, p) }
    }
    for (i, c) in circles.enumerated() {
        if axes { keep([c]) { circleAxes(c, &$0) } }
        for d in circles.dropFirst(i + 1) { keep([c, d]) { circleCircle(c, d, &$0) } }
        let steps = min(8192, max(64, Int((2 * Double.pi * c.r * perUnit).rounded(.up))))
        for f in fns { keep([c]) { circleFunction(c, f, steps, &$0) } }
    }
    return out
}

// MARK: Two graphs

/// Where two graphs cross each other (not the axes), inside the view, left to right: the points shown
/// on a selected graph, and the ones the Intersect tool keeps in a row. `scale`: pixels per unit.
public func crossingsBetween(_ a: Drawn, _ b: Drawn, _ view: GraphView, scale: Double) -> [Vec] {
    let width = (view.xMax - view.xMin) * scale
    let height = (view.yMax - view.yMin) * scale
    let fns = [a, b].compactMap(\.fn)
    let circles = [a, b].compactMap(\.circle)
    let sideways = [a, b].compactMap(\.fnOfY)
    let found = !sideways.isEmpty ? sidewaysCrossings(sideways, fns, circles, view.yMin, view.yMax, samples: height, axes: false)
        : !circles.isEmpty ? circleCrossings(circles, fns, perUnit: scale, axes: false)
        : intersections(fns, view.xMin, view.xMax, samples: width)
    return found
        .filter { $0.x >= view.xMin && $0.x <= view.xMax && $0.y >= view.yMin && $0.y <= view.yMax }
        .sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
}
