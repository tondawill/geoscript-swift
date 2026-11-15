import Foundation
import Testing
@testable import GeoEngine

func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.005) -> Bool { abs(a - b) < tolerance }

private func seg(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> CurveGeom {
    .straight(a: Vec(x: ax, y: ay), b: Vec(x: bx, y: by), ext: .segment)
}

private func circ(_ x: Double, _ y: Double, _ radius: Double) -> CurveGeom {
    .circle(center: Vec(x: x, y: y), radius: radius)
}

private func exampleA() -> (c: Construction, A: Id, B: Id, s: Id, k: Id, k1: Id) {
    var c = Construction()
    let A = c.addFreePoint(Vec(x: 0, y: 0))
    let B = c.addFreePoint(Vec(x: 6, y: 0))
    let s = c.addSegment(A, B)
    let k = c.addCircle(center: A, radius: 4)
    let k1 = c.addCircle(center: B, radius: 5)
    return (c, A, B, s, k, k1)
}

@Suite struct Naming {
    @Test func pointNames() {
        #expect(nextPointName([]) == "A")
        #expect(nextPointName(["A", "B"]) == "C")
        #expect(nextPointName(["A", "C"]) == "B")
        #expect(nextPointName(Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))) == "A₁")
    }

    @Test func circleNames() {
        #expect(nextCircleName([]) == "k")
        #expect(nextCircleName(["k"]) == "k₁")
        #expect(nextCircleName(["k", "k₁"]) == "k₂")
    }

    @Test func validation() {
        #expect(normalizeName(" B1 ") == "B₁")
        #expect(isValidPointName("A"))
        #expect(isValidPointName("A'"))
        #expect(!isValidPointName("a"))
        #expect(!isValidPointName("AB"))
        #expect(isValidLowerName("k₂"))
        #expect(!isValidLowerName("K"))
    }
}

@Suite struct ConstructionDAG {
    @Test func namesAndDisplay() throws {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let b = c.addFreePoint(Vec(x: 3, y: 4))
        let s = c.addSegment(a, b)
        #expect(c.object(a)?.name == "A")
        #expect(c.object(b)?.name == "B")
        #expect(c.displayName(try #require(c.object(s))) == "AB")
        c.renameObject(s, "c")
        #expect(c.displayName(try #require(c.object(s))) == "c")
        #expect(c.isNameTaken("A"))
        #expect(!c.isNameTaken("A", except: a))
    }

    @Test func removesTransitiveDependents() {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let b = c.addDistancePoint(parent: a, distance: 6, angle: 0)
        c.addSegment(a, b)
        c.addCircle(center: b, radius: 2)
        let other = c.addFreePoint(Vec(x: 10, y: 10))
        c.removeObject(a)
        #expect(c.objects.map(\.id) == [other])
    }

    @Test func distancePointKeepsDistance() throws {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let b = c.addDistancePoint(parent: a, distance: 6, angle: 0)
        #expect(c.resolve()[b] == Vec(x: 6, y: 0))
        c.movePoint(a, to: Vec(x: 1, y: 1))
        #expect(c.resolve()[b] == Vec(x: 7, y: 1))
        c.movePoint(b, to: Vec(x: 1, y: 100))
        let r = c.resolve()
        #expect(close(dist(try #require(r[a]), try #require(r[b])), 6))
        #expect(close(try #require(r[b]).x, 1))
        #expect(close(try #require(r[b]).y, 7))
    }

    @Test func hitTestPriority() {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let b = c.addFreePoint(Vec(x: 4, y: 0))
        let s = c.addSegment(a, b)
        let k = c.addCircle(center: a, radius: 2)
        let r = c.resolve()
        #expect(c.hitTest(r, at: Vec(x: 0.1, y: 0), tolerance: 0.3)?.id == a)
        #expect(c.hitTest(r, at: Vec(x: 2, y: 0.1), tolerance: 0.3)?.id == s)
        #expect(c.hitTest(r, at: Vec(x: 0, y: 2.1), tolerance: 0.3)?.id == k)
        #expect(c.hitTest(r, at: Vec(x: 9, y: 9), tolerance: 0.3) == nil)
    }

    @Test func circleIncidence() {
        #expect(isOnCircle(Vec(x: 4.005, y: 0), Vec(x: 0, y: 0), 4))
        #expect(!isOnCircle(Vec(x: 4.02, y: 0), Vec(x: 0, y: 0), 4))
    }
}

@Suite struct Intersect {
    @Test func segmentSegment() {
        #expect(intersect(seg(-1, 0, 1, 0), seg(0, -1, 0, 1)) == [Vec(x: 0, y: 0)])
        #expect(intersect(seg(-1, 0, 1, 0), seg(2, -1, 2, 1)) == [nil])
        #expect(intersect(seg(0, 0, 1, 0), seg(0, 1, 1, 1)) == [nil])
    }

    @Test func segmentCircle() throws {
        let r = intersect(seg(-5, 0, 5, 0), circ(0, 0, 2))
        #expect(close(try #require(r[0]).x, -2))
        #expect(close(try #require(r[1]).x, 2))
        #expect(intersect(circ(0, 0, 2), seg(-5, 0, 5, 0)) == r)
        let half = intersect(seg(0, 0, 5, 0), circ(0, 0, 2))
        #expect(half[0] == nil)
        #expect(close(try #require(half[1]).x, 2))
        #expect(intersect(seg(-5, 3, 5, 3), circ(0, 0, 2)) == [nil, nil])
    }

    @Test func circleCircle() throws {
        let hits = intersect(circ(0, 0, 4), circ(6, 0, 5))
        let p = try #require(hits[0])
        let q = try #require(hits[1])
        #expect(close(dist(p, Vec(x: 0, y: 0)), 4))
        #expect(close(dist(p, Vec(x: 6, y: 0)), 5))
        #expect(p.y > 0)
        #expect(q.y < 0)
        #expect(intersect(circ(0, 0, 1), circ(5, 0, 1)) == [nil, nil])
        #expect(intersect(circ(0, 0, 1), circ(0, 0, 2)) == [nil, nil])
    }
}

@Suite struct DependentPoints {
    @Test func intersectionFollowsHidesAndReturns() throws {
        var (c, A, _, _, k, k1) = exampleA()
        let C = c.addIntersectionPoint(k, k1, index: 0)
        #expect(c.object(C)?.name == "C")
        #expect(close(dist(try #require(c.resolve()[C]), Vec(x: 0, y: 0)), 4))

        c.movePoint(A, to: Vec(x: 1, y: 0))
        let p = try #require(c.resolve()[C])
        #expect(close(dist(p, Vec(x: 1, y: 0)), 4))
        #expect(close(dist(p, Vec(x: 6, y: 0)), 5))

        c.movePoint(A, to: Vec(x: -20, y: 0))
        #expect(c.resolve()[C] == nil)
        c.movePoint(A, to: Vec(x: 0, y: 0))
        #expect(c.resolve()[C] != nil)
    }

    @Test func intersectionCannotBeDraggedAndDiesWithCurve() {
        var (c, _, _, _, k, k1) = exampleA()
        let C = c.addIntersectionPoint(k, k1, index: 0)
        let before = c.resolve()[C]
        var moved = c
        moved.movePoint(C, to: Vec(x: 50, y: 50))
        #expect(moved.resolve()[C] == before)
        c.removeObject(k1)
        #expect(c.object(C) == nil)
    }

    @Test func pointsSlideAlongCurves() throws {
        var (c, _, _, s, k, _) = exampleA()
        let X = c.addPointOn(s, t: 0.5)
        let Y = c.addPointOn(k, t: 0)
        #expect(c.resolve()[X] == Vec(x: 3, y: 0))

        c.movePoint(X, to: Vec(x: 4, y: 3))
        #expect(close(try #require(c.resolve()[X]).x, 4))
        #expect(close(try #require(c.resolve()[X]).y, 0))
        c.movePoint(X, to: Vec(x: 100, y: 0))
        #expect(close(try #require(c.resolve()[X]).x, 6))

        c.movePoint(Y, to: Vec(x: 0, y: 10))
        #expect(close(try #require(c.resolve()[Y]).x, 0))
        #expect(close(try #require(c.resolve()[Y]).y, 4))
    }
}
