import Foundation
import Testing
@testable import GeoEngine

// The web app's graph tests (src/engine/graph/*.test.ts), ported.

private func rows(_ texts: String...) -> [GraphRow] {
    texts.enumerated().map { GraphRow(id: "g\($0)", text: $1, color: "red") }
}

private func one(_ text: String) -> CompiledRow { compileRows(rows(text))[0] }

/// The value of a single typed row at x.
private func at(_ text: String, _ x: Double) -> Double {
    guard let fn = one(text).fn else {
        Issue.record("\(text): \(one(text).error?.key ?? "no function")")
        return .nan
    }
    return fn(x)
}

private func near(_ a: Double, _ b: Double, _ digits: Double = 2) -> Bool { abs(a - b) < pow(10, -digits) / 2 }

private func err(_ text: String) -> GraphError? {
    if case .failure(let e) = parseRow(text) { return e }
    return nil
}

@Suite struct GraphRowsTests {
    @Test func readsTheSchoolWayOfWriting() {
        #expect(at("y = 2x", 3) == 6)
        #expect(at("x^2 + 2x + 3", -1) == 2)
        #expect(at("y = x² + 2x + 3", 2) == 11)
        #expect(at("y = 3(x + 1)", 1) == 6)
        #expect(at("y = 3,5x", 2) == 7)
        #expect(at("y = 0.5x", 4) == 2)
        #expect(at("y = 2 · x − 1", 2) == 3)
        #expect(near(at("y = 2π", 0), 2 * .pi))
    }

    @Test func keepsTheOrderOfOperations() {
        #expect(at("y = -x^2", 3) == -9)
        #expect(at("y = 2^3^2", 0) == 512)
        #expect(at("y = 2^-x", 1) == 0.5)
        #expect(at("y = 1/2x", 4) == 2)
        #expect(at("y = 6/(2x)", 1) == 3)
        #expect(at("y = x - 3", 1) == -2)
    }

    @Test func knowsTheStandardFunctions() {
        #expect(near(at("y = sin x", .pi / 2), 1))
        #expect(near(at("y = sin(2x)", .pi / 4), 1))
        #expect(near(at("y = sin x cos x", .pi / 4), 0.5))
        #expect(near(at("y = xsinx", .pi / 2), .pi / 2))
        #expect(near(at("y = sin^2 x + cos^2 x", 0.7), 1))
        #expect(at("y = √x", 9) == 3)
        #expect(at("y = √(x + 7)", 9) == 4)
        #expect(at("y = sqrt(x)", 16) == 4)
        #expect(at("y = |x - 5|", 2) == 3)
        #expect(at("y = |x||x|", -3) == 9)
        #expect(at("y = abs(x)", -2) == 2)
        #expect(near(at("y = ln e", 0), 1))
        #expect(near(at("y = log 100", 0), 2))
        #expect(near(at("y = exp(x)", 1), M_E))
        #expect(near(at("y = tan x", .pi / 4), 1))
        #expect(near(at("y = x^(1/3)", -8), -2))
        #expect(at("y = √x", -1).isNaN)
    }

    @Test func definesFunctionsOtherRowsUse() {
        let c = compileRows(rows("f(x) = sin x", "y = 2f(x) - 3"))
        #expect(near(c[0].fn!(.pi / 2), 1))
        #expect(near(c[1].fn!(.pi / 2), -1))
        // A definition can come later than its use, and functions can call each other.
        let d = compileRows(rows("y = g(x + 1)", "h(x) = x^2", "g(x) = h(x) + 1"))
        #expect(d[0].fn!(1) == 5)
        #expect(d[2].fn!(2) == 5)
    }

