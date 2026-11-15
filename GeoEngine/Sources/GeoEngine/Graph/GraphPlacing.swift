import Foundation

// Placing a function by clicking: per kind, one hint per click, where a click is pulled to (the
// x-axis for roots, an asymptote), why a click is refused, the row once the last point is in, the
// dashed preview meanwhile and dashed helper lines. A port of the KINDS table of the web app's
// GraphWorkspace.tsx, with placing sideways (x = f(y)) by mirroring in y = x.

public enum FunctionKind: String, CaseIterable, Sendable {
    case linear
    case parabolaVertex = "parabola.vertex", parabolaIntercept = "parabola.intercept", parabolaGeneral = "parabola.general"
    case cubicInflection = "cubic.inflection", cubicIntercept = "cubic.intercept", cubicGeneral = "cubic.general"
    case sin = "trig.sin", cos = "trig.cos", tan = "trig.tan"
    case hyperbola, circle, ellipse

    /// The family of a kind with forms ("parabola"), or the kind itself.
    public var family: String { String(rawValue.split(separator: ".").first!) }
    /// A circle and an ellipse look the same placed sideways.
    public var isRound: Bool { self == .circle || self == .ellipse }
    /// Sines, cosines and tangents are placed on an axis marked in multiples of π.
    public var usesPi: Bool { family == "trig" }
}

/// A dashed helper line while placing: vertical at x, horizontal at y (asymptotes), or a segment (a radius).
public enum Guide: Equatable, Sendable {
    case x(Double)
    case y(Double)
    case segment(Vec, Vec)
}

/// What the graph under the pointer would be: its row text, and whether it is the function itself
/// (`ghost`) rather than a helper (a line through two points where no parabola fits yet).
public struct PlacingPreview: Equatable, Sendable {
    public var text: String?
    public var ghost: Bool
}

public struct PlacingKind {
    public var hints: [String]
    public var constrain: ([Vec], Vec) -> Vec
    public var reject: ([Vec], Vec) -> String?
    public var through: ([Vec], Vec, Bool) -> String?
    public var preview: ([Vec], Vec, Bool) -> PlacingPreview?
    public var guides: ([Vec], Vec?) -> [Guide]

    init(hints: [String], constrain: @escaping ([Vec], Vec) -> Vec = { $1 }, reject: @escaping ([Vec], Vec) -> String?,
         through: @escaping ([Vec], Vec, Bool) -> String?, preview: @escaping ([Vec], Vec, Bool) -> PlacingPreview?,
         guides: @escaping ([Vec], Vec?) -> [Guide] = { _, _ in [] }) {
        self.hints = hints
        self.constrain = constrain
        self.reject = reject
        self.through = through
        self.preview = preview
        self.guides = guides
    }
}

private func sameX(_ p: Vec, _ q: Vec) -> Bool { abs(p.x - q.x) < 1e-12 }
private func ghost(_ text: String?) -> PlacingPreview { PlacingPreview(text: text, ghost: true) }

