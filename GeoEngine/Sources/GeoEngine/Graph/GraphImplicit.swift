import Foundation

// Graphs that aren't functions, worked out on a grid of small cells (marching squares): the curve
// where an equation in x and y holds (an ellipse), and the area where an inequality holds (shading).
// Where a cell's edge is crossed is found exactly by halving, so neither looks blocky; neighbouring
// cells share those points, so the pieces fit without cracks. A port of src/engine/graph/implicit.ts.

/// Cell size in pixels.
private let cellPixels = 4.0
private let halvings = 24

/// The grid over the view: aligned to multiples of the cell, so that panning doesn't make lines shimmer.
private struct Grid {
    let h: Double
    let x0: Double
    let y0: Double
    let nx: Int
    let ny: Int

    init(_ view: GraphView, _ scale: Double) {
        h = cellPixels / scale
        // A cell more on each side, so that curves run off the screen.
        x0 = ((view.xMin / h).rounded(.down) - 1) * h
        y0 = ((view.yMin / h).rounded(.down) - 1) * h
        nx = Int(((view.xMax - x0) / h).rounded(.up)) + 2
        ny = Int(((view.yMax - y0) / h).rounded(.up)) + 2
    }

    func at(_ i: Double, _ j: Double) -> Vec { Vec(x: x0 + i * h, y: y0 + j * h) }
    func point(_ k: Int) -> Vec { at(Double(k % nx), Double(k / nx)) }

    /// The values of f at the grid points, row by row.
    func values(_ f: Fn2) -> [Double] {
        var v = [Double](repeating: 0, count: nx * ny)
        for j in 0..<ny {
            for i in 0..<nx { v[j * nx + i] = f(x0 + Double(i) * h, y0 + Double(j) * h) }
        }
        return v
    }
}

