import Foundation

// Samples y = fn(x) into polylines for drawing. About one sample per screen pixel, with extra
// samples where the curve is steep. The polyline breaks where fn is undefined (√ of a negative,
// ln 0) and at jumps that don't close up when sampled finer (tan x, 1/x), so no vertical
// "asymptote" lines get drawn. A port of the web app's src/engine/graph/sample.ts.

/// The part of the plane in view.
public struct GraphView: Equatable, Sendable {
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double

    public init(xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
    }
}

private let maxDepth = 10

/// `pixels`: the screen width, which sets the sampling step.
public func sampleCurve(_ fn: Fn, _ w: GraphView, pixels: Double) -> [[Vec]] {
    let n = max(2, Int(pixels.rounded(.up)))
    let dx = (w.xMax - w.xMin) / Double(n)
    let range = w.yMax - w.yMin
    /// Steps smaller than this (a pixel or so) need no refining.
    let fine = range / max(1, pixels) * 1.5
    // Off-screen values are clamped so that the drawing keeps sane coordinates.
    let lo = w.yMin - range * 2
    let hi = w.yMax + range * 2
    func visible(_ y: Double) -> Bool { y >= lo && y <= hi }

    var lines: [[Vec]] = []
    var line: [Vec] = []
    func breakLine() {
        if line.count > 1 { lines.append(line) }
        line = []
    }
    func add(_ x: Double, _ y: Double) { line.append(Vec(x: x, y: min(hi, max(lo, y)))) }
    func sign(_ v: Double) -> Double { v > 0 ? 1 : v < 0 ? -1 : v }

    /// Adds the points strictly between (x0, y0) and (x1, y1), breaking the line at a jump.
    func refine(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ depth: Int) {
        let dy = abs(y1 - y0)
        if dy <= fine || (!visible(y0) && !visible(y1) && sign(y0 - w.yMin) == sign(y1 - w.yMin)) { return }
        if depth >= maxDepth {
            // Still a big step after many halvings: a jump (tan x at π/2), not a steep piece.
            if dy > range { breakLine() }
            return
        }
        let xm = (x0 + x1) / 2
        let ym = fn(xm)
        if !ym.isFinite {
            // Undefined in between (ln |x| at 0): end the line there and start again after the gap.
            edgeEnd(fn, x0, xm, add)
            breakLine()
            edge(fn, xm, x1, add)
            return
        }
        refine(x0, y0, xm, ym, depth + 1)
        add(xm, ym)
        refine(xm, ym, x1, y1, depth + 1)
    }

    var px = w.xMin
    var py = fn(px)
    if py.isFinite { add(px, py) }
    for i in 1...n {
        let x = w.xMin + Double(i) * dx
        let y = fn(x)
        if y.isFinite {
            if py.isFinite { refine(px, py, x, y, 0) }
            // The curve starts between the samples (√x at 0): begin where it does.
            else { edge(fn, px, x, add) }
            add(x, y)
        } else {
            // …and it ends between them: walk up to where it stops.
            if py.isFinite { edgeEnd(fn, px, x, add) }
            breakLine()
        }
        px = x
        py = y
    }
    breakLine()
    return lines
}

/// Where fn becomes defined between `a` (undefined) and `b` (defined): adds that first point.
private func edge(_ fn: Fn, _ a0: Double, _ b0: Double, _ add: (Double, Double) -> Void) {
    var a = a0, b = b0
    for _ in 0..<30 {
        let m = (a + b) / 2
        if fn(m).isFinite { b = m } else { a = m }
    }
    add(b, fn(b))
}

/// Where fn stops being defined between `a` (defined) and `b` (undefined): adds that last point.
private func edgeEnd(_ fn: Fn, _ a0: Double, _ b0: Double, _ add: (Double, Double) -> Void) {
    var a = a0, b = b0
    for _ in 0..<30 {
        let m = (a + b) / 2
        if fn(m).isFinite { a = m } else { b = m }
    }
    add(a, fn(a))
}

/// The arcs of a restricted circle, {y ≥ 100} or {0 ≤ x ≤ 5}: gone round by angle about every two
/// pixels (`perUnit`: pixels per unit), each arc ending exactly where the restriction stops holding.
public func sampleArc(_ c: GraphCircle, perUnit: Double) -> [[Vec]] {
    let inside = c.inside ?? { _, _ in true }
    func at(_ t: Double) -> Vec { Vec(x: c.m + c.r * cos(t), y: c.n + c.r * sin(t)) }
    func holds(_ t: Double) -> Bool {
        let p = at(t)
        return inside(p.x, p.y)
    }
    /// Where the restriction flips between angles a (holds: `from`) and b.
    func flip(_ a0: Double, _ b0: Double, _ from: Bool) -> Double {
        var a = a0, b = b0
        for _ in 0..<40 {
            let m = (a + b) / 2
            if holds(m) == from { a = m } else { b = m }
        }
        return from ? a : b
    }
    let steps = min(8192, max(64, Int((Double.pi * c.r * perUnit).rounded(.up))))
    let dt = 2 * Double.pi / Double(steps)
    // Start from an angle that is cut away, so that no arc is split where the round begins.
    guard let start = (0..<steps).lazy.map({ Double($0) * dt }).first(where: { !holds($0) }) else {
        return [(0...steps).map { at(Double($0) * dt) }]
    }
    var lines: [[Vec]] = []
    var line: [Vec] = []
    var prev = false
    for k in 1...steps {
        let t = start + Double(k) * dt
        let now = holds(t)
        if now && !prev { line.append(at(flip(t - dt, t, false))) }
        if !now && prev {
            line.append(at(flip(t - dt, t, true)))
            if line.count > 1 { lines.append(line) }
            line = []
        }
        if now { line.append(at(t)) }
        prev = now
    }
    return lines
}

/// The polylines a row draws in the view: y = f(x) across it, x = g(y) up it (sampled with the axes
/// swapped), a circle round (only its arcs when restricted), any other curve where its equation holds;
/// a shaded row, its borders. `scale`: pixels per unit.
public func drawnLines(_ g: Drawn, _ view: GraphView, scale: Double) -> [[Vec]] {
    let width = (view.xMax - view.xMin) * scale
    let height = (view.yMax - view.yMin) * scale
    if let region = g.region { return region.edges.flatMap { drawnLines($0.drawn, view, scale: scale) } }
    if let implicit = g.implicit { return contour(implicit.f, implicit.inside, view, scale: scale) }
    if let circle = g.circle { return sampleArc(circle, perUnit: scale) }
    if let fnOfY = g.fnOfY {
        let swapped = GraphView(xMin: view.yMin, xMax: view.yMax, yMin: view.xMin, yMax: view.xMax)
        return sampleCurve(fnOfY, swapped, pixels: height).map { $0.map { Vec(x: $0.y, y: $0.x) } }
    }
    return g.fn.map { sampleCurve($0, view, pixels: width) } ?? []
}