private func kindTable(_ kind: FunctionKind) -> PlacingKind {
    switch kind {
    case .linear:
        return PlacingKind(
            hints: ["graph.hint.placeBase", "graph.hint.placeSecond"],
            // Straight above the first point: the vertical line x = c.
            reject: { ps, p in ps.first.map { sameX($0, p) && abs($0.y - p.y) < graphEps } == true ? "graph.hint.samePoint" : nil },
            through: { ps, p, c in linearThrough(ps[0], p, comma: c) ?? verticalThrough(ps[0], comma: c) },
            preview: { ps, p, c in ps.first.map { ghost(linearThrough($0, p, comma: c) ?? verticalThrough($0, comma: c)) } })
    case .parabolaVertex:
        return PlacingKind(
            hints: ["graph.hint.parabola.placeVertex", "graph.hint.parabola.placeSecond"],
            reject: { ps, p in
                guard let v = ps.first else { return nil }
                return sameX(v, p) ? "graph.hint.parabola.sameX" : parabolaThrough(v, p) == nil ? "graph.hint.parabola.flat" : nil
            },
            through: { ps, p, c in vertexThrough(ps[0], p, comma: c) },
            preview: { ps, p, c in ps.first.map { ghost(vertexThrough($0, p, comma: c)) } })
    case .parabolaIntercept:
        return PlacingKind(
            hints: ["graph.hint.parabola.root1", "graph.hint.parabola.root2", "graph.hint.parabola.placeSecond"],
            constrain: { ps, p in ps.count < 2 ? Vec(x: p.x, y: 0) : p },
            reject: { ps, p in
                ps.count < 2 ? nil : abs(p.y) < graphEps ? "graph.hint.parabola.onAxis"
                    : ps.contains { sameX($0, p) } ? "graph.hint.parabola.aboveRoot" : nil
            },
            through: { ps, p, c in interceptThrough(ps[0], ps[1], p, comma: c) },
            // Until the third point is in (or where it gives no parabola), a = 1 shows where the roots are.
            preview: { ps, p, c in
                guard let r1 = ps.first else { return nil }
                let r2 = ps.count == 1 ? p : ps[1]
                let fitted = ps.count == 1 ? nil : interceptThrough(r1, r2, p, comma: c)
                return ghost(fitted ?? interceptForm(1, r1.x, r2.x, comma: c))
            })
    case .parabolaGeneral:
        return PlacingKind(
            hints: ["graph.hint.parabola.point1", "graph.hint.parabola.point2", "graph.hint.parabola.point3"],
            reject: { ps, p in
                ps.contains { sameX($0, p) } ? "graph.hint.parabola.sameXPoints"
                    : ps.count == 2 && generalCoefficients(ps[0], ps[1], p) == nil ? "graph.hint.parabola.line" : nil
            },
            through: { ps, p, c in generalThrough(ps[0], ps[1], p, comma: c) },
            // No curve through one point; after two, a dashed line through them where no parabola fits.
            preview: { ps, p, c in
                guard ps.count >= 2 else { return nil }
                if let text = generalThrough(ps[0], ps[1], p, comma: c) { return ghost(text) }
                return PlacingPreview(text: linearThrough(ps[0], ps[1], comma: c), ghost: false)
            })
    case .cubicInflection:
        return PlacingKind(
            hints: ["graph.hint.cubic.placeInflection", "graph.hint.cubic.placeSecond"],
            reject: { ps, p in
                guard let i = ps.first else { return nil }
                return sameX(i, p) ? "graph.hint.cubic.sameX" : cubicThrough(i, p) == nil ? "graph.hint.cubic.flat" : nil
            },
            through: { ps, p, c in inflectionThrough(ps[0], p, comma: c) },
            preview: { ps, p, c in ps.first.map { ghost(inflectionThrough($0, p, comma: c)) } })
    case .cubicIntercept:
        return PlacingKind(
            hints: ["graph.hint.cubic.root1", "graph.hint.cubic.root2", "graph.hint.cubic.root3", "graph.hint.cubic.placeSecond"],
            constrain: { ps, p in ps.count < 3 ? Vec(x: p.x, y: 0) : p },
            reject: { ps, p in
                ps.count < 3 ? nil : abs(p.y) < graphEps ? "graph.hint.cubic.onAxis"
                    : ps.contains { sameX($0, p) } ? "graph.hint.parabola.aboveRoot" : nil
            },
            through: { ps, p, c in cubicInterceptThrough(ps, p, comma: c) },
            // Until the fourth point is in, a = 1 shows where the roots are; the pointer stands in for those still to come.
            preview: { ps, p, c in
                guard !ps.isEmpty else { return nil }
                if ps.count == 3 { return ghost(cubicInterceptThrough(ps, p, comma: c) ?? cubicInterceptForm(1, ps.map(\.x), comma: c)) }
                return ghost(cubicInterceptForm(1, Array((ps.map(\.x) + [p.x, p.x]).prefix(3)), comma: c))
            })
    case .cubicGeneral:
        return PlacingKind(
            hints: ["graph.hint.cubic.point1", "graph.hint.cubic.point2", "graph.hint.cubic.point3", "graph.hint.cubic.point4"],
            reject: { ps, p in
                ps.contains { sameX($0, p) } ? "graph.hint.parabola.sameXPoints"
                    : ps.count == 3 && cubicCoefficients(ps + [p]) == nil ? "graph.hint.cubic.notCubic" : nil
            },
            through: { ps, p, c in cubicGeneralThrough(ps + [p], comma: c) },
            preview: { ps, p, c in
                guard ps.count >= 3 else { return nil }
                if let text = cubicGeneralThrough(ps + [p], comma: c) { return ghost(text) }
                return PlacingPreview(text: generalThrough(ps[0], ps[1], ps[2], comma: c), ghost: false)
            })
    // Two clicks fix the middle line, the height and the period; a dashed middle line shows.
    case .sin:
        return PlacingKind(
            hints: ["graph.hint.sin.middle", "graph.hint.sin.top"],
            reject: { ps, p in
                guard let s = ps.first else { return nil }
                return sameX(s, p) ? "graph.hint.trig.sameX" : abs(p.y - s.y) < graphEps ? "graph.hint.trig.flat" : nil
            },
            through: { ps, p, c in sineThrough(ps[0], p, comma: c) },
            preview: { ps, p, c in ps.first.map { ghost(sineThrough($0, p, comma: c)) } },
            guides: { ps, p in ps.first.map { [.y($0.y)] } ?? p.map { [.y($0.y)] } ?? [] })
    case .cos:
        return PlacingKind(
            hints: ["graph.hint.cos.top", "graph.hint.cos.middle"],
            reject: { ps, p in
                guard let m = ps.first else { return nil }
                return sameX(m, p) ? "graph.hint.trig.sameX" : abs(p.y - m.y) < graphEps ? "graph.hint.trig.flat" : nil
            },
            through: { ps, p, c in cosineThrough(ps[0], p, comma: c) },
            preview: { ps, p, c in ps.first.map { ghost(cosineThrough($0, p, comma: c)) } },
            guides: { ps, p in !ps.isEmpty && p != nil ? [.y(p!.y)] : [] })
    // The centre, the asymptote next to it (level with the centre), then a point that sets a.
    case .tan:
        return PlacingKind(
            hints: ["graph.hint.tan.centre", "graph.hint.tan.asymptote", "graph.hint.tan.point"],
            constrain: { ps, p in ps.count == 1 ? Vec(x: p.x, y: ps[0].y) : p },
            reject: { ps, p in
                guard let c = ps.first else { return nil }
                guard ps.count > 1 else { return sameX(c, p) ? "graph.hint.tan.onCentre" : nil }
                if sameX(c, p) { return "graph.hint.trig.sameX" }
                if abs(p.y - c.y) < graphEps { return "graph.hint.trig.flat" }
                return tangentB(c, ps[1].x).flatMap { tangentA(c, $0, p) } == nil ? "graph.hint.tan.onAsymptote" : nil
            },
            through: { ps, p, c in tangentThrough(ps[0], ps[1].x, p, comma: c) },
            preview: { ps, p, c in
                guard let centre = ps.first else { return nil }
                let x = ps.count > 1 ? ps[1].x : p.x
                guard let b = tangentB(centre, x) else { return nil }
                let fitted = ps.count > 1 ? tangentThrough(centre, x, p, comma: c) : nil
                return ghost(fitted ?? trigForm(.tan, 1, b, centre.x, centre.y, comma: c))
            },
            guides: { ps, p in
                guard let c = ps.first else { return [] }
                let half = abs((ps.count > 1 ? ps[1] : p ?? c).x - c.x)
                // About 100 periods each side (the web uses 400, so the 200 listed stop left of the centre).
                let span = 199 * max(half, 1e-9)
                return [.y(c.y)] + tangentAsymptotes(c.x, half, c.x - span, c.x + span).map { .x($0) }
            })
    // Click 1 marks the vertical asymptote where it crosses the x-axis, click 2 the centre on it.
    case .hyperbola:
        return PlacingKind(
            hints: ["graph.hint.hyperbola.vertical", "graph.hint.hyperbola.horizontal", "graph.hint.hyperbola.point"],
            constrain: { ps, p in ps.isEmpty ? Vec(x: p.x, y: 0) : ps.count == 1 ? Vec(x: ps[0].x, y: p.y) : p },
            reject: { ps, p in
                ps.count < 2 ? nil : sameX(ps[1], p) ? "graph.hint.hyperbola.onVertical"
                    : abs(p.y - ps[1].y) < graphEps ? "graph.hint.hyperbola.onHorizontal" : nil
            },
            through: { ps, p, c in hyperbolaThrough(ps[1], p, comma: c) },
            preview: { ps, p, c in
                guard !ps.isEmpty else { return nil }
                let centre = ps.count > 1 ? ps[1] : p
                let fitted = ps.count == 2 ? hyperbolaThrough(centre, p, comma: c) : nil
                return ghost(fitted ?? hyperbolaForm(1, centre.x, centre.y, comma: c))
            },
            guides: { ps, p in
                let v = ps.first ?? p
                let h = ps.isEmpty ? nil : (ps.count > 1 ? ps[1] : p)
                return (v.map { [Guide.x($0.x)] } ?? []) + (h.map { [Guide.y($0.y)] } ?? [])
            })
    // The centre, how far it reaches to the side (level with the centre), then up or down.
    case .ellipse:
        return PlacingKind(
            hints: ["graph.hint.ellipse.centre", "graph.hint.ellipse.side", "graph.hint.ellipse.top"],
            constrain: { ps, p in ps.count > 1 ? Vec(x: ps[0].x, y: p.y) : ps.count == 1 ? Vec(x: p.x, y: ps[0].y) : p },
            reject: { ps, p in
                if ps.count > 1 { return abs(p.y - ps[0].y) < graphEps ? "graph.hint.ellipse.flat" : nil }
                return ps.count == 1 && abs(p.x - ps[0].x) < graphEps ? "graph.hint.ellipse.onCentre" : nil
            },
            through: { ps, p, c in ellipseThrough(ps[0], ps[1], p, comma: c) },
            // Until its height is set, the ellipse is round.
            preview: { ps, p, c in
                guard let centre = ps.first else { return nil }
                let a = (ps.count > 1 ? ps[1] : p).x - centre.x
                let text = ps.count > 1 ? ellipseThrough(centre, ps[1], p, comma: c) : ellipseForm(centre.x, centre.y, a, a, comma: c)
                return text.map { ghost($0) }
            },
            guides: { ps, p in
                guard let c = ps.first else { return [] }
                return (ps.count > 1 ? [Guide.segment(c, ps[1])] : []) + (p.map { [Guide.segment(c, $0)] } ?? [])
            })
    // The centre, then a point of the circle; a dashed radius joins them meanwhile.
    case .circle:
        return PlacingKind(
            hints: ["graph.hint.circle.centre", "graph.hint.circle.point"],
            reject: { ps, p in !ps.isEmpty && circleThrough(ps[0], p, comma: false) == nil ? "graph.hint.circle.onCentre" : nil },
            through: { ps, p, c in circleThrough(ps[0], p, comma: c) },
            preview: { ps, p, c in ps.first.map { ghost(circleThrough($0, p, comma: c)) } },
            guides: { ps, p in ps.first.flatMap { c in p.map { [.segment(c, $0)] } } ?? [] })
    }
}