/// Between p (where f is `from`) and q: where the sign of f changes, by halving.
private func crossing(_ f: Fn2, _ p: Vec, _ q: Vec, _ from: Bool) -> Vec {
    var a = 0.0, b = 1.0
    for _ in 0..<halvings {
        let m = (a + b) / 2
        let x: Double = p.x + (q.x - p.x) * m
        let y: Double = p.y + (q.y - p.y) * m
        if (f(x, y) >= 0) == from { a = m } else { b = m }
    }
    let t = (a + b) / 2
    return Vec(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
}

/// One edge of a cell: its id (shared with the neighbouring cell) and its two corners, as indices into the values.
private typealias CellEdge = (id: Int, from: Int, to: Int)

/// The four edges of cell (i, j), counter-clockwise from the bottom.
private func cellEdges(_ i: Int, _ j: Int, _ nx: Int) -> [CellEdge] {
    let c0 = j * nx + i
    let c1 = c0 + 1
    let c2 = c1 + nx
    let c3 = c0 + nx
    // Horizontal edge out of corner k: 2k; vertical: 2k + 1.
    return [(2 * c0, c0, c1), (2 * c1 + 1, c1, c2), (2 * c3, c3, c2), (2 * c0 + 1, c0, c3)]
}

/// The end of a segment: an edge id, or a point where a restriction cut the curve short.
private enum EndKey: Hashable {
    case edge(Int)
    case cut(Int)
}

private struct ContourPiece {
    var keys: (EndKey, EndKey)
    var ends: (Vec, Vec)
}

/// The curve f(x, y) = 0 in the view as polylines (only where `inside` holds). `scale`: pixels per
/// unit. A sign change that isn't a zero (1/x jumping at a pole) draws nothing.
public func contour(_ f: @escaping Fn2, _ inside: Inside?, _ view: GraphView, scale: Double) -> [[Vec]] {
    let g = Grid(view, scale)
    let v = g.values(f)
    var found: [Int: Vec?] = [:]
    /// Where the edge is crossed, or nil when it isn't (or only by a jump).
    func cross(_ e: CellEdge) -> Vec? {
        if let known = found[e.id] { return known }
        let va = v[e.from], vb = v[e.to]
        var p: Vec?
        if va.isFinite && vb.isFinite && (va >= 0) != (vb >= 0) {
            let q = crossing(f, g.point(e.from), g.point(e.to), va >= 0)
            if abs(f(q.x, q.y)) <= 1e-3 * (abs(va) + abs(vb)) { p = q }
        }
        found[e.id] = .some(p)
        return p
    }

    // Segments, each between two edge points; a piece cut short by a restriction ends at its own key.
    var segments: [ContourPiece] = []
    var cut = 0
    func add(_ e: CellEdge, _ d: CellEdge) {
        guard let p = cross(e), let q = cross(d) else { return }
        guard let inside else { return segments.append(ContourPiece(keys: (.edge(e.id), .edge(d.id)), ends: (p, q))) }
        let ip = inside(p.x, p.y), iq = inside(q.x, q.y)
        if ip && iq { return segments.append(ContourPiece(keys: (.edge(e.id), .edge(d.id)), ends: (p, q))) }
        if ip == iq { return }
        // Up to where the restriction stops holding.
        let holds: Fn2 = { x, y in inside(x, y) ? 1 : -1 }
        if ip {
            segments.append(ContourPiece(keys: (.edge(e.id), .cut(cut)), ends: (p, crossing(holds, p, q, true))))
        } else {
            segments.append(ContourPiece(keys: (.cut(cut), .edge(d.id)), ends: (crossing(holds, q, p, true), q)))
        }
        cut += 1
    }

    func crossed(_ e: CellEdge) -> Bool {
        v[e.from].isFinite && v[e.to].isFinite && (v[e.from] >= 0) != (v[e.to] >= 0)
    }
    for j in 0..<(g.ny - 1) {
        for i in 0..<(g.nx - 1) {
            let edges = cellEdges(i, j, g.nx)
            let hit = edges.filter(crossed)
            if hit.count == 2 {
                add(hit[0], hit[1])
            } else if hit.count == 4 {
                // A saddle: the middle of the cell says which corners are joined.
                let c = g.at(Double(i) + 0.5, Double(j) + 0.5)
                let joined = (f(c.x, c.y) >= 0) == (v[edges[1].from] >= 0)
                if joined {
                    add(edges[3], edges[0])
                    add(edges[1], edges[2])
                } else {
                    add(edges[0], edges[1])
                    add(edges[2], edges[3])
                }
            }
        }
    }
    return join(segments)
}

/// Joins segments that share an end into polylines.
private func join(_ segments: [ContourPiece]) -> [[Vec]] {
    var at: [EndKey: [Int]] = [:]
    for (k, s) in segments.enumerated() {
        at[s.keys.0, default: []].append(k)
        at[s.keys.1, default: []].append(k)
    }
    var used = [Bool](repeating: false, count: segments.count)
    var lines: [[Vec]] = []
    /// Follows the chain from `key` on, adding each next point.
    func walk(_ start: EndKey, _ push: (Vec) -> Void) {
        var key = start
        while let next = at[key]?.first(where: { !used[$0] }) {
            used[next] = true
            let s = segments[next]
            let far = s.keys.0 == key
            push(far ? s.ends.1 : s.ends.0)
            key = far ? s.keys.1 : s.keys.0
        }
    }
    for (k, s) in segments.enumerated() where !used[k] {
        used[k] = true
        var tail = [s.ends.0, s.ends.1]
        walk(s.keys.1) { tail.append($0) }
        var head: [Vec] = []
        walk(s.keys.0) { head.append($0) }
        lines.append(head.reversed() + tail)
    }
    return lines
}

/// The area where margin(x, y) ≥ 0 in the view, as counter-clockwise polygons: rows of whole cells
/// merged into rectangles, and the inside part of each cell the border goes through. Drawn together
/// as one path (nonzero fill), they show no seams.
public func fillPolygons(_ margin: @escaping Fn2, _ view: GraphView, scale: Double) -> [[Vec]] {
    let g = Grid(view, scale)
    let v = g.values(margin)
    func inside(_ k: Int) -> Bool { v[k] >= 0 }
    var found: [Int: Vec] = [:]
    func cross(_ e: CellEdge) -> Vec {
        if let p = found[e.id] { return p }
        let p = crossing(margin, g.point(e.from), g.point(e.to), inside(e.from))
        found[e.id] = p
        return p
    }

    var out: [[Vec]] = []
    for j in 0..<(g.ny - 1) {
        var run = -1
        func endRun(_ i: Int) {
            guard run >= 0 else { return }
            let a = g.at(Double(run), Double(j)), b = g.at(Double(i), Double(j + 1))
            out.append([a, Vec(x: b.x, y: a.y), b, Vec(x: a.x, y: b.y)])
            run = -1
        }
        for i in 0..<(g.nx - 1) {
            let edges = cellEdges(i, j, g.nx)
            // Corners counter-clockwise: bottom left, bottom right, top right, top left.
            let corners = [edges[0].from, edges[0].to, edges[1].to, edges[2].from]
            let ins = corners.map(inside)
            if ins.allSatisfy({ $0 }) {
                if run < 0 { run = i }
                continue
            }
            endRun(i)
            if !ins.contains(true) { continue }
            // Walk round the cell: the corners inside, and where each edge leaves or enters.
            var poly: [Vec] = []
            for k in 0..<4 {
                if ins[k] { poly.append(g.point(corners[k])) }
                if ins[k] != ins[(k + 1) % 4] { poly.append(cross(edges[k])) }
            }
            out.append(poly)
        }
        endRun(g.nx - 1)
    }
    return out
}

private func slope(_ f: Fn2, _ p: Vec) -> (v: Double, gx: Double, gy: Double) {
    let e = 1e-6 * (1 + abs(p.x) + abs(p.y))
    return (f(p.x, p.y), (f(p.x + e, p.y) - f(p.x - e, p.y)) / (2 * e), (f(p.x, p.y + e) - f(p.x, p.y - e)) / (2 * e))
}

/// Whether p lies on the curve f = 0 (to rounding).
public func onCurve(_ f: Fn2, _ p: Vec) -> Bool {
    let s = slope(f, p)
    return s.v.isFinite && abs(s.v) <= 1e-9 * (1 + abs(p.x) + abs(p.y)) * max(1e-12, hypot(s.gx, s.gy))
}

/// A point of the curve f = 0 next to p (Newton's method along the slope), or nil when there is none near.
public func projectOn(_ f: Fn2, _ p: Vec) -> Vec? {
    var q = p
    for _ in 0..<40 {
        let s = slope(f, q)
        let g2 = s.gx * s.gx + s.gy * s.gy
        if !s.v.isFinite || !g2.isFinite || g2 == 0 { return nil }
        let step = Vec(x: s.v * s.gx / g2, y: s.v * s.gy / g2)
        q = Vec(x: q.x - step.x, y: q.y - step.y)
        if hypot(step.x, step.y) < 1e-13 * (1 + abs(q.x) + abs(q.y)) { break }
    }
    return onCurve(f, q) ? q : nil
}

/// Where the curve f = 0 crosses the line x = c (`alongX`) or y = c, starting from t (Newton), or nil.
public func crossLine(_ f: Fn2, alongX: Bool, _ c: Double, _ t0: Double) -> Vec? {
    func at(_ s: Double) -> Vec { alongX ? Vec(x: c, y: s) : Vec(x: s, y: c) }
    var t = t0
    for _ in 0..<40 {
        let p = at(t)
        let e = 1e-6 * (1 + abs(t))
        let v = f(p.x, p.y)
        let q = at(t + e), r = at(t - e)
        let d = (f(q.x, q.y) - f(r.x, r.y)) / (2 * e)
        if !v.isFinite || !d.isFinite || d == 0 { return nil }
        let step = v / d
        t -= step
        if abs(step) < 1e-13 * (1 + abs(t)) { break }
    }
    let p = at(t)
    return onCurve(f, p) ? p : nil
}
