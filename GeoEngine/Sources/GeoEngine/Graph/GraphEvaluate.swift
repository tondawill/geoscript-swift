import Foundation

// Turns the parsed rows into functions of x. Rows may call functions defined in any other row
// (`f(x) = sin x` and `y = 2f(x)`); unknown names, duplicate definitions and cycles are errors.
// A port of the web app's src/engine/graph/evaluate.ts.

public typealias Fn = (Double) -> Double
/// An expression in x and y (a restriction, the right side of x = … in y, an equation in both).
public typealias Fn2 = (Double, Double) -> Double
/// Whether the point [x; y] satisfies a row's restrictions.
public typealias Inside = (Double, Double) -> Bool

/// A circle row: its centre [m; n] and radius; `inside`: only the arc where it holds is drawn.
public struct GraphCircle {
    public var m: Double
    public var n: Double
    public var r: Double
    public var inside: Inside?
}

/// Any other equation in x and y (an ellipse): drawn where f, its left side minus its right, is 0.
public struct Implicit {
    public var f: Fn2
    public var inside: Inside?
}

/// A shaded row (an inequality): inside where `margin` ≥ 0, with its borders.
public struct Region {
    public var margin: Fn2
    public var edges: [Edge]
}

/// What a row draws: y = f(x), x = g(y) (sideways), a circle, any other curve, or a shaded area.
/// Outside a row's restrictions its functions are NaN, so it isn't drawn there.
public struct Drawn {
    public var fn: Fn?
    public var fnOfY: Fn?
    public var circle: GraphCircle?
    public var implicit: Implicit?
    public var region: Region?

    public init(fn: Fn? = nil, fnOfY: Fn? = nil, circle: GraphCircle? = nil, implicit: Implicit? = nil, region: Region? = nil) {
        self.fn = fn
        self.fnOfY = fnOfY
        self.circle = circle
        self.implicit = implicit
        self.region = region
    }
}

/// One border of a shaded row, drawn where the rest of the row holds; `strict` (< or >): dashed.
public struct Edge {
    public var drawn: Drawn
    public var strict: Bool
}

/// A row ready to draw, an error to show, or neither (an empty row).
public struct CompiledRow {
    public var id: String
    public var parsed: ParsedRow?
    public var drawn: Drawn
    public var error: GraphError?

    public var fn: Fn? { drawn.fn }
    public var fnOfY: Fn? { drawn.fnOfY }
    public var circle: GraphCircle? { drawn.circle }
    public var implicit: Implicit? { drawn.implicit }
    public var region: Region? { drawn.region }
}

private func builtIn(_ name: BuiltIn) -> Fn {
    switch name {
    case .sin: return sin
    case .cos: return cos
    case .tan: return tan
    case .sqrt: return { $0.squareRoot() }
    case .abs: return { Swift.abs($0) }
    case .ln: return { Foundation.log($0) }
    case .log: return log10
    case .exp: return Foundation.exp
    }
}

/// Like JavaScript's Math.pow, but odd roots of negative numbers are real: (−8)^(1/3) = −2.
func jsPow(_ a: Double, _ b: Double) -> Double {
    if b.isNaN { return .nan }
    if b.isInfinite && Swift.abs(a) == 1 { return .nan }
    if a >= 0 || (b.isFinite && b == b.rounded(.towardZero)) { return Foundation.pow(a, b) }
    let inv = 1 / b
    let n = (inv + 0.5).rounded(.down)
    if Swift.abs(inv - n) < 1e-9 && n.truncatingRemainder(dividingBy: 2) != 0 { return -Foundation.pow(-a, b) }
    return .nan
}

private func calls(_ e: Expr, _ out: inout [String]) {
    switch e {
    case .call(let name, let a):
        if !out.contains(name) { out.append(name) }
        calls(a, &out)
    case .neg(let a), .fn(_, let a):
        calls(a, &out)
    case .bin(_, let a, let b):
        calls(a, &out)
        calls(b, &out)
    default:
        break
    }
}

private func callsOf(_ e: Expr) -> [String] {
    var out: [String] = []
    calls(e, &out)
    return out
}

/// Does the expression use the variable (true: x, false: y)?
private func mentions(_ e: Expr, x: Bool) -> Bool {
    switch e {
    case .x: return x
    case .y: return !x
    case .neg(let a), .fn(_, let a), .call(_, let a): return mentions(a, x: x)
    case .bin(_, let a, let b): return mentions(a, x: x) || mentions(b, x: x)
    default: return false
    }
}

/// One comparison of a chain: its two sides, a test (the ends count as inside) and a margin, ≥ 0 inside.
private struct Comparison {
    var a: Expr
    var b: Expr
    var op: Compare
    var holds: Inside
    var margin: Fn2
}

