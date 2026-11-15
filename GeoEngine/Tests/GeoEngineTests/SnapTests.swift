import Testing
@testable import GeoEngine

private func exampleA() -> (c: Construction, A: Id, s: Id, k: Id) {
    var c = Construction()
    let A = c.addFreePoint(Vec(x: 0, y: 0))
    let B = c.addFreePoint(Vec(x: 6, y: 0))
    let s = c.addSegment(A, B)
    let k = c.addCircle(center: A, radius: 4)
    c.addCircle(center: B, radius: 5)
    return (c, A, s, k)
}

@Suite struct Snapping {
    @Test func priorities() throws {
        let (c, A, s, k) = exampleA()
        let r = c.resolve()
        #expect(c.findSnap(r, at: Vec(x: 0.1, y: 0.1), tolerance: 0.3).targets == [A])

        // AB ∩ k is at (4, 0); (3.9, 0.1) is also near the segment and the circle.
        let inter = c.findSnap(r, at: Vec(x: 3.9, y: 0.1), tolerance: 0.3)
        guard case .intersection = inter else { Issue.record("expected an intersection, got \(inter)"); return }
        #expect(close(inter.pos.x, 4))

        let on = c.findSnap(r, at: Vec(x: 2, y: 0.2), tolerance: 0.3)
        guard case .on = on else { Issue.record("expected on-curve, got \(on)"); return }
        #expect(on.targets == [s])
        #expect(on.pos == Vec(x: 2, y: 0))

        #expect(c.findSnap(r, at: Vec(x: 0, y: 4.2), tolerance: 0.3).targets == [k])
        #expect(c.findSnap(r, at: Vec(x: 20, y: 20), tolerance: 0.3) == .free(pos: Vec(x: 20, y: 20)))
    }

    @Test func materializesIntersection() throws {
        var (c, _, s, k) = exampleA()
        let snap = c.findSnap(c.resolve(), at: Vec(x: 3.9, y: 0.1), tolerance: 0.3)
        let id = c.materializeSnap(snap)
        guard case .intersectionPoint(let p)? = c.object(id) else { Issue.record("not an intersection point"); return }
        #expect([s, k].contains(p.a))
        #expect(close(try #require(c.resolve()[id]).x, 4))
    }

    @Test func placePointSkipsExistingAndMarksFree() throws {
        var c = Construction()
        let placed = c.placePoint(.free(pos: Vec(x: 1, y: 2)))
        let id = try #require(placed)
        guard case .freePoint(let p)? = c.object(id) else { Issue.record("not a free point"); return }
        #expect(p.ownStep)
        #expect(p.name == "A")
        let again = c.placePoint(.point(id: id, pos: Vec(x: 1, y: 2)))
        #expect(again == nil)
        #expect(c.objects.count == 1)
    }
}

@Suite struct ViewportMath {
    @Test func roundTrip() {
        let v = Viewport(width: 800, height: 600)
        #expect(v.toScreen(Vec(x: 0, y: 0)) == Vec(x: 400, y: 300))
        let p = v.toWorld(v.toScreen(Vec(x: 3, y: -2)))
        #expect(close(p.x, 3, 1e-9) && close(p.y, -2, 1e-9))
        #expect(v.toScreen(Vec(x: 0, y: 1)).y < 300) // world y points up
    }

    @Test func zoomKeepsPointFixedAndClamps() {
        var v = Viewport(width: 800, height: 600)
        let at = Vec(x: 123, y: 45)
        let before = v.toWorld(at)
        v.zoom(at: at, factor: 2.5)
        let after = v.toWorld(at)
        #expect(close(before.x, after.x, 1e-9) && close(before.y, after.y, 1e-9))
        v.zoom(at: at, factor: 1e6)
        #expect(v.scale == Viewport.maxScale)
    }
}
