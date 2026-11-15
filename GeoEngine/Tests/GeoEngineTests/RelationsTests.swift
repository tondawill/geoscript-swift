import Foundation
import Testing
@testable import GeoEngine

private func deg(_ d: Double) -> Double { d * .pi / 180 }

/// p = AB along the x axis, q = CD, free points.
private func twoSegments(_ c0: (Double, Double), _ d0: (Double, Double)) -> (c: Construction, A: Id, B: Id, C: Id, D: Id, p: Id, q: Id) {
    var c = Construction()
    let A = c.addFreePoint(Vec(x: 0, y: 0))
    let B = c.addFreePoint(Vec(x: 6, y: 0))
    let C = c.addFreePoint(Vec(x: c0.0, y: c0.1))
    let D = c.addFreePoint(Vec(x: d0.0, y: d0.1))
    let p = c.addSegment(A, B)
    let q = c.addSegment(C, D)
    return (c, A, B, C, D, p, q)
}

private func angleBetween(_ c: Construction, _ p: Id, _ q: Id) -> Double {
    let r = c.resolve()
    func dir(_ id: Id) -> Double {
        let ends = parentsOf(c.object(id)!)
        return atan2(r[ends[1]]!.y - r[ends[0]]!.y, r[ends[1]]!.x - r[ends[0]]!.x)
    }
    return abs(dir(q) - dir(p)).truncatingRemainder(dividingBy: .pi)
}

private func value(_ r: RelationResult) throws -> Construction { try r.get() }

@Suite struct LinesAndRays {
    @Test func lineExtendsBeyondItsPoints() throws {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 1, y: 0))
        let C = c.addFreePoint(Vec(x: 5, y: -1))
        let D = c.addFreePoint(Vec(x: 5, y: 1))
        let l = c.addLine(A, B)
        let s = c.addSegment(C, D)
        let r = c.resolve()
        let hit = intersect(curveGeom(c.object(l)!, r)!, curveGeom(c.object(s)!, r)!)
        #expect(close(try #require(hit[0]).x, 5))
    }

    @Test func rayStopsAtOrigin() {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 1, y: 0))
        let C = c.addFreePoint(Vec(x: -5, y: -1))
        let D = c.addFreePoint(Vec(x: -5, y: 1))
        let ray = c.addRay(A, B)
        let s = c.addSegment(C, D)
        let r = c.resolve()
        #expect(intersect(curveGeom(c.object(ray)!, r)!, curveGeom(c.object(s)!, r)!)[0] == nil)
    }
}

@Suite struct RelationsBehaviour {
    @Test func perpTurnsAroundNearestEnd() throws {
        let t = twoSegments((2, 0), (3, 3))
        let next = try value(t.c.finishRelation(.perpendicular, t.p, target: t.q, t.c.resolve()))
        let r = next.resolve()
        #expect(close(angleBetween(next, t.p, t.q), .pi / 2))
        #expect(close(dist(r[t.D]!, r[t.C]!), hypot(1, 3)))
        #expect(next.relationOf(next.object(t.q)!)?.kind == .perpendicular)
    }

    @Test func relationSurvivesDragging() throws {
        let t = twoSegments((2, 0), (3, 3))
        var next = try value(t.c.finishRelation(.perpendicular, t.p, target: t.q, t.c.resolve()))
        next.movePoint(t.B, to: Vec(x: 4, y: 4))
        #expect(close(angleBetween(next, t.p, t.q), .pi / 2))
    }

    @Test func parallel() throws {
        let t = twoSegments((1, 2), (4, 3))
        let next = try value(t.c.finishRelation(.parallel, t.p, target: t.q, t.c.resolve()))
        #expect(close(angleBetween(next, t.p, t.q), 0))
        #expect(next.allRelations()[0].kind == .parallel)
    }

    @Test func clickingPointMakesLine() throws {
        let t = twoSegments((2, 2), (3, 5))
        let next = try value(t.c.finishRelation(.perpendicular, t.p, target: t.C, t.c.resolve()))
        let line = try #require(next.objects.first { if case .line = $0 { true } else { false } })
        #expect(close(angleBetween(next, t.p, line.id), .pi / 2))
    }

