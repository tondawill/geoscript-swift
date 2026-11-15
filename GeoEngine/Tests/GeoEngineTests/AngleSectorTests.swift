import Foundation
import Testing
@testable import GeoEngine

/// Angle tool: the angle between two lines that the mouse is in is the one that gets the typed value.
@Suite struct AngleSectors {
    /// p: (−5, 0)–(5, 0); q: (−3, −3)–(3, 3), at 45°.
    private func crossing() -> (Construction, p: Id, q: Id, qEnd: Id) {
        var c = Construction()
        func seg(_ a: Vec, _ b: Vec) -> Id {
            _ = c.finishSegment(start: .free(pos: a), end: .snap(.free(pos: b)))
            return c.objects.last!.id
        }
        let p = seg(Vec(x: -5, y: 0), Vec(x: 5, y: 0))
        let q = seg(Vec(x: -3, y: -3), Vec(x: 3, y: 3))
        return (c, p, q, parentsOf(c.object(q)!)[1])
    }

    private func degrees(_ a: Double) -> Double { a * 180 / .pi }

    @Test func picksTheSectorUnderTheMouse() throws {
        let (c, p, q, _) = crossing()
        let r = c.resolve()
        let acute = try #require(c.angleSector(p, q, mouse: Vec(x: 3, y: 1), r))
        #expect(acute.start == p && acute.end == q && close(degrees(acute.size), 45))
        let obtuse = try #require(c.angleSector(p, q, mouse: Vec(x: 1, y: 3), r))
        #expect(obtuse.start == q && obtuse.end == p && close(degrees(obtuse.size), 135))
        let below = try #require(c.angleSector(p, q, mouse: Vec(x: -3, y: -1), r))
        #expect(close(degrees(below.size), 45))
    }

    @Test func setsTheAngleOfThatSector() throws {
        for (mouse, value) in [(Vec(x: 3, y: 1), 60.0), (Vec(x: 1, y: 3), 120.0), (Vec(x: 1, y: 3), 150.0), (Vec(x: -3, y: -1), 30.0)] {
            let (c, p, q, _) = crossing()
            let r = c.resolve()
            let sector = try #require(c.angleSector(p, q, mouse: mouse, r))
            let next = try c.finishSectorAngle(sector, angle: value * .pi / 180, r).get()
            let after = try #require(next.angleSector(p, q, mouse: mouse, next.resolve()))
            #expect(close(degrees(after.size), value), "mouse \(mouse) → \(value)°")
        }
    }

    @Test func turnsBySmallestAmount() throws {
        // 45° → 60° in the acute sector: q turns by 15°, its end (3, 3) stays on the same side.
        let (c, p, q, qEnd) = crossing()
        let r = c.resolve()
        let sector = try #require(c.angleSector(p, q, mouse: Vec(x: 3, y: 1), r))
        let next = try c.finishSectorAngle(sector, angle: .pi / 3, r).get()
        let end = try #require(next.resolve()[qEnd])
        let d = 3 * 2.0.squareRoot()
        #expect(close(end.x, d * cos(.pi / 3)) && close(end.y, d * sin(.pi / 3)))
    }

    @Test func noSectorWithoutCrossing() {
        var c = Construction()
        _ = c.finishSegment(start: .free(pos: Vec(x: 0, y: 0)), end: .snap(.free(pos: Vec(x: 1, y: 0))))
        let p = c.objects.last!.id
        _ = c.finishSegment(start: .free(pos: Vec(x: 5, y: 1)), end: .snap(.free(pos: Vec(x: 6, y: 3))))
        let q = c.objects.last!.id
        #expect(c.angleSector(p, q, mouse: Vec(x: 3, y: 3), c.resolve()) == nil)
    }
}

/// Several angle constraints at one vertex: |∠ABC| = 50° and |∠ABX| = 70° (or |∠CBX| = 70°).
@Suite struct AnglesAtOneVertex {
    private let format = ProtocolFormat(dim: { formatDimension($0) }, deg: { formatDimension($0) })

    /// B at the origin with arms to A (5, 0), C (2, 4) and X.
    private func fan(x: Vec) -> (Construction, a: Id, ba: Id, bc: Id, bx: Id) {
        var c = Construction()
        let b = c.addFreePoint(Vec(x: 0, y: 0), name: "B")
        let a = c.addFreePoint(Vec(x: 5, y: 0), name: "A")
        let cc = c.addFreePoint(Vec(x: 2, y: 4), name: "C")
        let xx = c.addFreePoint(x, name: "X")
        func seg(_ p: Id, _ q: Id) -> Id { c.addSegment(p, q); return c.objects.last!.id }
        let ba = seg(b, a), bc = seg(b, cc), bx = seg(b, xx)
        return (c, a, ba, bc, bx)
    }

    private func setAngle(_ c: inout Construction, _ p: Id, _ q: Id, mouse: Vec, _ degrees: Double) throws {
        let r = c.resolve()
        let sector = try #require(c.angleSector(p, q, mouse: mouse, r))
        c = try c.finishSectorAngle(sector, angle: degrees * .pi / 180, r).get()
    }