    @Test func reportsWhatIsWrong() {
        #expect(err("y = 3x +")?.key == "graph.error.end")
        #expect(err("y = (x + 1")?.key == "graph.error.end")
        #expect(err("y = x )")?.key == "graph.error.syntax")
        #expect(err("y = 2a") == GraphError("graph.error.unknownName", name: "a"))
        #expect(err("x(x) = 2") == GraphError("graph.error.reserved", name: "x"))
        #expect(err("2 = 3")?.key == "graph.error.form")
        #expect(err("y ≤ x = 2")?.key == "graph.error.syntax")
        #expect(err("y = x # 2")?.key == "graph.error.syntax")
        #expect(one("y = q(x)").error == GraphError("graph.error.unknownFunction", name: "q"))
        let cycle = compileRows(rows("f(x) = g(x)", "g(x) = f(x)"))
        #expect(cycle[0].error?.key == "graph.error.cycle")
        #expect(cycle[1].error?.key == "graph.error.cycle")
        #expect(compileRows(rows("f(x) = x", "f(x) = 2x"))[0].error == GraphError("graph.error.duplicate", name: "f"))
        // A restriction that refers to its own function draws nothing instead of looping.
        #expect(compileRows(rows("f(x) = x {f(x) > 0}", "y = f(x)"))[1].fn!(1).isNaN)
    }

    @Test func skipsEmptyRows() {
        let r = one("  ")
        #expect(r.parsed == nil && r.fn == nil && r.error == nil)
    }
}

@Suite struct GraphSamplingTests {
    let view = GraphView(xMin: -10, xMax: 10, yMin: -7, yMax: 7)

    @Test func drawsAContinuousFunctionAsOneLine() {
        let lines = sampleCurve({ $0 * $0 + 2 * $0 + 3 }, view, pixels: 800)
        #expect(lines.count == 1)
        #expect(lines[0][0].x == -10)
        #expect(near(lines[0].last!.x, 10))
    }

    @Test func breaksAtAsymptotes() {
        #expect(sampleCurve({ 1 / $0 }, view, pixels: 800).count == 2)
        // tan x has jumps at ±π/2, ±3π/2, ±5π/2 inside −10…10: seven pieces.
        #expect(sampleCurve(tan, view, pixels: 800).count == 7)
    }

    @Test func keepsSteepCurvesWhole() {
        #expect(sampleCurve({ pow($0, 9) }, view, pixels: 800).count == 1)
        #expect(sampleCurve({ 30 * sin(5 * $0) }, view, pixels: 800).count == 1)
    }

    @Test func startsAndStopsWhereDefined() {
        let sqrt = sampleCurve({ $0.squareRoot() }, view, pixels: 800)
        #expect(near(sqrt[0][0].x, 0, 6))
        #expect(sampleCurve({ log(abs($0)) }, view, pixels: 800).count == 2)
        #expect(sampleCurve({ _ in .nan }, view, pixels: 800).isEmpty)
    }

    @Test func keepsOffScreenValuesNear() {
        let line = sampleCurve({ pow($0, 9) }, view, pixels: 800)[0]
        #expect(line.map { abs($0.y) }.max()! <= 7 + 14 * 2)
    }
}

@Suite struct GraphCurveTests {
    let view = GraphView(xMin: -5, xMax: 5, yMin: -4, yMax: 4)
    let scale = 60.0

    @Test func drawsAnEllipseAsOneClosedLine() {
        let r = one("(x - 1)^2/3^2 + y^2/2^2 = 1")
        guard case .curve = r.parsed?.kind else { Issue.record("not a curve"); return }
        let lines = drawnLines(r.drawn, view, scale: scale)
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.count > 100)
        for p in line { #expect(near(pow((p.x - 1) / 3, 2) + pow(p.y / 2, 2), 1, 6)) }
        #expect(hypot(line[0].x - line.last!.x, line[0].y - line.last!.y) < 0.1)
    }