    @Test func angleToolEditAndRemove() throws {
        let t = twoSegments((3, -2), (3, 2))
        let next = try value(t.c.finishAngle(t.p, t.q, angle: deg(60), t.c.resolve()))
        #expect(close(angleBetween(next, t.p, t.q), deg(60)))
        #expect(next.relationOf(next.object(t.q)!)?.kind == .angle)

        let edited = try #require(next.settingRelationAngle(t.q, deg(30)))
        #expect(close(angleBetween(edited, t.p, t.q), deg(30)))

        var removed = edited.removingRelation(t.q, edited.resolve())
        #expect(removed.allRelations().isEmpty)
        removed.movePoint(t.B, to: Vec(x: 6, y: 3))
        #expect(!close(angleBetween(removed, t.p, t.q), deg(30)))
    }

    @Test func turnsLineThatMovesLess() throws {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 1, y: 0.2))
        let C = c.addFreePoint(Vec(x: 3, y: -10))
        let D = c.addFreePoint(Vec(x: 4, y: 10))
        let p = c.addSegment(A, B)
        let q = c.addSegment(C, D)
        let r = c.resolve()
        let less = try value(c.finishRelation(.perpendicular, p, target: q, r))
        #expect(less.relationOf(less.object(p)!)?.kind == .perpendicular)
        #expect(less.resolve()[D] == r[D])
        let second = try value(c.finishRelation(.perpendicular, p, target: q, turn: .second, r))
        #expect(second.relationOf(second.object(q)!)?.kind == .perpendicular)
        #expect(second.resolve()[B] == r[B])
    }

    @Test func turnsOtherLineWhenLocked() throws {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        c.addFreePoint(Vec(x: 6, y: 1))
        let C = c.addFreePoint(Vec(x: 3, y: 4))
        let D = c.addFreePoint(Vec(x: 3.5, y: -2))
        let q = c.addSegment(C, D)
        let k = c.addCircle(center: C, radius: 2, locked: true)
        let X = c.addIntersectionPoint(q, k, index: 1)
        let p = c.addSegment(X, A)
        let next = try value(c.finishRelation(.perpendicular, p, target: q, turn: .second, c.resolve()))
        #expect(close(angleBetween(next, p, q), .pi / 2))
        #expect(next.relationOf(next.object(p)!) != nil)
    }

    @Test func angleNeedsIntersection() {
        let t = twoSegments((10, 1), (10, 3))
        if case .success = t.c.finishAngle(t.p, t.q, angle: deg(60), t.c.resolve()) { Issue.record("expected failure") }
    }

    @Test func turnsAroundSharedEndpoint() throws {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 3, y: 0))
        let C = c.addFreePoint(Vec(x: 1, y: 4))
        let p = c.addSegment(A, B)
        let q = c.addSegment(A, C)
        let next = try value(c.finishAngle(p, q, angle: deg(30), c.resolve()))
        let pos = try #require(next.resolve()[C])
        #expect(close(atan2(pos.y, pos.x), deg(30)))
    }
}

@Suite struct DirectionSnapping {
    @Test func perpWithinTwoDegrees() {
        let t = twoSegments((3, 5), (3, 6))
        let r = t.c.resolve()
        let start = Vec(x: 3, y: 0)
        #expect(t.c.findDirectionSnap(r, start: start, mouse: Vec(x: 3 + tan(deg(1)) * 4, y: 4))?.kind == .perpendicular)
        #expect(t.c.findDirectionSnap(r, start: start, mouse: Vec(x: 3 + tan(deg(5)) * 4, y: 4)) == nil)
    }

    @Test func parallelOffTheLine() {
        let t = twoSegments((0, 2), (1, 2))
        let snap = t.c.findDirectionSnap(t.c.resolve(), start: Vec(x: 0, y: 3), mouse: Vec(x: 5, y: 3 + tan(deg(1.5)) * 5), excluding: [t.q])
        #expect(snap?.kind == .parallel)
        #expect(snap?.ref == t.p)
    }

    @Test func snappedSegmentStaysPerpendicular() throws {
        var t = twoSegments((3, 5), (3, 6))
        let ok = t.c.finishSegment(start: .free(pos: Vec(x: 3, y: 0)), end: .direction(ref: t.p, offset: .pi / 2, distance: 2, locked: false))
        #expect(ok)
        let seg = try #require(t.c.objects.last).id
        t.c.movePoint(t.B, to: Vec(x: 5, y: 2))
        #expect(close(angleBetween(t.c, t.p, seg), .pi / 2))
    }