/// Hints whose words change sideways (the y-axis, level with, higher or lower); the hyperbola's asymptotes trade places.
private let sidewaysHints: [String: String] = {
    var d: [String: String] = [:]
    for key in ["parabola.sameX", "parabola.flat", "parabola.root1", "parabola.root2", "parabola.onAxis", "parabola.aboveRoot",
                "parabola.sameXPoints", "cubic.sameX", "cubic.flat", "cubic.root1", "cubic.root2", "cubic.root3", "cubic.onAxis",
                "sin.middle", "sin.top", "cos.top", "cos.middle", "trig.sameX", "trig.flat", "tan.onCentre"] {
        d["graph.hint.\(key)"] = "graph.hint.\(key).sideways"
    }
    d["graph.hint.hyperbola.vertical"] = "graph.hint.hyperbola.horizontal"
    d["graph.hint.hyperbola.horizontal"] = "graph.hint.hyperbola.vertical"
    d["graph.hint.hyperbola.onVertical"] = "graph.hint.hyperbola.onHorizontal"
    d["graph.hint.hyperbola.onHorizontal"] = "graph.hint.hyperbola.onVertical"
    return d
}()

private func sidewaysHint(_ key: String?) -> String? { key.map { sidewaysHints[$0] ?? $0 } }

/// The rules for placing `kind`. Sideways, the clicks are mirrored in y = x, handed to the kind as
/// usual, and what comes back (the row, the guides) is mirrored back.
public func placingKind(_ kind: FunctionKind, sideways: Bool) -> PlacingKind {
    let k = kindTable(kind)
    guard sideways && !kind.isRound else { return k }
    let all = { (ps: [Vec]) in ps.map(mirror) }
    return PlacingKind(
        hints: k.hints.map { sidewaysHint($0)! },
        constrain: { ps, p in mirror(k.constrain(all(ps), mirror(p))) },
        reject: { ps, p in sidewaysHint(k.reject(all(ps), mirror(p))) },
        through: { ps, p, c in mirrorText(k.through(all(ps), mirror(p), c)) },
        preview: { ps, p, c in k.preview(all(ps), mirror(p), c).map { PlacingPreview(text: mirrorText($0.text), ghost: $0.ghost) } },
        guides: { ps, p in
            k.guides(all(ps), p.map(mirror)).map {
                switch $0 {
                case .x(let x): return .y(x)
                case .y(let y): return .x(y)
                case .segment(let a, let b): return .segment(mirror(a), mirror(b))
                }
            }
        })
}

