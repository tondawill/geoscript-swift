import Testing
@testable import GeoEngine

/// A segment of a typed length that starts at A and goes through B: "AC; C ∈ ↦AB ∧ |AC| = 5 cm".
@Suite struct AimedSegment {
    private let format = ProtocolFormat(dim: { formatDimension($0) }, deg: { formatDimension($0) })
    private let ctx = TypingContext(center: Vec(x: 0, y: 0))

    private func drawn() -> (Construction, a: Id, b: Id) {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let b = c.addFreePoint(Vec(x: 3, y: 4))
        let ok = c.finishSegment(start: .point(id: a, pos: Vec(x: 0, y: 0)), end: .lengthThrough(10, point: b))
        #expect(ok)
        return (c, a, b)
    }

    @Test func endsOnTheRayAndFollowsB() throws {
        var (c, _, b) = drawn()
        let end = try #require(c.objects.filter(\.isPoint).last)
        #expect(end.name == "C")
        var r = c.resolve()
        let p = try #require(r[end.id])
        #expect(close(p.x, 6) && close(p.y, 8))
        #expect(!isDraggable(end))

        c.movePoint(b, to: Vec(x: 0, y: -2))
        r = c.resolve()
        let q = try #require(r[end.id])
        #expect(close(q.x, 0) && close(q.y, -10))
    }

    @Test func protocolTextAndTypingRoundTrip() throws {
        let (c, _, _) = drawn()
        let text = try #require(c.buildProtocol(format).last).text
        #expect(text == "AC; C ∈ ↦AB ∧ |AC| = 10 cm")

        var typed = Construction()
        typed.addFreePoint(Vec(x: 0, y: 0))
        typed.addFreePoint(Vec(x: 3, y: 4))
        let result = try typed.insertStep(text, ctx).get().construction
        let end = try #require(result.objects.filter(\.isPoint).last)
        guard case .distancePoint(let d) = end else { Issue.record("not a distance point"); return }
        #expect(d.toward == "o2" && d.distance == 10)
        #expect(result.buildProtocol(format).last?.text == text)
    }

    @Test func savesAndLoads() throws {
        let (c, _, _) = drawn()
        let file = exportFile(FileContents(construction: c), steps: c.buildProtocol(format), stepsTitle: "Steps", exerciseTitle: "Exercise")
        let loaded = try importFile(file, ctx).get().construction
        #expect(loaded.resolve() == c.resolve())
        #expect(loaded.objects.contains { if case .distancePoint(let d) = $0 { d.toward != nil } else { false } })
    }

    @Test func lengthEditKeepsTheStart() throws {
        var (c, a, _) = drawn()
        let seg = try #require(c.objects.last)
        #expect(c.setSegmentLength(seg.id, 5) == nil)
        let r = c.resolve()
        #expect(r[a] == Vec(x: 0, y: 0))
        let end = try #require(c.objects.filter(\.isPoint).last)
        #expect(close(r[end.id]!.x, 3) && close(r[end.id]!.y, 4))
    }

    @Test func rejectsAimingAtTheStart() {
        var c = Construction()
        let a = c.addFreePoint(Vec(x: 0, y: 0))
        let before = c
        let ok = c.finishSegment(start: .point(id: a, pos: Vec(x: 0, y: 0)), end: .lengthThrough(4, point: a))
        #expect(!ok)
        #expect(c == before)
    }
}
