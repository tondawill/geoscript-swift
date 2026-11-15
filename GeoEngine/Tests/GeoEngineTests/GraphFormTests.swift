import Foundation
import Testing
@testable import GeoEngine

// The web app's tests of the function cards (linear, quadratic, cubic, trig, hyperbola, circle,
// ellipse .test.ts), ported.

private func p(_ x: Double, _ y: Double) -> Vec { Vec(x: x, y: y) }
private func row(_ text: String) -> CompiledRow { compileRows([GraphRow(id: "g1", text: text, color: "red")])[0] }
private func at(_ text: String, _ x: Double) -> Double { row(text).fn!(x) }
private func near(_ a: Double, _ b: Double, _ digits: Double = 2) -> Bool { abs(a - b) < pow(10, -digits) / 2 }

@Suite struct GraphFormTests {
    @Test func linear() {
        #expect(linearThrough(p(1, 3), p(2, 5), comma: false) == "y = 2x + 1")
        #expect(linearThrough(p(0, 0), p(1, 1), comma: false) == "y = x")
        #expect(linearThrough(p(0, 2), p(2, 0), comma: false) == "y = -x + 2")
        #expect(linearThrough(p(-1, 3), p(4, 3), comma: false) == "y = 3")
        #expect(linearThrough(p(0, -2), p(2, -1), comma: true) == "y = 0,5x - 2")
        #expect(linearThrough(p(0.1, 0.2), p(0.2, 0.4), comma: false) == "y = 2x")
        #expect(linearThrough(p(0, 0), p(3, 1), comma: false) == "y = 1/3x")
        #expect(linearThrough(p(0.5, 0.2), p(2, 0.7), comma: false) == "y = 1/3x + 1/30")
        #expect(linearThrough(p(0, 0), p(.pi, 1), comma: false) == "y = 0.3183098862x")
        #expect(linearThrough(p(1, 0), p(1, 5), comma: false) == nil)
        #expect(verticalThrough(p(-2.5, 1), comma: true) == "x = -2,5")
        #expect(row(verticalThrough(p(3, 0), comma: false)).fnOfY!(7) == 3)
        for comma in [true, false] {
            for (a, b) in [(p(1, 3), p(2, 5)), (p(-1.5, 2), p(0.5, -1)), (p(1, 0), p(4, 1)), (p(0, 2), p(7, -1))] {
                let f = row(linearThrough(a, b, comma: comma)!).fn!
                #expect(near(f(a.x), a.y, 9) && near(f(b.x), b.y, 9))
            }
        }
    }