/// The base formula of a kind, as a hint of what is being placed (sideways: x and y trade places).
public func functionTemplate(_ kind: FunctionKind, sideways: Bool, czech: Bool) -> String {
    let (X, Y) = sideways && !kind.isRound ? ("y", "x") : ("x", "y")
    let (h, k) = czech ? ("m", "n") : ("h", "k")
    switch kind {
    case .linear: return "\(Y) = m\(X) + c"
    case .parabolaVertex: return "\(Y) = a(\(X) − \(h))² + \(k)"
    case .parabolaIntercept: return "\(Y) = a(\(X) − \(X)₁)(\(X) − \(X)₂)"
    case .parabolaGeneral: return "\(Y) = a\(X)² + b\(X) + c"
    case .cubicInflection: return "\(Y) = a(\(X) − \(h))³ + \(k)"
    case .cubicIntercept: return "\(Y) = a(\(X) − \(X)₁)(\(X) − \(X)₂)(\(X) − \(X)₃)"
    case .cubicGeneral: return "\(Y) = a\(X)³ + b\(X)² + c\(X) + d"
    case .sin, .cos, .tan: return "\(Y) = a·\(kind.rawValue.dropFirst(5))(b(\(X) − c)) + d"
    case .hyperbola: return czech ? "\(Y) = k/(\(X) − m) + n" : "\(Y) = a/(\(X) − h) + k"
    case .circle: return "(x − \(h))² + (y − \(k))² = r²"
    case .ellipse: return "(x − \(h))²/a² + (y − \(k))²/b² = 1"
    }
}