    @Test func perpEndsOnCircle() throws {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 8, y: 0))
        let p = c.addSegment(A, B)
        let S = c.addFreePoint(Vec(x: 3, y: 4))
        c.addCircle(center: S, radius: 2)
        let start = Vec(x: 3, y: 0)
        let hit = try #require(c.findDirectionHit(c.resolve(), start: start, dir: .pi / 2, mouse: Vec(x: 3.1, y: 2.1), tolerance: 0.5))
        #expect(close(hit.pos.y, 2))
        let ok = c.finishSegment(start: .free(pos: start), end: .direction(ref: p, offset: .pi / 2, distance: 2, locked: false,
                                                                           onCurve: OnCurve(id: hit.curve, index: hit.index)))
        #expect(ok)
        let end = parentsOf(try #require(c.objects.last))[1]
        c.movePoint(S, to: Vec(x: 3, y: 6))
        #expect(close(try #require(c.resolve()[end]).y, 4))
        #expect(close(try #require(c.resolve()[end]).x, 3))
    }

    @Test func perpWithoutTouching() {
        let t = twoSegments((3, 5), (3, 6))
        let snap = t.c.findDirectionSnap(t.c.resolve(), start: Vec(x: 2, y: 3), mouse: Vec(x: 2.05, y: 6))
        #expect(snap?.kind == .perpendicular)
        #expect(snap?.touching == false)
    }

    @Test func lineAtAngleHidesItsPoints() throws {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 6, y: 0))
        let p = c.addSegment(A, B)
        let ok = c.finishSegment(start: .free(pos: Vec(x: 3, y: -2)), end: .direction(ref: p, offset: deg(60), distance: 3, locked: false), shape: .line)
        #expect(ok)
        let line = try #require(c.objects.first { if case .line = $0 { true } else { false } })
        let directionPoints = c.objects.filter { if case .directionPoint = $0 { true } else { false } }
        let allHidden = directionPoints.allSatisfy(\.isHidden)
        #expect(allHidden)
        #expect(close(try #require(c.relationOf(line)).angle, deg(60)))
    }
}

@Suite struct DraggingSegments {
    private func typed() -> (c: Construction, A: Id, B: Id, s: Id) {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addDistancePoint(parent: A, distance: 6, angle: 0)
        let s = c.addSegment(A, B)
        return (c, A, B, s)
    }

    @Test func eitherEndRotatesAroundTheOther() throws {
        var (c, A, B, _) = typed()
        let before = try #require(c.resolve()[B])
        c.dragPoint(A, to: Vec(x: 6, y: 9))
        let r = c.resolve()
        #expect(close(try #require(r[B]).x, before.x))
        #expect(close(try #require(r[B]).y, before.y))
        #expect(close(dist(try #require(r[A]), before), 6))
        #expect(close(try #require(r[A]).x, 6))

        let pivot = try #require(c.resolve()[A])
        c.dragPoint(B, to: Vec(x: 20, y: 6))
        let after = c.resolve()
        #expect(close(try #require(after[A]).x, pivot.x))
        #expect(close(try #require(after[A]).y, pivot.y))
        #expect(close(dist(try #require(after[A]), try #require(after[B])), 6))
    }

    @Test func sharedAnchorJustMoves() throws {
        var (c, A, B, _) = typed()
        let C = c.addDistancePoint(parent: A, distance: 3, angle: 1)
        c.addSegment(A, C)
        c.dragPoint(A, to: Vec(x: 1, y: 1))
        let r = c.resolve()
        #expect(r[A] == Vec(x: 1, y: 1))
        #expect(close(try #require(r[B]).x, 7))
    }

    @Test func translateMovesWholeSegment() throws {
        var (c, A, B, s) = typed()
        #expect(c.canTranslateSegment(s))
        c.translateSegment(s, dx: 2, dy: 3)
        let r = c.resolve()
        #expect(r[A] == Vec(x: 2, y: 3))
        #expect(close(try #require(r[B]).x, 8))
        #expect(close(try #require(r[B]).y, 3))
    }

    @Test func tiedEndsCannotTranslate() {
        var c = Construction()
        let P = c.addFreePoint(Vec(x: 0, y: 0))
        let Q = c.addFreePoint(Vec(x: 6, y: 0))
        let k1 = c.addCircle(center: P, radius: 4)
        let k2 = c.addCircle(center: Q, radius: 5)
        let X = c.addIntersectionPoint(k1, k2, index: 0)
        let Y = c.addFreePoint(Vec(x: 20, y: 0))
        let s = c.addSegment(X, Y)
        #expect(!c.canTranslateSegment(s))
    }
}
