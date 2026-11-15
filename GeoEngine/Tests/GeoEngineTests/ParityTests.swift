import Foundation
import Testing
@testable import GeoEngine

/// Runs the same scenario as `parity/generate.ts` and compares it with the TypeScript engine's output.
@Suite struct Parity {
    struct Snapshot: Decodable {
        let positions: [String: [Double]]
        let objects: [[String]]
    }

    private func kind(_ o: GeoObject) -> String {
        switch o {
        case .freePoint: "freePoint"
        case .distancePoint: "distancePoint"
        case .intersectionPoint: "intersectionPoint"
        case .pointOn: "pointOn"
        case .directionPoint: "directionPoint"
        case .segment: "segment"
        case .line: "line"
        case .ray: "ray"
        case .circle: "circle"
        }
    }

    @Test func matchesTypeScriptEngine() throws {
        let url = try #require(Bundle.module.url(forResource: "parity", withExtension: "json"))
        let expected = try JSONDecoder().decode([Snapshot].self, from: Data(contentsOf: url))

        var c = Construction()
        var actual: [Construction] = []
        func snap() { actual.append(c) }

        let A = c.addFreePoint(Vec(x: 0, y: 0))
        let B = c.addFreePoint(Vec(x: 6, y: 0))
        let s = c.addSegment(A, B)
        let k = c.addCircle(center: A, radius: 4)
        let k1 = c.addCircle(center: B, radius: 5)
        let C = c.addIntersectionPoint(k, k1, index: 0)
        let D = c.addPointOn(s, t: 0.5)
        let E = c.addPointOn(k, t: 1)
        let F = c.addDirectionPoint(parent: D, ref: s, offset: .pi / 2, distance: 3, lengthLocked: false)
        c.addDirectionPoint(parent: D, ref: s, offset: 0.3, distance: 1, lengthLocked: false, onCurve: OnCurve(id: k, index: 1))
        let p = c.addLine(A, C)
        c.addRay(B, C)
        let H = c.addDistancePoint(parent: C, distance: 2.5, angle: 1.2)
        c.addCircle(center: H, through: A)
        let k3 = c.addCircle(center: F, span: (A, B))
        c.addIntersectionPoint(p, k3, index: 0)
        c.addSegment(E, F)
        snap()
        c.movePoint(A, to: Vec(x: 1, y: -0.5)); snap()
        c.movePoint(F, to: Vec(x: 3, y: 5)); snap()
        c.movePoint(D, to: Vec(x: 2, y: 1)); snap()
        c.movePoint(H, to: Vec(x: 9, y: 9)); snap()
        c.movePoint(E, to: Vec(x: -3, y: 2)); snap()
        c.movePoint(A, to: Vec(x: -20, y: 0)); snap()
        c.movePoint(A, to: Vec(x: 0.5, y: 0.25)); snap()
        c.removeKeepingPoints([C]); snap()
        c.removeObject(D); snap()

        try #require(actual.count == expected.count)
        for (step, (got, want)) in zip(actual, expected).enumerated() {
            let positions = got.resolve()
            #expect(Set(positions.keys) == Set(want.positions.keys), "step \(step)")
            for (id, xy) in want.positions {
                let pos = try #require(positions[id], "step \(step) \(id)")
                #expect(close(pos.x, xy[0], 1e-9) && close(pos.y, xy[1], 1e-9), "step \(step) \(id)")
            }
            #expect(got.objects.map { [$0.id, kind($0), $0.name ?? ""] } == want.objects, "step \(step)")
        }
    }
}
