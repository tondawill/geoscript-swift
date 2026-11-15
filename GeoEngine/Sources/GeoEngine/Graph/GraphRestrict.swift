import Foundation

// Restricting a graph by clicking (src/engine/graph/restrict.ts), the Fill tool's rows (fill.ts) and
// placing a function sideways (sideways.ts). Also finding the graph under the pointer.

/// The row text without its restrictions.
public func withoutWhere(_ text: String) -> String {
    let main = text.firstIndex(of: "{").map { String(text[..<$0]) } ?? text
    return main.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func signed(_ v: Double, _ comma: Bool) -> String {
    (v < -graphEps ? "-" : "") + formatAbs(abs(v) < graphEps ? 0 : v, comma: comma)
}

/// Which variable a piece of the graph is cut along: x for y = …, y for x = …, nil for a circle or another curve (an arc).
public func cutAlongX(_ g: Drawn) -> Bool? {
    g.fn != nil ? true : g.fnOfY != nil ? false : nil
}

/// The row cut to the piece between a and b: {a ≤ x ≤ b} (or y), the smaller end first.
public func intervalText(_ text: String, alongX: Bool, _ a: Vec, _ b: Vec, comma: Bool) -> String {
    let ends = alongX ? [a.x, b.x] : [a.y, b.y]
    let lo = ends.min()!, hi = ends.max()!
    return "\(withoutWhere(text)) {\(signed(lo, comma)) ≤ \(alongX ? "x" : "y") ≤ \(signed(hi, comma))}"
}

/// The circle row cut to the arc from a to b that `keep` is on: the side of the line through a and b
/// where `keep` lies. Nil when a and b are the same point, or `keep` is on that line.
public func arcText(_ text: String, _ a: Vec, _ b: Vec, keep: Vec, comma: Bool) -> String? {
    if hypot(a.x - b.x, a.y - b.y) < graphEps { return nil }
    let condition: String
    if let line = linearThrough(a, b, comma: comma) {
        let m = (b.y - a.y) / (b.x - a.x)
        let side = keep.y - (a.y + m * (keep.x - a.x))
        if abs(side) < graphEps { return nil }
        condition = "y \(side > 0 ? "≥" : "≤") \(line.dropFirst("y = ".count))"
    } else {
        let side = keep.x - a.x
        if abs(side) < graphEps { return nil }
        condition = "x \(side > 0 ? "≥" : "≤") \(signed(a.x, comma))"
    }
    return "\(withoutWhere(text)) {\(condition)}"
}

/// The point of the circle nearest p (the centre itself: the top).
public func nearestOnCircle(_ c: GraphCircle, _ p: Vec) -> Vec {
    let d = hypot(p.x - c.m, p.y - c.n)
    if d < graphEps { return Vec(x: c.m, y: c.n + c.r) }
    return Vec(x: c.m + (p.x - c.m) * c.r / d, y: c.n + (p.y - c.n) * c.r / d)
}

/// Where a click at `snapped` (already pulled to the grid or a crossing) and `raw` (exactly under
/// the pointer) lands on the graph: straight above or below it on y = f(x), level with it on
/// x = g(y). On a circle or another curve: the snapped point if it's on it, else a point of it on a
/// grid line within `reach` of the pointer, else the nearest point. Nil: no graph there.
public func landOn(_ g: Drawn, snapped: Vec, raw: Vec, grid: Double, reach: Double) -> Vec? {
    if let fn = g.fn {
        let y = fn(snapped.x)
        return y.isFinite ? Vec(x: snapped.x, y: y) : nil
    }
    if let fnOfY = g.fnOfY {
        let x = fnOfY(snapped.y)
        return x.isFinite ? Vec(x: x, y: snapped.y) : nil
    }
    if let f = g.implicit?.f {
        if onCurve(f, snapped) { return snapped }
        guard let near = projectOn(f, raw) else { return nil }
        var best = near
        var bestDist = reach
        for alongX in [true, false] {
            let k = jsPrecision12(jsRound((alongX ? near.x : near.y) / grid) * grid)
            let p = crossLine(f, alongX: alongX, k, alongX ? near.y : near.x)
            let d = p.map { hypot($0.x - near.x, $0.y - near.y) } ?? .infinity
            if let p, d < bestDist { (best, bestDist) = (p, d) }
        }
        return best
    }
    guard let c = g.circle else { return nil }
    if abs(hypot(snapped.x - c.m, snapped.y - c.n) - c.r) < 1e-9 * (1 + c.r) { return snapped }
    let near = nearestOnCircle(c, raw)
    var best = near
    var bestDist = reach
    // Grid lines x = k·grid and y = k·grid near the pointer, where they cross the circle.
    for alongX in [true, false] {
        let (at, across) = alongX ? (c.m, c.n) : (c.n, c.m)
        let k = jsRound((alongX ? near.x : near.y) / grid) * grid
        let h2 = c.r * c.r - (k - at) * (k - at)
        if h2 < 0 { continue }
        for s in [-1.0, 1.0] {
            let other = across + s * h2.squareRoot()
            let p = alongX ? Vec(x: jsPrecision12(k), y: other) : Vec(x: other, y: jsPrecision12(k))
            let d = hypot(p.x - near.x, p.y - near.y)
            if d < bestDist { (best, bestDist) = (p, d) }
        }
    }
    return best
}

/// JavaScript's Math.round: halves go up.
public func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

/// Distance from p to the nearest of the polylines.
public func distanceToLines(_ lines: [[Vec]], _ p: Vec) -> Double {
    var best = Double.infinity
    for l in lines where l.count > 1 {
        for i in 1..<l.count {
            let a = l[i - 1], b = l[i]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
            best = min(best, hypot(p.x - a.x - t * dx, p.y - a.y - t * dy))
        }
    }
    return best
}

// MARK: Fill

/// The inequality of a row (its text, and the row compiled without its restrictions) that holds at p:
/// y = … → y ≤ … or y ≥ …, x = … → x ≤ / ≥ …, a circle or another curve → its left side ≤ / ≥ its right.
/// Nil when p is on the graph, or the graph isn't defined there.
public func sideText(_ text: String, _ row: CompiledRow, _ p: Vec) -> String? {
    guard let parsed = row.parsed, row.error == nil else { return nil }
    let side: Double
    if let fn = row.fn { side = p.y - fn(p.x) }
    else if let g = row.fnOfY { side = p.x - g(p.y) }
    else if let c = row.circle { side = (p.x - c.m) * (p.x - c.m) + (p.y - c.n) * (p.y - c.n) - c.r * c.r }
    else if let f = row.implicit?.f { side = f(p.x, p.y) }
    else { return nil }
    if !side.isFinite || abs(side) < 1e-9 * (1 + abs(p.x) + abs(p.y)) { return nil }
    let sign = side < 0 ? "≤" : "≥"
    let main = withoutWhere(text)
    // y = 2f(x) − 1, a bare x^2 (y is meant) and f(x) = … (its graph y = f(x)).
    if case .y(_, bare: true) = parsed.kind { return "y \(sign) \(main)" }
    if case .def(let name, _) = parsed.kind { return "y \(sign) \(name)(x)" }
    guard let eq = main.firstIndex(of: "=") else { return nil }
    let left = main[..<eq].trimmingCharacters(in: .whitespaces)
    let right = main[main.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    return "\(left) \(sign) \(right)"
}

/// The row of the Fill tool: the first side as the row, the others in braces.
public func fillText(_ sides: [String]) -> String {
    sides[0] + sides.dropFirst().map { " {\($0)}" }.joined()
}

// MARK: Sideways

/// The point mirrored in the line y = x.
public func mirror(_ p: Vec) -> Vec { Vec(x: p.y, y: p.x) }

/// A row's text with x and y swapped (y = 2x + 1 → x = 2y + 1).
public func mirrorText(_ text: String?) -> String? {
    text.map { String($0.map { $0 == "x" ? "y" : $0 == "y" ? "x" : $0 }) }
}
