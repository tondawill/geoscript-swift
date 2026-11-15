import Foundation
import Testing
@testable import GeoEngine

/// Clicking functions into the grid, as the sidebar's cards do.
@Suite struct GraphPlacingTests {
    private func p(_ x: Double, _ y: Double) -> Vec { Vec(x: x, y: y) }

    /// Clicks the points in turn (each pulled where the kind wants it); the row made, or the refusal.
    private func place(_ kind: FunctionKind, sideways: Bool = false, _ clicks: [Vec]) -> (text: String?, refused: String?, placed: [Vec]) {
        let k = placingKind(kind, sideways: sideways)
        var placed: [Vec] = []
        for (i, click) in clicks.enumerated() {
            let q = k.constrain(placed, click)
            if let reason = k.reject(placed, q) { return (nil, reason, placed) }
            if i == k.hints.count - 1 { return (k.through(placed, q, false), nil, placed + [q]) }
            placed.append(q)
        }
        return (nil, nil, placed)
    }

    private func value(_ text: String, _ x: Double) -> Double { compileRows([GraphRow(id: "g", text: text, color: "red")])[0].fn!(x) }

    @Test func everyKindWritesItsRow() {
        #expect(place(.linear, [p(1, 3), p(2, 5)]).text == "y = 2x + 1")
        #expect(place(.linear, [p(1, 3), p(1, 5)]).text == "x = 1")
        #expect(place(.parabolaVertex, [p(1, 3), p(2, 5)]).text == "y = 2(x - 1)^2 + 3")
        // Roots are pulled onto the x-axis.
        #expect(place(.parabolaIntercept, [p(-3, 0.4), p(1, -0.2), p(0, -3)]).text == "y = (x + 3)(x - 1)")
        #expect(place(.parabolaGeneral, [p(-2, 0), p(0, -4), p(2, 0)]).text == "y = x^2 - 4")
        #expect(place(.cubicInflection, [p(0, 0), p(1, -1)]).text == "y = -x^3")
        #expect(place(.cubicIntercept, [p(-2, 1), p(0, 1), p(3, 1), p(1, -3)]).text == "y = 0.5(x + 2)x(x - 3)")
        #expect(place(.sin, [p(0, 0), p(.pi / 2, 1)]).text == "y = sin(x)")
        // The tangent's asymptote is level with its centre.
        #expect(place(.tan, [p(0, 1), p(.pi / 2, 7), p(.pi / 4, 3)]).text == "y = 2tan(x) + 1")
        // The hyperbola: the vertical asymptote on the x-axis, the centre on it.
        #expect(place(.hyperbola, [p(1, 4), p(9, 3), p(2, 5)]).text == "y = 2/(x - 1) + 3")
        #expect(place(.circle, [p(0, 0), p(3, 0)]).text == "x^2 + y^2 = 3^2")
        #expect(place(.ellipse, [p(0, 0), p(3, 5), p(7, 2)]).text == "x^2/3^2 + y^2/2^2 = 1")
    }

    @Test func refusesClicksThatFixNoGraph() {
        #expect(place(.linear, [p(1, 3), p(1, 3)]).refused == "graph.hint.samePoint")
        #expect(place(.parabolaVertex, [p(1, 3), p(1, 5)]).refused == "graph.hint.parabola.sameX")
        #expect(place(.parabolaVertex, [p(1, 3), p(4, 3)]).refused == "graph.hint.parabola.flat")
        #expect(place(.parabolaIntercept, [p(-1, 0), p(3, 0), p(5, 0)]).refused == "graph.hint.parabola.onAxis")
        #expect(place(.parabolaGeneral, [p(0, 1), p(1, 3), p(2, 5)]).refused == "graph.hint.parabola.line")
        #expect(place(.tan, [p(0, 0), p(0, 3)]).refused == "graph.hint.tan.onCentre")
        #expect(place(.circle, [p(1, 1), p(1, 1)]).refused == "graph.hint.circle.onCentre")
        #expect(place(.ellipse, [p(0, 0), p(0, 4)]).refused == "graph.hint.ellipse.onCentre")
    }

    @Test func placesSideways() {
        let r = place(.parabolaVertex, sideways: true, [p(3, 1), p(5, 2)])
        #expect(r.text == "x = 2(y - 1)^2 + 3")
        // Roots on the y-axis, and the hints talk about it.
        let k = placingKind(.parabolaIntercept, sideways: true)
        #expect(k.hints[0] == "graph.hint.parabola.root1.sideways")
        #expect(k.constrain([], p(0.4, -3)) == p(0, -3))
        #expect(placingKind(.parabolaVertex, sideways: true).reject([p(3, 1)], p(5, 1)) == "graph.hint.parabola.sameX.sideways")
        // A hyperbola's asymptotes trade places; a circle stays as it is.
        #expect(placingKind(.hyperbola, sideways: true).hints[0] == "graph.hint.hyperbola.horizontal")
        #expect(place(.circle, sideways: true, [p(1, 0), p(1, 2)]).text == "(x - 1)^2 + y^2 = 2^2")
        #expect(placingKind(.sin, sideways: true).guides([p(2, 5)], nil) == [.x(2)])
    }

    @Test func previewsFollowThePointer() {
        let k = placingKind(.parabolaIntercept, sideways: false)
        // One root down: a = 1 through it and the pointer's x.
        #expect(k.preview([p(-1, 0)], p(3, 2), false) == PlacingPreview(text: "y = (x + 1)(x - 3)", ghost: true))
        #expect(k.preview([], p(3, 2), false) == nil)
        // Three points on a line give no parabola: the line through the first two, as a helper.
        let g = placingKind(.parabolaGeneral, sideways: false).preview([p(0, 1), p(1, 3)], p(2, 5), false)
        #expect(g == PlacingPreview(text: "y = 2x + 1", ghost: false))
        #expect(placingKind(.ellipse, sideways: false).preview([p(0, 0)], p(2, 1), false)?.text == "x^2/2^2 + y^2/2^2 = 1")
        #expect(placingKind(.tan, sideways: false).guides([p(0, 0)], p(.pi / 2, 0)).contains(.x(.pi / 2)))
        #expect(functionTemplate(.parabolaVertex, sideways: true, czech: true) == "x = a(y − m)² + n")
    }

    @Test func placedRowsGoThroughTheClicks() {
        for sideways in [false, true] {
            let r = place(.cubicGeneral, sideways: sideways, [p(-2, 1), p(0.5, -1), p(1, 2), p(3, 0)])
            let row = compileRows([GraphRow(id: "g", text: r.text!, color: "red")])[0]
            for q in r.placed {
                if sideways { #expect(abs(row.fnOfY!(q.y) - q.x) < 1e-6) } else { #expect(abs(row.fn!(q.x) - q.y) < 1e-6) }
            }
        }
        #expect(abs(value(place(.cos, [p(1, 4), p(3, 1)]).text!, 3) - 1) < 1e-9)
    }
}
