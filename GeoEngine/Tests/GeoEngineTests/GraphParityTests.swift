import Foundation
import Testing
@testable import GeoEngine

/// Compares the Swift graph engine with the TypeScript one (parity/graphs.ts): parsing, values, drawn
/// lines, shading, crossings, number formatting and files. Set GEO_PARITY_OUT to also write files for
/// parity/graphs.ts to open with the web code.
@Suite struct GraphParity {
    private var data: [String: Any] {
        get throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("graphs-parity.json")
            return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }
    }

    private func view(_ d: [String: Any]) -> GraphView {
        let v = d["view"] as! [String: Double]
        return GraphView(xMin: v["xMin"]!, xMax: v["xMax"]!, yMin: v["yMin"]!, yMax: v["yMax"]!)
    }

    /// Two numbers (or both missing) equal to rounding.
    private func same(_ a: Double?, _ b: Any?, _ what: @autoclosure () -> String, tolerance: Double = 1e-9) {
        let want = (b as? NSNumber)?.doubleValue
        switch (a, want) {
        case (nil, nil): return
        case let (a?, b?) where abs(a - b) <= tolerance * (1 + abs(b)): return
        default: Issue.record("\(what()): got \(String(describing: a)), want \(String(describing: want))")
        }
    }

    private func samePoints(_ got: [Vec], _ want: Any?, _ what: String, tolerance: Double = 1e-7) {
        let w = (want as? [[Double]]) ?? []
        guard got.count == w.count else {
            Issue.record("\(what): \(got.map { [$0.x, $0.y] }) vs \(w)")
            return
        }
        for (p, q) in zip(got, w) {
            same(p.x, q[0], "\(what) x", tolerance: tolerance)
            same(p.y, q[1], "\(what) y", tolerance: tolerance)
        }
    }

    private func sorted(_ ps: [Vec]) -> [Vec] { ps.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y } }

    @Test func rowsMatchTypeScript() throws {
        let d = try data
        let v = view(d)
        let scale = d["scale"] as! Double
        let xs = d["xs"] as! [Double]
        let pts = (d["pts"] as! [[Double]]).map { ($0[0], $0[1]) }
        let cases = d["cases"] as! [[String: Any]]
        #expect(cases.count >= 15)
        for c in cases {
            let texts = c["texts"] as! [String]
            let rows = texts.enumerated().map { GraphRow(id: "g\($0 + 1)", text: $1, color: "red") }
            let compiled = compileRows(rows)
            for (i, (row, want)) in zip(compiled, c["rows"] as! [[String: Any]]).enumerated() {
                let label = "row \(i + 1) “\(texts[i])”"
                #expect(row.parsed.map(parsedText) == want["parsed"] as? String, "\(label) parsed")
                let error = row.error.map { [$0.key, $0.name ?? ""] }
                #expect(error == want["error"] as? [String], "\(label) error")
                let fn = want["fn"] as? [Any]
                #expect((row.fn != nil) == (fn != nil), "\(label) has fn")
                if let f = row.fn, let fn { for (x, w) in zip(xs, fn) { same(finite(f(x)), w, "\(label) f(\(x))") } }
                let fy = want["fnOfY"] as? [Any]
                #expect((row.fnOfY != nil) == (fy != nil), "\(label) has fnOfY")
                if let g = row.fnOfY, let fy { for (y, w) in zip(xs, fy) { same(finite(g(y)), w, "\(label) g(\(y))") } }
                let circle = want["circle"] as? [Any]
                #expect((row.circle != nil) == (circle != nil), "\(label) has circle")
                if let k = row.circle, let circle {
                    same(k.m, circle[0], "\(label) m")
                    same(k.n, circle[1], "\(label) n")
                    same(k.r, circle[2], "\(label) r")
                    for (j, p) in pts.enumerated() {
                        #expect((k.inside?(p.0, p.1) ?? true) == (circle[3 + j] as? Bool), "\(label) inside \(p)")
                    }
                }
                let implicit = want["implicit"] as? [Any]
                #expect((row.implicit != nil) == (implicit != nil), "\(label) has implicit")
                if let f = row.implicit?.f, let implicit { for (p, w) in zip(pts, implicit) { same(finite(f(p.0, p.1)), w, "\(label) f\(p)") } }
                let margin = want["margin"] as? [Any]
                #expect((row.region != nil) == (margin != nil), "\(label) has region")
                if let region = row.region, let margin {
                    for (p, w) in zip(pts, margin) { same(finite(region.margin(p.0, p.1)), w, "\(label) margin\(p)") }
                    #expect(region.edges.map(\.strict) == want["strict"] as? [Bool], "\(label) strict")
                    same(polygonArea(fillPolygons(region.margin, v, scale: scale)), want["area"], "\(label) area", tolerance: 1e-6)
                }
                if let lines = want["lines"] as? [[String: Any]] {
                    let got = drawnLines(row.drawn, v, scale: scale)
                    #expect(got.map(\.count) == lines.map { $0["n"] as! Int }, "\(label) lines")
                    if got.map(\.count) == lines.map({ $0["n"] as! Int }) {
                        for (l, w) in zip(got, lines) {
                            let every = l.enumerated().filter { $0.offset % 10 == 0 || $0.offset == l.count - 1 }.map(\.element)
                            samePoints(every, w["every"], "\(label) line points")
                        }
                    }
                }
            }
            for pair in c["between"] as! [[Any]] {
                let (i, j) = (pair[0] as! Int, pair[1] as! Int)
                samePoints(crossingsBetween(compiled[i].drawn, compiled[j].drawn, v, scale: scale), pair[2], "crossings of “\(texts[i])” and “\(texts[j])”")
            }
            // Pairs that cross nowhere are left out of the data: check a few of them too.
            let listed = Set((c["between"] as! [[Any]]).map { "\($0[0] as! Int),\($0[1] as! Int)" })
            for i in compiled.indices.prefix(8) {
                for j in compiled.indices.prefix(8) where j > i && !listed.contains("\(i),\(j)") {
                    guard compiled[i].error == nil, compiled[j].error == nil, compiled[i].parsed != nil, compiled[j].parsed != nil else { continue }
                    #expect(crossingsBetween(compiled[i].drawn, compiled[j].drawn, v, scale: scale).isEmpty, "no crossings of “\(texts[i])” and “\(texts[j])”")
                }
            }
            let ok = compiled.filter { $0.error == nil }
            let fns = ok.compactMap(\.fn), circles = ok.compactMap(\.circle), gs = ok.compactMap(\.fnOfY)
            samePoints(sorted(snapPoints(fns, v.xMin, v.xMax, samples: 640)), c["snap"], "snap points of \(texts)")
            samePoints(sorted(circleCrossings(circles, fns, perUnit: scale)), c["circles"], "circle crossings of \(texts)")
            samePoints(sorted(sidewaysCrossings(gs, fns, circles, v.yMin, v.yMax, samples: 440)), c["sideways"], "sideways crossings of \(texts)")
        }
    }

    @Test func numbersAreWrittenLikeTheWeb() throws {
        let f = try data["format"] as! [String: Any]
        let values = f["values"] as! [Double]
        #expect(values.map { formatAbs($0, comma: true) } == f["cs"] as! [String])
        #expect(values.map { formatAbs($0, comma: false) } == f["en"] as! [String])
        for pair in f["strings"] as! [[Any]] {
            // Read from the text: JSONSerialization is a bit off on some numbers (0.010101010101010102).
            let text = pair[1] as! String
            let v = try #require(Double(text))
            #expect(abs(v - (pair[0] as! NSNumber).doubleValue) <= 1e-15 * abs(v))
            #expect(jsString(v) == text, "String(\(v))")
        }
        for line in f["lines"] as! [[Any]] {
            let a = line[0] as! [Double], b = line[1] as! [Double]
            #expect(linearThrough(Vec(x: a[0], y: a[1]), Vec(x: b[0], y: b[1]), comma: true) == line[2] as? String, "line through \(a), \(b)")
        }
    }

    @Test func functionCardsWriteRowsLikeTheWeb() throws {
        let forms = try data["forms"] as! [[Any]]
        #expect(forms.count >= 300)
        for entry in forms {
            let comma = entry[0] as! String == "cs"
            let ps = (entry[1] as! [[String]]).map { Vec(x: Double($0[0])!, y: Double($0[1])!) }
            let want = (entry[2] as! [Any]).map { $0 as? String }
            let (a, b, c, d) = (ps[0], ps[1], ps[2], ps[3])
            let r1 = Vec(x: a.x, y: 0), r2 = Vec(x: b.x, y: 0), r3 = Vec(x: c.x, y: 0)
            let got: [String?] = [
                linearThrough(a, b, comma: comma), verticalThrough(a, comma: comma),
                vertexThrough(a, b, comma: comma), interceptThrough(r1, r2, c, comma: comma), generalThrough(a, b, c, comma: comma),
                interceptForm(1, a.x, b.x, comma: comma),
                inflectionThrough(a, b, comma: comma), cubicInterceptThrough([r1, r2, r3], d, comma: comma),
                cubicGeneralThrough([a, b, c, d], comma: comma), cubicInterceptForm(1, [a.x, b.x, c.x], comma: comma),
                sineThrough(a, b, comma: comma), cosineThrough(a, b, comma: comma), tangentThrough(a, b.x, c, comma: comma),
                trigForm(.tan, 1, abs(b.x - a.x) > 1e-9 ? .pi / (2 * abs(b.x - a.x)) : 1, a.x, a.y, comma: comma),
                hyperbolaThrough(a, b, comma: comma), hyperbolaForm(1, a.x, a.y, comma: comma),
                circleThrough(a, b, comma: comma), circleForm(a.x, a.y, (b.x - a.x) * (b.x - a.x) + 0.37, comma: comma),
                ellipseThrough(a, Vec(x: b.x, y: a.y), Vec(x: a.x, y: c.y), comma: comma),
                piLabel(a.x),
            ]
            for (i, (g, w)) in zip(got, want).enumerated() where g != w {
                Issue.record("form \(i) through \(ps): \(g ?? "nil") vs \(w ?? "nil")")
            }
        }
    }

    private func rowDump(_ rows: [GraphRow]) -> String {
        let list: [[Any]] = rows.map { g in
            [g.id, g.text, g.color, g.hidden, g.between ?? NSNull(), g.width ?? NSNull(), g.dash?.rawValue ?? NSNull(), g.fill ?? NSNull()]
        }
        return String(data: try! JSONSerialization.data(withJSONObject: list, options: [.withoutEscapingSlashes]), encoding: .utf8)!
    }

    private func webDump(_ any: Any?) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: any as! [[Any]], options: [.withoutEscapingSlashes]), encoding: .utf8)!
    }

    @Test func opensFilesWrittenByTheWeb() throws {
        let d = try data
        let ctx = TypingContext(center: Vec(x: 0, y: 0))
        guard case .success(let web) = importFile(d["file"] as! String, ctx) else { Issue.record("can't open the web file"); return }
        #expect(rowDump(web.graphs) == webDump(d["fileRows"]))
        guard case .success(let hand) = importFile(d["handFile"] as! String, ctx) else { Issue.record("can't open the hand-written file"); return }
        #expect(rowDump(hand.graphs) == webDump(d["handRows"]))
        // Written again by Swift, the same rows come back.
        let again = exportFile(web, steps: [], stepsTitle: "Construction steps", exerciseTitle: "Exercise")
        guard case .success(let back) = importFile(again, ctx) else { Issue.record("can't open its own file"); return }
        #expect(back.graphs == web.graphs)
        #expect(again.contains("Graphs:\n- (x + 0.6)^2/3.8^2"))
    }

    @Test func writesFilesForTheWeb() throws {
        guard let out = ProcessInfo.processInfo.environment["GEO_PARITY_OUT"] else { return }
        let ctx = TypingContext(center: Vec(x: 0, y: 0))
        guard case .success(let web) = importFile(try data["file"] as! String, ctx) else { return }
        var rows = web.graphs
        rows.append(GraphRow(id: "g50", text: "y = 2,5x − 1 {x ≥ 0}", color: "orange", hidden: true, width: 0, dash: .dashed))
        rows.append(GraphRow(id: "g51", text: "", color: "purple", between: ["g50", "g1"]))
        let text = exportFile(FileContents(construction: Construction(), graphs: rows), steps: [], stepsTitle: "Postup konstrukce",
                              exerciseTitle: "Zadání", graphsTitle: "Grafy")
        guard case .success(let back) = importFile(text, ctx) else { Issue.record("can't open its own file"); return }
        try text.write(toFile: out + "/graphs-1.geoscript", atomically: true, encoding: .utf8)
        try rowDump(back.graphs).write(toFile: out + "/graphs-1.geoscript.json", atomically: true, encoding: .utf8)
    }
}

