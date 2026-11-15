import Testing
@testable import GeoEngine

private func freeSegment() -> (c: Construction, A: Id, B: Id, s: Id) {
    var c = Construction()
    let A = c.addFreePoint(Vec(x: 0, y: 0))
    let B = c.addFreePoint(Vec(x: 4, y: 0))
    let s = c.addSegment(A, B)
    return (c, A, B, s)
}

private func length(_ c: Construction, _ s: Id) -> Double {
    c.segmentLength(c.object(s)!, c.resolve()) ?? -1
}

private func radius(_ c: Construction, _ k: Id) -> Double {
    c.circleRadius(c.object(k)!, c.resolve()) ?? -1
}

private func locked(_ c: Construction, _ id: Id) -> Bool {
    c.isLocked(c.object(id)!)
}

@Suite struct SegmentDimensions {
    @Test func eyeballedChangesWhenDragged() {
        var (c, A, _, s) = freeSegment()
        #expect(!locked(c, s))
        c.movePoint(A, to: Vec(x: 1, y: 0))
        #expect(close(length(c, s), 3))
    }

    @Test func settingMovesBothEndsAndLocks() throws {
        var (c, A, B, s) = freeSegment()
        let error = c.setSegmentLength(s, 6)
        #expect(error == nil)
        let r = c.resolve()
        #expect(close(try #require(r[A]).x, -1))
        #expect(close(try #require(r[B]).x, 5))
        #expect(locked(c, s))
        c.movePoint(B, to: Vec(x: 2, y: 9))
        #expect(close(length(c, s), 6))
        c.movePoint(A, to: Vec(x: 10, y: 10))
        #expect(close(length(c, s), 6))
    }

    @Test func changingLockedIsSymmetric() throws {
        var (c, A, B, s) = freeSegment()
        c.setSegmentLength(s, 4)
        c.setSegmentLength(s, 8)
        let r = c.resolve()
        #expect(close(try #require(r[A]).x, -2))
        #expect(close(try #require(r[B]).x, 6))
    }

    @Test func onlyFreeEndMoves() throws {
        var c = Construction()
        let P = c.addFreePoint(Vec(x: 0, y: 0))
        let Q = c.addFreePoint(Vec(x: 6, y: 0))
        let k1 = c.addCircle(center: P, radius: 4)
        let k2 = c.addCircle(center: Q, radius: 5)
        let X = c.addIntersectionPoint(k1, k2, index: 0)
        let Y = c.addFreePoint(Vec(x: 20, y: 0))
        let s = c.addSegment(X, Y)
        let before = c.resolve()[X]
        c.setSegmentLength(s, 3)
        #expect(c.resolve()[X] == before)
        #expect(close(length(c, s), 3))

        let R = c.addIntersectionPoint(k1, k2, index: 1)
        let fixed = c.addSegment(X, R)
        #expect(!c.canEditDimension(c.object(fixed)!))
        let unchanged = c
        let error = c.setSegmentLength(fixed, 2)
        #expect(error == .cannotEditSegment)
        #expect(c == unchanged)
    }

    @Test func locksWhenSecondPointCameFirst() throws {
        var c = Construction()
        let B = c.addFreePoint(Vec(x: 4, y: 0), name: "B")
        let A = c.addFreePoint(Vec(x: 0, y: 0), name: "A")
        let s = c.addSegment(A, B)
        c.setSegmentLength(s, 2)
        #expect(close(length(c, s), 2))
        // Every object still comes after its parents.
        let index = Dictionary(uniqueKeysWithValues: c.objects.enumerated().map { ($1.id, $0) })
        for o in c.objects {
            for p in parentsOf(o) { #expect(try #require(index[p]) < (try #require(index[o.id]))) }
        }
    }

    @Test func unlockKeepsPositionFreesLength() {
        var (c, A, _, s) = freeSegment()
        c.setSegmentLength(s, 6)
        c.unlockSegment(s)
        #expect(!locked(c, s))
        #expect(close(length(c, s), 6))
        c.movePoint(A, to: Vec(x: 0, y: 0))
        #expect(close(length(c, s), 5))
    }

    @Test func typedDuringConstructionIsLocked() {
        var c = Construction()
        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addDistancePoint(parent: A, distance: 6, angle: 0)
        let s = c.addSegment(A, B)
        #expect(locked(c, s))
    }
}

@Suite struct CircleDimensions {
    @Test func eyeballedResizesTypedLocks() throws {
        var c = Construction()
        let S = c.addFreePoint(Vec(x: 0, y: 0))
        let k = c.addCircle(center: S, radius: 2)
        #expect(!locked(c, k))
        c.resizeCircle(k, radius: 3)
        #expect(radius(c, k) == 3)
        c.setCircleRadius(k, 4)
        #expect(locked(c, k))
        c.resizeCircle(k, radius: 9)
        #expect(radius(c, k) == 4)
        c.unlockCircle(k)
        #expect(!locked(c, k))
    }

    @Test func throughCircleFollowsAndLocks() throws {
        var c = Construction()
        let S = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 3, y: 4))
        let k = c.addCircle(center: S, through: B)
        #expect(close(radius(c, k), 5))
        c.movePoint(B, to: Vec(x: 0, y: 2))
        #expect(close(radius(c, k), 2))
        #expect(!locked(c, k))

        c.setCircleRadius(k, 7)
        let r = c.resolve()
        #expect(close(try #require(r[B]).x, 0))
        #expect(close(try #require(r[B]).y, 7))
        #expect(locked(c, k))
        c.movePoint(B, to: Vec(x: 100, y: 0))
        #expect(close(radius(c, k), 7))

        c.unlockCircle(k)
        #expect(!locked(c, k))
        #expect(close(radius(c, k), 7))
    }
}

@Suite struct NumberFormat {
    @Test func parses() {
        #expect(parseNumber("6") == 6)
        #expect(parseNumber("6,5") == 6.5)
        #expect(parseNumber(" 2.25 cm ") == 2.25)
        #expect(parseNumber(".5") == 0.5)
        #expect(parseNumber("5.") == 5)
        #expect(parseNumber("0") == nil)
        #expect(parseNumber("abc") == nil)
        #expect(parseNumber("1.2.3") == nil)
    }

    @Test func formats() {
        #expect(formatDimension(6) == "6")
        #expect(formatDimension(6.5) == "6.5")
        #expect(formatDimension(6.256) == "6.26")
        #expect(formatNumber(6) == "6.00")
    }
}