private func allHold(_ cs: [Comparison]) -> Inside {
    let tests = cs.map(\.holds)
    return { x, y in tests.allSatisfy { $0(x, y) } }
}

/// y = f(x) only where the restrictions hold (they may use y, the value).
private func restrict(_ f: @escaping Fn, _ inside: @escaping Inside) -> Fn {
    { x in
        let y = f(x)
        return inside(x, y) ? y : .nan
    }
}

/// Compiles expressions of one set of rows. A definition is compiled when first called, after its own
/// calls, so the closures hold each other directly (definitions with problems give NaN).
private final class Compiler {
    var bodies: [String: Expr] = [:]
    var duplicate = Set<String>()
    var defWhere: [String: [Restriction]] = [:]
    private var defs: [String: Fn] = [:]
    private var compiling = Set<String>()

    /// Why a function can't be used: unknown, defined twice, or it calls itself.
    func problem(_ name: String, _ seen: [String] = []) -> GraphError? {
        if seen.contains(name) { return GraphError("graph.error.cycle", name: name) }
        guard let body = bodies[name] else { return GraphError("graph.error.unknownFunction", name: name) }
        if duplicate.contains(name) { return GraphError("graph.error.duplicate", name: name) }
        for c in callsOf(body) {
            if let err = problem(c, seen + [name]) { return err }
        }
        return nil
    }

    func def(_ name: String) -> Fn {
        if let f = defs[name] { return f }
        guard problem(name) == nil, !compiling.contains(name), let body = bodies[name] else { return { _ in .nan } }
        compiling.insert(name)
        let plain = ofX(body)
        let f = defWhere[name].map { restrict(plain, compileWhere($0)) } ?? plain
        compiling.remove(name)
        defs[name] = f
        return f
    }

    func expr(_ e: Expr) -> Fn2 {
        switch e {
        case .num(let v): return { _, _ in v }
        case .x: return { x, _ in x }
        case .y: return { _, y in y }
        case .pi: return { _, _ in Double.pi }
        case .e: return { _, _ in M_E }
        case .neg(let a):
            let fa = expr(a)
            return { x, y in -fa(x, y) }
        case .fn(let name, let a):
            let f = builtIn(name)
            let fa = expr(a)
            return { x, y in f(fa(x, y)) }
        case .call(let name, let a):
            let f = def(name)
            let fa = expr(a)
            return { x, y in f(fa(x, y)) }
        case .bin(let op, let a, let b):
            let fa = expr(a)
            let fb = expr(b)
            switch op {
            case .add: return { x, y in fa(x, y) + fb(x, y) }
            case .sub: return { x, y in fa(x, y) - fb(x, y) }
            case .mul: return { x, y in fa(x, y) * fb(x, y) }
            case .div: return { x, y in fa(x, y) / fb(x, y) }
            case .pow: return { x, y in jsPow(fa(x, y), fb(x, y)) }
            }
        }
    }

    /// A function of x alone (a y in it is undefined).
    func ofX(_ e: Expr) -> Fn {
        let f = expr(e)
        return { x in f(x, .nan) }
    }

    func comparisons(_ r: Restriction) -> [Comparison] {
        let fs = r.terms.map(expr)
        return r.ops.enumerated().map { i, op in
            let fa = fs[i], fb = fs[i + 1]
            let below = op == .lt || op == .le
            return Comparison(
                a: r.terms[i], b: r.terms[i + 1], op: op,
                holds: { x, y in
                    let a = fa(x, y), b = fb(x, y)
                    // A hair of slack, so that 0 ≤ x ≤ 10 keeps x = 10 when it is sampled as 10.000000000002.
                    let slack = 1e-9 * (1 + Swift.abs(a) + Swift.abs(b))
                    return below ? a <= b + slack : a >= b - slack
                },
                margin: below ? { x, y in fb(x, y) - fa(x, y) } : { x, y in fa(x, y) - fb(x, y) })
        }
    }

    /// All the restrictions as one test; the ends count as inside, so 0 < x and 0 ≤ x draw alike.
    func compileWhere(_ restrictions: [Restriction]) -> Inside {
        allHold(restrictions.flatMap(comparisons))
    }