    private func angle(_ c: Construction, _ p: Id, _ q: Id, mouse: Vec) -> Double? {
        c.angleSector(p, q, mouse: mouse, c.resolve()).map { $0.size * 180 / .pi }
    }

    @Test func bothFromTheSameLine() throws {
        var (c, a, ba, bc, bx) = fan(x: Vec(x: -3, y: 3))
        try setAngle(&c, ba, bc, mouse: Vec(x: 3, y: 1), 50)
        try setAngle(&c, ba, bx, mouse: Vec(x: 1, y: 3), 70)
        c.movePoint(a, to: Vec(x: 4, y: 3))
        #expect(close(try #require(angle(c, ba, bc, mouse: Vec(x: 1, y: 3))), 50))
        #expect(close(try #require(angle(c, ba, bx, mouse: Vec(x: -1, y: 4))), 70))
    }

    /// Angle in degrees between two segments from the same start point.
    private func armAngle(_ c: Construction, _ p: Id, _ q: Id) -> Double {
        let r = c.resolve()
        let pe = parentsOf(c.object(p)!), qe = parentsOf(c.object(q)!)
        let d = angleOf(r[pe[0]]!, r[pe[1]]!) - angleOf(r[qe[0]]!, r[qe[1]]!)
        return abs(atan2(sin(d), cos(d))) * 180 / .pi
    }

    @Test func secondAngleDoesNotDropTheFirst() throws {
        // X is far away, so turning BC moves less – but BC is held by |∠ABC| = 50°: BA and BC turn together.
        var (c, _, ba, bc, bx) = fan(x: Vec(x: -10, y: 10))
        try setAngle(&c, ba, bc, mouse: Vec(x: 3, y: 1), 50)
        try setAngle(&c, bc, bx, mouse: Vec(x: 0, y: 3), 70)
        #expect(close(armAngle(c, ba, bc), 50))
        #expect(close(armAngle(c, bc, bx), 70))
        let x = parentsOf(c.object(bx)!)[1]
        c.movePoint(x, to: Vec(x: 3, y: 8))
        #expect(close(armAngle(c, ba, bc), 50))
        #expect(close(armAngle(c, bc, bx), 70))
    }

    @Test func overConstrainedFails() throws {
        // Both BC and BX hang on BA, so ∠CBX is already fixed: neither can turn.
        var (c, _, ba, bc, bx) = fan(x: Vec(x: -3, y: 3))
        try setAngle(&c, ba, bc, mouse: Vec(x: 3, y: 1), 50)
        try setAngle(&c, ba, bx, mouse: Vec(x: 1, y: 3), 70)
        let r = c.resolve()
        let sector = try #require(c.angleSector(bc, bx, mouse: Vec(x: 0, y: 5), r))
        #expect(throws: RelationError.self) { try c.finishSectorAngle(sector, angle: 30 * .pi / 180, r).get() }
    }

    @Test func heldPairTurnsTogether() throws {
        // CO is given by the exercise; CX and CX₁ make 110°. Setting ∠XCO turns CX and CX₁ together.
        var c = Construction()
        _ = c.finishSegment(start: .free(pos: Vec(x: 0, y: 0)), end: .snap(.free(pos: Vec(x: 0.3, y: -5))), shape: .ray)
        let cx = c.objects.last!.id
        let vertex = Snap.point(id: c.objects[0].id, pos: Vec(x: 0, y: 0))
        _ = c.finishSegment(start: vertex, end: .snap(.free(pos: Vec(x: 7, y: -2.2))), shape: .ray)
        let cx1 = c.objects.last!.id
        _ = c.finishSegment(start: vertex, end: .snap(.free(pos: Vec(x: 2.5, y: -2.7))), shape: .ray)
        let co = c.objects.last!.id
        c.exercise = [c.objects[0].id, parentsOf(c.object(co)!)[1], co]
        let o = parentsOf(c.object(co)!)[1]
        let oBefore = c.resolve()[o]

        try setAngle(&c, cx, cx1, mouse: Vec(x: 3, y: -4), 110)
        try setAngle(&c, cx, co, mouse: Vec(x: 0.8, y: -3), 35)
        #expect(c.resolve()[o] == oBefore)
        #expect(close(try #require(angle(c, cx, co, mouse: Vec(x: 0.8, y: -3))), 35))
        let texts = c.buildProtocol(format).map(\.text).joined(separator: "\n")
        #expect(texts.contains("= 110°") && texts.contains("= 35°"))
    }

    @Test func typedSteps() throws {
        var c = Construction()
        c.addFreePoint(Vec(x: 0, y: 0), name: "B")
        c.addFreePoint(Vec(x: 5, y: 0), name: "A")
        c.addSegment("o1", "o2")
        let ctx = TypingContext(center: Vec(x: 0, y: 0))
        c = try c.insertStep("BC; |∠ABC| = 50°", ctx).get().construction
        c = try c.insertStep("BX; |∠ABX| = 70°", ctx).get().construction
        let texts = c.buildProtocol(format).map(\.text)
        #expect(texts.contains { $0.contains("|∠ABC| = 50°") })
        #expect(texts.contains { $0.contains("|∠ABX| = 70°") })
    }
}