    @Test func keepsOnlyTheArcItsRestrictionAllows() {
        let lines = drawnLines(one("x^2/4 + y^2 = 1 {y ≥ 0}").drawn, view, scale: scale)
        #expect(lines.count == 1)
        for p in lines[0] { #expect(p.y > -1e-6) }
        #expect(near(lines[0].map(\.x).min()!, -2))
        #expect(near(lines[0].map(\.x).max()!, 2))
    }

    @Test func drawsNothingAtAJump() {
        for l in contour({ x, y in 1 / x - y }, nil, view, scale: scale) {
            for p in l { #expect(abs(1 / p.x - p.y) < 1e-6) }
        }
    }

    @Test func landsClicksOnTheCurve() {
        let r = one("x^2/4 + y^2 = 1")
        #expect(projectOn(r.implicit!.f, Vec(x: 0.1, y: 1.3))!.y > 0.9)
        let p = landOn(r.drawn, snapped: Vec(x: 1, y: 1), raw: Vec(x: 1.02, y: 0.9), grid: 0.5, reach: 0.2)!
        #expect(near(p.x, 1, 9))
        #expect(near(p.y, 0.75.squareRoot(), 9))
    }

    @Test func fillsADisc() {
        let r = one("(x - 1)^2 + y^2 ≤ 4")
        #expect(near(polygonArea(fillPolygons(r.region!.margin, view, scale: scale)), 4 * .pi))
        #expect(r.region!.edges.count == 1)
        let c = r.region!.edges[0].drawn.circle!
        #expect(c.m == 1 && c.n == 0 && c.r == 2)
    }

    @Test func fillsABand() {
        let r = one("-1 ≤ y < 2")
        #expect(near(polygonArea(fillPolygons(r.region!.margin, view, scale: scale)), 30, 0))
        #expect(r.region!.edges.map { $0.drawn.fn!(0) } == [-1, 2])
        #expect(r.region!.edges.map(\.strict) == [false, true])
    }

    @Test func fillsUnderAGraphInsideItsRestrictions() {
        let r = one("y ≤ x^2 {0 ≤ x ≤ 2}{y ≥ 0}")
        #expect(near(polygonArea(fillPolygons(r.region!.margin, view, scale: scale)), 8 / 3))
        #expect(r.region!.edges[0].drawn.fn!(1) == 1)
        #expect(r.region!.edges[0].drawn.fn!(3).isNaN)
    }

    @Test func shadesSidewaysAndAnyInequality() {
        let s = one("x ≥ y^2")
        #expect(s.region!.edges[0].drawn.fnOfY!(2) == 4)
        #expect(s.region!.margin(5, 2) > 0)
        #expect(s.region!.margin(3, 2) < 0)
        let e = one("x^2/4 + y^2 < 1")
        #expect(e.region!.edges[0].drawn.implicit != nil)
        #expect(near(polygonArea(fillPolygons(e.region!.margin, view, scale: scale)), 2 * .pi))
    }
}

@Suite struct GraphRestrictTests {
    @Test func cutsAFunctionToAnInterval() {
        let f = one("y = x^2 {0 ≤ x ≤ 3}").fn!
        #expect(f(2) == 4 && f(0) == 0 && f(3) == 9)
        #expect(f(-1).isNaN && f(3.1).isNaN)
    }

    @Test func readsEveryWayOfWritingThem() {
        #expect(one("y = x {x >= 1}").fn!(0).isNaN)
        #expect(one("y = x {x<=1}").fn!(0) == 0)
        let g = one("y = 2x {x > 0}{y < 4}").fn!
        #expect(g(1) == 2)
        #expect(g(3).isNaN && g(-1).isNaN)
        #expect(one("y = x {5 > x > 2}").fn!(3) == 3)
    }

    @Test func carryOverToCallers() {
        let y = compileRows(rows("f(x) = x {x > 0}", "y = f(x) + 1"))[1].fn!
        #expect(y(2) == 3)
        #expect(y(-2).isNaN)
    }

    @Test func reportBrokenRestrictions() {
        #expect(err("y = x {x}")?.key == "graph.error.restriction")
        #expect(err("y = x {x > 1")?.key == "graph.error.restriction")
        #expect(err("y = x {x > 1} 2")?.key == "graph.error.restriction")
        #expect(err("{x > 1}")?.key == "graph.error.syntax")
        #expect(one("y = x {q(x) > 1}").error == GraphError("graph.error.unknownFunction", name: "q"))
    }

    @Test func sidewaysRowsAreFunctionsOfY() {
        let r = one("x = y^2 - 1 {-2 ≤ y ≤ 2}")
        #expect(r.fn == nil)
        #expect(r.fnOfY!(2) == 3)
        #expect(r.fnOfY!(3).isNaN)
        #expect(one("x = 0 {57 ≤ y ≤ 100}").fnOfY!(60) == 0)
        #expect(err("x = x + 1") == GraphError("graph.error.form"))
        #expect(err("y = y + 1") == GraphError("graph.error.form"))
        let lines = sampleCurve(one("x = 0 {57 ≤ y ≤ 100}").fnOfY!, GraphView(xMin: 0, xMax: 120, yMin: -20, yMax: 100), pixels: 600)
        #expect(lines.count == 1)
        #expect(near(lines[0][0].x, 57, 6))
        #expect(near(lines[0].last!.x, 100, 6))
    }

    @Test func restrictedCirclesDrawTheirArc() {
        let c = one("(x - 5)^2 + (y - 100)^2 = 25 {y ≥ 100}").circle!
        let arcs = sampleArc(c, perUnit: 10)
        #expect(arcs.count == 1)
        for p in [arcs[0][0], arcs[0].last!] { #expect(near(p.y, 100, 6)) }
        #expect(near(arcs[0].map(\.y).max()!, 105))
        #expect(sampleArc(one("x^2 + y^2 = 1 {x ≥ 0}").circle!, perUnit: 50).count == 1)
        let pts = circleCrossings([one("x^2 + y^2 = 4 {y ≥ 0}").circle!], [], perUnit: 50)
        #expect(pts.count == 3)
        #expect(!pts.contains { $0.y < -1 })
    }

    @Test func writesIntervals() {
        #expect(withoutWhere("y = x^2 {0 ≤ x ≤ 3}{y > 1}") == "y = x^2")
        #expect(intervalText("y = x^2 {0 ≤ x ≤ 3}", alongX: true, Vec(x: 5, y: 25), Vec(x: -1.5, y: 2.25), comma: true) == "y = x^2 {-1,5 ≤ x ≤ 5}")
        #expect(intervalText("x = y^2", alongX: false, Vec(x: 4, y: 2), Vec(x: 1.0 / 9, y: 1.0 / 3), comma: false) == "x = y^2 {1/3 ≤ y ≤ 2}")
    }

    @Test func keepsTheArcOnTheSideOfItsEnds() {
        let c = "x^2 + y^2 = 5^2"
        #expect(arcText(c, Vec(x: -5, y: 0), Vec(x: 5, y: 0), keep: Vec(x: 0, y: 5), comma: false) == "x^2 + y^2 = 5^2 {y ≥ 0}")
        #expect(arcText(c, Vec(x: 0, y: 5), Vec(x: 0, y: -5), keep: Vec(x: -5, y: 0), comma: false) == "x^2 + y^2 = 5^2 {x ≤ 0}")
        let text = arcText(c, Vec(x: -5, y: 0), Vec(x: 0, y: 5), keep: Vec(x: -3, y: 4), comma: false)
        #expect(text == "x^2 + y^2 = 5^2 {y ≥ x + 5}")
        let r = one(text!)
        #expect(r.circle!.inside!(-3, 4))
        #expect(!r.circle!.inside!(3, -4))
        #expect(arcText(c, Vec(x: -5, y: 0), Vec(x: -5, y: 0), keep: Vec(x: 0, y: 5), comma: false) == nil)
        #expect(arcText(c, Vec(x: -5, y: 0), Vec(x: 5, y: 0), keep: Vec(x: 5, y: 0), comma: false) == nil)
    }

    @Test func landsClicksOnTheGraph() {
        let piece = one("y = x^2 {0 ≤ x ≤ 1}").drawn
        let full = one("y = x^2").drawn
        #expect(landOn(full, snapped: Vec(x: 3, y: 0), raw: Vec(x: 3, y: 0.2), grid: 1, reach: 0.5) == Vec(x: 3, y: 9))
        #expect(landOn(piece, snapped: Vec(x: 3, y: 0), raw: Vec(x: 3, y: 0.2), grid: 1, reach: 0.5) == nil)
        #expect(landOn(one("x = 2y").drawn, snapped: Vec(x: 0, y: 3), raw: Vec(x: 0, y: 3), grid: 1, reach: 0.5) == Vec(x: 6, y: 3))
        let circle = one("x^2 + y^2 = 5^2").drawn
        #expect(landOn(circle, snapped: Vec(x: 4, y: 4), raw: Vec(x: 3.1, y: 3.9), grid: 1, reach: 0.5) == Vec(x: 3, y: 4))
        let far = landOn(circle, snapped: Vec(x: 0, y: 0), raw: Vec(x: 3.5, y: 3.5), grid: 1, reach: 0.05)!
        #expect(near(hypot(far.x, far.y), 5))
    }

    @Test func measuresTheDistanceToAGraph() {
        #expect(distanceToLines([[Vec(x: 0, y: 0), Vec(x: 10, y: 0)]], Vec(x: 5, y: 2)) == 2)
        #expect(distanceToLines([[Vec(x: 0, y: 0), Vec(x: 10, y: 0)]], Vec(x: 13, y: 4)) == 5)
    }
}

@Suite struct GraphCrossingTests {
    private func fns(_ texts: String...) -> [Fn] {
        compileRows(texts.enumerated().map { GraphRow(id: "g\($0)", text: $1, color: "red") }).map { $0.fn! }
    }

    private func sorted(_ ps: [Vec]) -> [Vec] { ps.sorted { $0.x < $1.x } }

    @Test func findsWhereTwoLinesCross() {
        #expect(intersections(fns("y = 2x + 1", "y = -x + 4"), -10, 10, samples: 1000) == [Vec(x: 1, y: 3)])
    }

    @Test func findsIrrationalCrossings() {
        let ps = sorted(intersections(fns("y = 1.25x + 0.5", "y = 0.5(x - 1)^2 - 2"), -10, 10, samples: 1000))
        #expect(ps.count == 2)
        let r = (4.5 * 4.5 + 16).squareRoot()
        #expect(near(ps[0].x, (4.5 - r) / 2, 12))
        #expect(near(ps[1].x, (4.5 + r) / 2, 12))
        #expect(near(ps[1].y, 1.25 * ps[1].x + 0.5, 12))
    }

    @Test func findsATangent() {
        #expect(intersections(fns("y = x^2", "y = 2x - 1"), -10, 10, samples: 1000) == [Vec(x: 1, y: 1)])
    }

    @Test func takesEveryPair() {
        #expect(sorted(intersections(fns("y = x", "y = -x", "y = 2"), -10, 10, samples: 1000)) == [Vec(x: -2, y: 2), Vec(x: 0, y: 0), Vec(x: 2, y: 2)])
    }

    @Test func skipsJumpsParallelsAndTheSameGraph() {
        #expect(intersections(fns("y = 1/x", "y = 0"), -10, 10, samples: 1000).isEmpty)
        #expect(intersections(fns("y = tan x", "y = 100"), 1.4, 1.7, samples: 1000).count == 1)
        #expect(intersections(fns("y = x", "y = x + 1"), -10, 10, samples: 1000).isEmpty)
        #expect(intersections(fns("y = 2x", "y = x + x"), -10, 10, samples: 1000).isEmpty)
        #expect(intersections(fns("y = x", "y = 5"), -2, 2, samples: 1000).isEmpty)
        let piece: Fn = { $0 >= 0 && $0 <= 2 ? $0 * $0 : .nan }
        #expect(intersections([{ $0 * $0 }, piece], -5, 5, samples: 200).isEmpty)
    }

    @Test func offersTheAxes() {
        #expect(sorted(snapPoints(fns("y = x^2 - 4"), -10, 10, samples: 1000)) == [Vec(x: -2, y: 0), Vec(x: 0, y: -4), Vec(x: 2, y: 0)])
        #expect(snapPoints(fns("y = 2x", "y = 0"), -10, 10, samples: 1000) == [Vec(x: 0, y: 0)])
        #expect(snapPoints(fns("y = x + 1"), 1, 10, samples: 1000).isEmpty)
    }

    @Test func findsCrossingsOfSidewaysRows() {
        let g = one("x = y^2 - 4").fnOfY!
        func pts(_ fns: [Fn], _ gs: [Fn]) -> [Vec] {
            sidewaysCrossings(gs, fns, [], -10, 10, samples: 400).map { Vec(x: jsToFixedNumber($0.x, 6), y: jsToFixedNumber($0.y, 6)) }
        }
        let axes = pts([], [g])
        for p in [Vec(x: 0, y: -2), Vec(x: 0, y: 2), Vec(x: -4, y: 0)] { #expect(axes.contains(p)) }
        #expect(pts([{ $0 }], [g]).filter { $0.x == $0.y }.count == 2)
        let c = one("x^2 + y^2 = 4^2 {y ≥ 0}").circle!
        let onCircle = sidewaysCrossings([g], [], [c], -10, 10, samples: 400).filter { abs(hypot($0.x, $0.y) - 4) < 1e-6 }
        #expect(!onCircle.isEmpty)
        #expect(onCircle.allSatisfy { $0.y >= 0 })
        let both = pts([], [g, one("x = 5").fnOfY!])
        #expect(both.contains(Vec(x: 5, y: 3)) && both.contains(Vec(x: 5, y: -3)))
    }

    @Test func mirrorsRowsInYEqualsX() {
        #expect(mirrorText("y = 2x + 1") == "x = 2y + 1")
        #expect(mirrorText("y = 1/2(x + 2)x(x - 3)") == "x = 1/2(y + 2)y(y - 3)")
        #expect(linearThrough(mirror(Vec(x: 1, y: 3)), mirror(Vec(x: 5, y: 3)), comma: false) == nil)
    }

    private let view = GraphView(xMin: -10, xMax: 10, yMin: -10, yMax: 10)
    private func between(_ a: String, _ b: String) -> [Vec] { crossingsBetween(one(a).drawn, one(b).drawn, view, scale: 40) }

    @Test func findsCrossingsOfTwoGraphs() {
        let ps = between("y = x^2", "y = x + 1.5")
        #expect(ps.count == 2)
        #expect(near(ps[0].x, (1 - 7.0.squareRoot()) / 2))
        #expect(near(ps[1].x, (1 + 7.0.squareRoot()) / 2))
        #expect(between("y = x", "y = -x + 2") == [Vec(x: 1, y: 1)])
        #expect(between("x^2 + y^2 = 5^2", "y = 3") == [Vec(x: -4, y: 3), Vec(x: 4, y: 3)])
        #expect(between("x^2 + y^2 = 5^2", "(x - 8)^2 + y^2 = 5^2") == [Vec(x: 4, y: -3), Vec(x: 4, y: 3)])
        #expect(between("x = 2", "y = x^2") == [Vec(x: 2, y: 4)])
        let piece = between("y = x^2 {x ≥ 0}", "y = x + 1.5")
        #expect(piece.count == 1)
        #expect(near(piece[0].x, (1 + 7.0.squareRoot()) / 2))
        #expect(between("y = x^2 + 1", "y = -1").isEmpty)
    }
}

@Suite struct GraphFillTests {
    /// The side of row `i` (compiled whole, as the Fill tool does) where p is.
    private func side(_ texts: [String], _ i: Int, _ p: Vec) -> String? {
        let rows = texts.enumerated().map { k, t in GraphRow(id: "g\(k)", text: k == i ? withoutWhere(t) : t, color: "red") }
        return sideText(texts[i], compileRows(rows)[i], p)
    }

    @Test func turnsEachGraphIntoAnInequality() {
        #expect(side(["y = 2x + 1"], 0, Vec(x: 0, y: 0)) == "y ≤ 2x + 1")
        #expect(side(["y = 2x + 1"], 0, Vec(x: 0, y: 3)) == "y ≥ 2x + 1")
        #expect(side(["x^2"], 0, Vec(x: 0, y: 3)) == "y ≥ x^2")
        #expect(side(["x = 2y + 1"], 0, Vec(x: 5, y: 0)) == "x ≥ 2y + 1")
        #expect(side(["(x - 1)^2 + y^2 = 2^2"], 0, Vec(x: 1, y: 0)) == "(x - 1)^2 + y^2 ≤ 2^2")
        #expect(side(["x^2/3^2 + y^2/2^2 = 1"], 0, Vec(x: 5, y: 0)) == "x^2/3^2 + y^2/2^2 ≥ 1")
        #expect(side(["f(x) = sin x", "y = 2f(x)"], 0, Vec(x: 0, y: -1)) == "y ≤ f(x)")
        #expect(side(["y = 1 {0 ≤ x ≤ 1}"], 0, Vec(x: 5, y: 3)) == "y ≥ 1")
        #expect(side(["y = 2x + 1"], 0, Vec(x: 1, y: 3)) == nil)
        #expect(side(["y = √x"], 0, Vec(x: -1, y: 3)) == nil)
    }

    @Test func putsTheOtherPicksInBraces() {
        let text = fillText(["y ≤ 4 - x^2", "y ≥ 0"])
        #expect(text == "y ≤ 4 - x^2 {y ≥ 0}")
        let r = one(text).region!
        #expect(r.margin(0, 1) > 0)
        #expect(r.margin(0, -1) < 0)
        #expect(r.margin(3, 0.5) < 0)
    }
}

@Suite struct GraphStateTests {
    @Test func addsRowsInTurnColoursAndRemovesTheirCrossings() {
        var g = GraphState().adding("y = x").adding("y = 2")
        #expect(g.rows.map(\.color) == ["red", "blue"])
        g = g.addingCrossing("g1", "g2")
        #expect(g.rows[2].between == ["g1", "g2"])
        #expect(g.removing("g2").rows.map(\.id) == ["g1"])
        #expect(GraphState(fromRows: [GraphRow(id: "g7", text: "", color: "red")]).nextId == 8)
    }

    @Test func keepsOnlySoundRowsFromAFile() {
        let rows = validGraphs([
            ["id": "g1", "text": "y = x", "color": "red", "width": 3, "dash": "dotted", "fill": 2],
            ["id": "g1", "text": "y = 2", "color": "red"],
            ["id": "x2", "text": "y = 2", "color": "red"],
            ["id": "g3", "text": "y = 2", "color": "mauve"],
            ["id": "g4", "text": "", "color": "blue", "between": ["g1", "g9"]],
            ["id": "g5", "text": "y = 3", "color": "#00ff00", "hidden": true],
        ])
        #expect(rows.map(\.id) == ["g1", "g5"])
        #expect(rows[0].width == 3 && rows[0].dash == .dotted && rows[0].fill == nil)
        #expect(rows[1].hidden)
    }
}