    /// The graph of a = b where `inside` holds, drawn the best way there is: y = f(x) when one side is y
    /// alone, x = g(y) when it's x alone, a circle, or else as an implicit curve.
    func drawnOf(_ a: Expr, _ b: Expr, _ inside: @escaping Inside) -> Drawn {
        for (v, other) in [(a, b), (b, a)] {
            if v == .y && !mentions(other, x: false) { return Drawn(fn: restrict(ofX(other), inside)) }
            if v == .x && !mentions(other, x: true) {
                let g = expr(other)
                return Drawn(fnOfY: { y in
                    let x = g(.nan, y)
                    return inside(x, y) ? x : .nan
                })
            }
        }
        if let c = circleOf(a, b) ?? circleOf(b, a), case .circle(_, let rhs, let em, let en) = c {
            let m = expr(em)(0, 0), n = expr(en)(0, 0), r2 = expr(rhs)(0, 0)
            guard m.isFinite && n.isFinite && r2 > 0 else { return Drawn() }
            return Drawn(circle: GraphCircle(m: m, n: n, r: r2.squareRoot(), inside: inside))
        }
        let fa = expr(a), fb = expr(b)
        return Drawn(implicit: Implicit(f: { x, y in fa(x, y) - fb(x, y) }, inside: inside))
    }

    /// A shaded row: inside where all its comparisons and restrictions hold; a border for each comparison.
    func region(_ row: Restriction, _ restrictions: [Restriction]) -> Region {
        let own = comparisons(row)
        let all = own + restrictions.flatMap(comparisons)
        let margins = all.map(\.margin)
        let margin: Fn2 = { x, y in
            var m = Double.infinity
            for c in margins {
                let v = c(x, y)
                if v.isNaN { return .nan }
                if v < m { m = v }
            }
            return m
        }
        let edges = own.enumerated().map { i, c in
            Edge(drawn: drawnOf(c.a, c.b, allHold(all.enumerated().filter { $0.offset != i }.map(\.element))),
                 strict: c.op == .lt || c.op == .gt)
        }
        return Region(margin: margin, edges: edges)
    }
}

/// Parses and compiles all rows together.
public func compileRows(_ rows: [GraphRow]) -> [CompiledRow] {
    let parsed: [Result<ParsedRow, GraphError>?] = rows.map {
        $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : parseRow($0.text)
    }
    let c = Compiler()
    for case .success(let p)? in parsed {
        guard case .def(let name, let body) = p.kind else { continue }
        if c.bodies[name] != nil { c.duplicate.insert(name) } else { c.bodies[name] = body }
        if !p.restrictions.isEmpty { c.defWhere[name] = p.restrictions }
    }

    return rows.enumerated().map { i, r in
        func out(_ parsed: ParsedRow?, _ drawn: Drawn = Drawn(), _ error: GraphError? = nil) -> CompiledRow {
            CompiledRow(id: r.id, parsed: parsed, drawn: drawn, error: error)
        }
        guard let p = parsed[i] else { return out(nil) }
        let row: ParsedRow
        switch p {
        case .failure(let error): return out(nil, Drawn(), error)
        case .success(let value): row = value
        }
        var own: GraphError?
        if case .def(let name, _) = row.kind { own = c.problem(name) }
        var sides: [Expr]
        switch row.kind {
        case .circle(_, let rhs, let m, let n): sides = [m, n, rhs]
        case .curve(let lhs, let rhs): sides = [lhs, rhs]
        case .region(let r): sides = r.terms
        case .y(let e, _), .def(_, let e), .x(let e): sides = own != nil ? [] : [e]
        }
        let used = sides.flatMap(callsOf) + row.restrictions.flatMap { $0.terms.flatMap(callsOf) }
        for name in used {
            if let err = c.problem(name) { return out(row, Drawn(), err) }
        }
        if let own { return out(row, Drawn(), own) }
        let inside = row.restrictions.isEmpty ? nil : c.compileWhere(row.restrictions)
        switch row.kind {
        case .circle(_, let rhs, let em, let en):
            let m = c.expr(em)(0, 0), n = c.expr(en)(0, 0), r2 = c.expr(rhs)(0, 0)
            guard m.isFinite && n.isFinite && r2.isFinite && r2 > 0 else { return out(row, Drawn(), GraphError("graph.error.radius")) }
            return out(row, Drawn(circle: GraphCircle(m: m, n: n, r: r2.squareRoot(), inside: inside)))
        case .curve(let lhs, let rhs):
            // Always drawn as a curve, even when it could be a function (2y = x).
            let fl = c.expr(lhs), fr = c.expr(rhs)
            return out(row, Drawn(implicit: Implicit(f: { x, y in fl(x, y) - fr(x, y) }, inside: inside)))
        case .region(let r):
            return out(row, Drawn(region: c.region(r, row.restrictions)))
        case .x(let e):
            let g = c.expr(e)
            return out(row, Drawn(fnOfY: { y in
                let x = g(.nan, y)
                return inside == nil || inside!(x, y) ? x : .nan
            }))
        case .def(let name, _):
            // A definition's restrictions are already part of it.
            return out(row, Drawn(fn: c.def(name)))
        case .y(let e, _):
            let fn = c.ofX(e)
            return out(row, Drawn(fn: inside.map { restrict(fn, $0) } ?? fn))
        }
    }
}