private func finite(_ v: Double) -> Double? { v.isFinite ? v : nil }

/// Area of counter-clockwise polygons (shoelace).
func polygonArea(_ polys: [[Vec]]) -> Double {
    polys.reduce(0) { sum, p in
        sum + p.indices.reduce(0) { s, i in
            let a = p[i], b = p[(i + 1) % p.count]
            return s + (a.x * b.y - b.x * a.y) / 2
        }
    }
}

/// A parsed row as text with every bracket written, as parity/graphs.ts writes it.
func parsedText(_ p: ParsedRow) -> String {
    func ex(_ e: Expr) -> String {
        switch e {
        case .num(let v): return jsString(v)
        case .x: return "x"
        case .y: return "y"
        case .pi: return "pi"
        case .e: return "e"
        case .neg(let a): return "(-\(ex(a)))"
        case .bin(let op, let a, let b): return "(\(ex(a)) \(op.rawValue) \(ex(b)))"
        case .fn(let name, let a): return "\(name.rawValue)[\(ex(a))]"
        case .call(let name, let a): return "\(name)<\(ex(a))>"
        }
    }
    func chain(_ r: Restriction) -> String {
        r.terms.enumerated().map { i, t in (i > 0 ? " \(r.ops[i - 1].rawValue) " : "") + ex(t) }.joined()
    }
    let main: String
    switch p.kind {
    case .y(let e, let bare): main = "y\(bare ? "?" : "") = \(ex(e))"
    case .def(let name, let e): main = "\(name)(x) = \(ex(e))"
    case .x(let e): main = "x = \(ex(e))"
    case .circle(let lhs, let rhs, let m, let n): main = "circle \(ex(lhs)) = \(ex(rhs)) @ \(ex(m)), \(ex(n))"
    case .curve(let lhs, let rhs): main = "curve \(ex(lhs)) = \(ex(rhs))"
    case .region(let r): main = "region \(chain(r))"
    }
    return main + p.restrictions.map { " {\(chain($0))}" }.joined()
}
