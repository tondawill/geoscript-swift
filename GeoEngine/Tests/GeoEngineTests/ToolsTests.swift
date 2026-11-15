import Testing
@testable import GeoEngine

@Suite struct DrawingTools {
    @Test func buildsExampleA() throws {
        var c = Construction()
        do { let ok = c.finishSegment(start: .free(pos: Vec(x: 0, y: 0)), end: .length(6, toward: Vec(x: 1, y: 0))); #expect(ok) }
        let points = c.objects.filter(\.isPoint)
        #expect(points.map(\.name) == ["A", "B"])
        let r = c.resolve()
        #expect(close(dist(try #require(r[points[0].id]), try #require(r[points[1].id])), 6))

        do { let ok = c.finishCircle(center: points[0].id, radius: 4, locked: true); #expect(ok) }
        do { let ok = c.finishCircle(center: points[1].id, radius: 5, locked: true); #expect(ok) }
        let circles = c.objects.filter { if case .circle = $0 { true } else { false } }
        #expect(circles.map(\.name) == ["k", "k₁"])
    }

    @Test func rejectsDegenerates() {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let atA = Snap.point(id: a, pos: Vec(x: 0, y: 0))
        let before = c
        do { let ok = c.finishSegment(start: atA, end: .snap(atA)); #expect(!ok) }
        do { let ok = c.finishSegment(start: atA, end: .length(0, toward: Vec(x: 1, y: 0))); #expect(!ok) }
        do { let ok = c.finishCircle(center: a, radius: 0, locked: true); #expect(!ok) }
        do { let ok = c.finishCircle(center: "missing", radius: 3, locked: true); #expect(!ok) }
        do { let ok = c.finishCircleThrough(center: a, through: a); #expect(!ok) }
        #expect(c == before)
    }

    @Test func lineHidesOnlyItsNewPoints() {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let start = Snap.point(id: a, pos: Vec(x: 0, y: 0))
        do { let ok = c.finishSegment(start: start, end: .snap(.free(pos: Vec(x: 3, y: 1))), shape: .line); #expect(ok) }
        let points = c.objects.filter(\.isPoint)
        #expect(points.map(\.isHidden) == [false, true])
        #expect(c.objects.last?.name == "p")
    }

    @Test func rayEndsAtX() {
        var c = Construction()
        do { let ok = c.finishSegment(start: .free(pos: Vec(x: 0, y: 0)), end: .snap(.free(pos: Vec(x: 3, y: 1))), shape: .ray); #expect(ok) }
        #expect(c.objects.filter(\.isPoint).map(\.name) == ["A", "X"])
        #expect(c.displayName(c.objects[2]) == "↦AX")
    }

    @Test func circleThroughFollowsItsPoint() throws {
        var c = Construction()
        let s = c.addFreePoint(Vec(x: 0, y: 0))
        let b = c.addFreePoint(Vec(x: 3, y: 0))
        do { let ok = c.finishCircleThrough(center: s, through: b); #expect(ok) }
        c.movePoint(b, to: Vec(x: 0, y: 5))
        guard case let .circle(_, radius)? = curveGeom(try #require(c.objects.last), c.resolve()) else {
            Issue.record("not a circle"); return
        }
        #expect(close(radius, 5))
    }

    @Test func resizeCircleIgnoresZero() {
        var c = Construction()
        let s = c.addFreePoint(Vec(x: 0, y: 0))
        let k = c.addCircle(center: s, radius: 2)
        c.resizeCircle(k, radius: 7)
        c.resizeCircle(k, radius: 0)
        guard case .circle(let circle)? = c.object(k) else { Issue.record("not a circle"); return }
        #expect(circle.radius == 7)
    }
}