    @Test func parabola() {
        #expect(vertexThrough(p(1, 3), p(2, 5), comma: false) == "y = 2(x - 1)^2 + 3")
        #expect(vertexThrough(p(-2, 0), p(-1, -1), comma: false) == "y = -(x + 2)^2")
        #expect(vertexThrough(p(1.5, -2), p(3.5, 0), comma: true) == "y = 0,5(x - 1,5)^2 - 2")
        #expect(vertexThrough(p(0, 0), p(3, -2), comma: true) == "y = -2/9x^2")
        #expect(vertexThrough(p(1, 0), p(1, 5), comma: false) == nil)
        #expect(vertexThrough(p(1, 2), p(4, 2), comma: false) == nil)
        #expect(interceptThrough(p(1, 0), p(-3, 0), p(-1, 2), comma: false) == "y = -0.5(x + 3)(x - 1)")
        #expect(interceptThrough(p(3, 0), p(0, 0), p(1, -4), comma: false) == "y = 2x(x - 3)")
        #expect(interceptThrough(p(2, 0), p(2, 0), p(3, 3), comma: false) == "y = 3(x - 2)^2")
        #expect(interceptThrough(p(-1, 0), p(3, 0), p(5, 0), comma: false) == nil)
        #expect(interceptThrough(p(-1, 0), p(3, 0), p(3, 2), comma: false) == nil)
        #expect(generalThrough(p(-2, 3), p(0, -1), p(4, 3), comma: false) == "y = 0.5x^2 - x - 1")
        #expect(generalThrough(p(0, 0), p(3, 3), p(-3, 1), comma: false) == "y = 2/9x^2 + 1/3x")
        #expect(generalThrough(p(0, 1), p(1, 3), p(2, 5), comma: false) == nil)
        for comma in [true, false] {
            for pts in [[p(-2, 3), p(0, -1), p(4, 3)], [p(-1.5, 2), p(0.5, -1), p(3, 4)], [p(-7, 1), p(2, 2), p(5, -3)]] {
                let f = row(generalThrough(pts[0], pts[1], pts[2], comma: comma)!).fn!
                for q in pts { #expect(near(f(q.x), q.y, 9)) }
            }
        }
    }

    @Test func cubic() {
        #expect(inflectionThrough(p(1, 3), p(2, 5), comma: false) == "y = 2(x - 1)^3 + 3")
        #expect(inflectionThrough(p(-1, 0), p(1, 4), comma: true) == "y = 0,5(x + 1)^3")
        #expect(inflectionThrough(p(1, 3), p(4, 3), comma: false) == nil)
        #expect(cubicInterceptForm(1, [3, -2, 0], comma: false) == "y = (x + 2)x(x - 3)")
        #expect(cubicInterceptForm(-0.5, [1, 1, -2], comma: true) == "y = -0,5(x + 2)(x - 1)^2")
        #expect(cubicInterceptForm(2, [0, 0, 0], comma: false) == "y = 2x^3")
        let roots = [p(-2, 0), p(0, 0), p(3, 0)]
        #expect(cubicInterceptThrough(roots, p(1, -3), comma: false) == "y = 0.5(x + 2)x(x - 3)")
        #expect(cubicInterceptThrough(roots, p(3, 2), comma: false) == nil)
        let ps = [-1.0, 0, 1, 2].map { p($0, $0 * $0 * $0 - 2 * $0 * $0 + 3) }
        #expect(cubicGeneralThrough(ps, comma: false) == "y = x^3 - 2x^2 + 3")
        let odd = [p(-2, 1), p(0.5, -1), p(1, 2), p(3, 0)]
        let text = cubicGeneralThrough(odd, comma: false)!
        for q in odd { #expect(near(at(text, q.x), q.y, 6)) }
        #expect(cubicCoefficients([0.0, 1, 2, 3].map { p($0, $0 * $0) }) == nil)
    }

    @Test func trig() {
        #expect(piFraction(.pi) == "π")
        #expect(piFraction(-.pi / 2) == "π/2")
        #expect(piFraction(3 * .pi / 4) == "3π/4")
        #expect(piFraction(1) == nil)
        #expect(piLabel(-3 * .pi / 2) == "−3π/2")
        #expect(sineThrough(p(0, 0), p(.pi / 2, 1), comma: false) == "y = sin(x)")
        #expect(trigForm(.cos, 2, 0.5, .pi, 1, comma: true) == "y = 2cos(0,5(x - π)) + 1")
        #expect(trigForm(.tan, -1, .pi / 2, -1, 0, comma: false) == "y = -tan(π/2(x + 1))")
        let s = sineThrough(p(.pi / 4, 1), p(.pi, 3), comma: false)!
        #expect(s == "y = 2sin(2/3(x - π/4)) + 1")
        #expect(near(at(s, .pi), 3))
        let back = sineThrough(p(0, 0), p(-.pi / 2, 2), comma: false)!
        #expect(near(at(back, -.pi / 2), 2))
        #expect(tangentThrough(p(0, 1), .pi / 2, p(.pi / 4, 3), comma: false) == "y = 2tan(x) + 1")
        #expect(tangentThrough(p(0, 0), .pi / 2, p(.pi / 2, 1), comma: false) == nil)
        #expect(tangentAsymptotes(0, .pi / 2, -4, 4).map { jsToFixedNumber($0 / .pi, 6) } == [-0.5, 0.5])
        #expect(near(piGridStep(51.8).major, .pi / 2))
        #expect(near(piGridStep(5).major, 8 * .pi))
    }

    @Test func hyperbola() {
        #expect(hyperbolaThrough(p(1, 3), p(2, 5), comma: false) == "y = 2/(x - 1) + 3")
        #expect(hyperbolaThrough(p(0, 0), p(1, -1), comma: false) == "y = -1/x")
        #expect(hyperbolaThrough(p(-2, -1), p(1, -8.0 / 9), comma: false) == "y = 1/(3(x + 2)) - 1")
        #expect(hyperbolaThrough(p(0, 0), p(3, -1.0 / 9), comma: true) == "y = -1/(3x)")
        #expect(hyperbolaForm(2.0 / 3, 1, 0, comma: false) == "y = 2/(3(x - 1))")
        #expect(hyperbolaThrough(p(1, 2), p(1, 5), comma: false) == nil)
        for (c, q) in [(p(1, 3), p(2, 5)), (p(-2, -1), p(1, -8.0 / 9)), (p(2, 1), p(-0.7, 3.3))] {
            let f = row(hyperbolaThrough(c, q, comma: true)!).fn!
            #expect(near(f(q.x), q.y, 9))
            #expect(near(f(2 * c.x - q.x), 2 * c.y - q.y, 9))
            #expect(!f(c.x).isFinite)
        }
    }

    @Test func circleAndEllipse() {
        #expect(circleThrough(p(0, 0), p(3, 0), comma: false) == "x^2 + y^2 = 3^2")
        #expect(circleThrough(p(1, -2), p(4, 2), comma: false) == "(x - 1)^2 + (y + 2)^2 = 5^2")
        #expect(circleThrough(p(0, 1), p(0, 2.5), comma: true) == "x^2 + (y - 1)^2 = 1,5^2")
        #expect(circleThrough(p(1, -2), p(2, 0), comma: false) == "(x - 1)^2 + (y + 2)^2 = (√5)^2")
        #expect(circleForm(0, 0, 1.0 / 9, comma: false) == "x^2 + y^2 = (1/3)^2")
        #expect(circleForm(0, 0, 4.0 / 3, comma: false) == "x^2 + y^2 = (√(4/3))^2")
        #expect(circleThrough(p(1, 2), p(1, 2), comma: false) == nil)
        for (c, q) in [(p(1, -2), p(2, 0)), (p(0, 0), p(0.5, 0.5)), (p(2.3, -1.7), p(-0.4, 3.1))] {
            let k = row(circleThrough(c, q, comma: true)!).circle!
            #expect(near(k.m, c.x, 9) && near(k.n, c.y, 9) && near(k.r, hypot(q.x - c.x, q.y - c.y), 9))
        }
        #expect(ellipseThrough(p(0, 0), p(3, 0), p(0, 2), comma: false) == "x^2/3^2 + y^2/2^2 = 1")
        #expect(ellipseThrough(p(1, -2), p(-0.5, -2), p(1, -6), comma: true) == "(x - 1)^2/1,5^2 + (y + 2)^2/4^2 = 1")
        #expect(ellipseThrough(p(0, 0), p(0, 0), p(0, 2), comma: false) == nil)
        let f = row(ellipseThrough(p(1, -2), p(4, -2), p(1, 0), comma: false)!).implicit!.f
        for (x, y) in [(4.0, -2.0), (-2, -2), (1, 0), (1, -4)] { #expect(abs(f(x, y)) < 1e-12) }
    }

    @Test func sidewaysPlacing() {
        // The right edge of a shape: turning point [70; 100], through [76; 63].
        let text = mirrorText(vertexThrough(mirror(p(70, 100)), mirror(p(76, 63)), comma: false))!
        #expect(text.hasPrefix("x = "))
        let g = row(text).fnOfY!
        #expect(near(g(100), 70) && near(g(63), 76))
    }
}
