import CoreGraphics
import Foundation
import GeoEngine

/// The box that follows the pointer while something is in progress.
struct LiveDimension {
    let label: String
    let number: Double
    let value: String
    let unit: String
    let typing: Bool
    let invalid: Bool
}

/// A typed dimension or relation angle shown in the drawing.
struct DimensionLabel: Identifiable {
    let id: Id
    let position: CGPoint
    let text: String
    var radiusLine: (CGPoint, CGPoint)?
    var isAngle = false
}

/// ⊥, ∥ and angle marks, in screen coordinates.
enum RelationMark {
    case rightAngle(at: CGPoint, u: CGVector, v: CGVector, id: Id)
    case ticks(at: CGPoint, dir: CGVector, count: Int, id: Id)
    case arc(at: CGPoint, u: CGVector, v: CGVector, id: Id)
    case perpendicularSign(at: CGPoint, id: Id)
}

/// A snapped line being drawn: its ⊥ or ∥ mark.
struct DirectionMark {
    let kind: RelationTool
    let touching: Bool
    let at: Vec
    let refDir: Double
    let newDir: Double
    let refMid: Vec
}

/// What the action in progress looks like right now.
struct DrawProgress {
    var straight: (from: Vec, to: Vec, shape: LineShape)?
    var circle: (center: Vec, radius: Double)?
    var ghosts: [(pos: Vec, snapped: Bool)] = []
    var live: LiveDimension?
    var directionMark: DirectionMark?
    var highlighted: Set<Id> = []
    /// Faded result of a ⊥ / ∥ / angle action.
    var result: [CurveGeom] = []
    /// Angle tool: the arc of the angle being set, counter-clockwise from `from` by `size` radians.
    var angleArc: (at: Vec, from: Double, size: Double)?
}

func screenDirection(_ angle: Double) -> CGVector {
    CGVector(dx: cos(angle), dy: -sin(angle))
}

extension DrawingStore {
    private func live(_ label: String, _ number: Double, unit: String = "cm") -> LiveDimension {
        LiveDimension(label: label, number: number, value: typed ?? formatNumber(typedValue ?? number, comma: usesComma), unit: unit,
                      typing: typed != nil, invalid: typed != nil && typedValue == nil)
    }

    private func name(_ id: Id) -> String { construction.object(id)?.name ?? "?" }

    /// The object a ⊥ / ∥ / angle click would use.
    private func hoveredObject(_ mouse: Vec) -> GeoObject? {
        let resolved = construction.resolve()
        let linearOnly = tool == .angle || relFirst == nil
        return construction.hitTest(resolved, at: mouse, tolerance: tolerance) { !linearOnly || $0.isLinear }
    }

    var progress: DrawProgress {
        var out = DrawProgress()
        for id in hoveredSteps { out.highlighted.insert(id) }
        if let selection { out.highlighted.insert(selection) }
        if let relFirst { out.highlighted.insert(relFirst) }
        if let relSecond { out.highlighted.insert(relSecond) }
        if let circleCenter { out.highlighted.insert(circleCenter) }

        guard prompt == nil, let hover, let mouse = world(hover), let snap = snap(at: hover) else {
            addPendingAngle(&out)
            return out
        }
        func ghost(_ s: Snap) {
            if case .point = s { out.ghosts.append((s.pos, true)); return }
            if case .free = s { out.ghosts.append((s.pos, false)); return }
            out.ghosts.append((s.pos, true))
        }

        switch tool {
        case .point:
            ghost(snap)
            out.highlighted.formUnion(snap.targets)
        case .segment, .line, .ray:
            guard let start = lineStart, let shape = lineShape else {
                ghost(snap)
                out.highlighted.formUnion(snap.targets)
                break
            }
            drawLine(&out, start: start, shape: shape, snap: snap, mouse: mouse)
            if tool == .line { out.ghosts = [] }
        case .circle:
            if let circleCenter, let center = construction.resolve()[circleCenter] {
                let radius = typedValue ?? dist(center, circleTarget(snap, mouse: mouse))
                out.circle = (center, radius)
                out.highlighted.formUnion(snap.targets)
                if typed == nil, case .point(let id, _) = snap, id != circleCenter {
                    out.live = live("|\(name(circleCenter))\(name(id))|", radius)
                } else {
                    out.live = live("r", radius)
                }
            } else if case .point = snap {
                ghost(snap)
                out.highlighted.formUnion(snap.targets)
            }
        case .perp, .parallel:
            let hovered = hoveredObject(mouse)
            if let hovered { out.highlighted.insert(hovered.id) }
            if let relFirst, let hovered, hovered.id != relFirst, hovered.isLinear || hovered.isPoint {
                let resolved = construction.resolve()
                if case .success(let next) = construction.finishRelation(tool == .perp ? .perpendicular : .parallel, relFirst, target: hovered.id, resolved) {
                    out.result = changedShapes(next, resolved)
                }
            }
        case .angle:
            if relSecond == nil, let hovered = hoveredObject(mouse) { out.highlighted.insert(hovered.id) }
        case .move:
            if let hit = construction.hitTest(construction.resolve(), at: mouse, tolerance: tolerance) { out.highlighted.insert(hit.id) }
        }
        addPendingAngle(&out)
        return out
    }

    /// Angle tool, both lines chosen: the angle of the four at their crossing that the mouse is in.
    var hoveredAngle: AngleSector? {
        guard tool == .angle, let relFirst, let relSecond, let hover, let mouse = world(hover) else { return nil }
        return construction.angleSector(relFirst, relSecond, mouse: mouse, construction.resolve())
    }

    /// The angle being set: frozen once typing starts, otherwise the one under the mouse.
    var pendingAngle: AngleSector? { angleLock ?? hoveredAngle }

    /// Angle tool, both lines chosen: the angle under the mouse is shown with an arc and typed in the dimension box.
    private func addPendingAngle(_ out: inout DrawProgress) {
        guard tool == .angle, relFirst != nil, relSecond != nil, let sector = pendingAngle else { return }
        let resolved = construction.resolve()
        out.live = live("α", (sector.size * 180 / .pi * 100).rounded() / 100, unit: "°")
        out.angleArc = (sector.at, sector.startDir, sector.size)
        if let typedValue, typedValue > 0, typedValue < 180,
           case .success(let next) = construction.finishSectorAngle(sector, angle: typedValue * .pi / 180, resolved) {
            out.result = changedShapes(next, resolved)
        }
    }

    private func drawLine(_ out: inout DrawProgress, start: Snap, shape: LineShape, snap: Snap, mouse: Vec) {
        var used = construction.usedNames
        func takeName() -> String {
            let next = nextPointName(used)
            used.insert(next)
            return next
        }
        func label(_ s: Snap) -> String {
            if case .point(let id, _) = s { return name(id) }
            return takeName()
        }
        out.ghosts.append((start.pos, false))
        let startName = label(start)

        // Hovering the start point itself does not count as an end.
        var endSnap = snap
        if case .point(let a, _) = snap, case .point(let b, _) = start, a == b { endSnap = .free(pos: mouse) }

        let dirSnap = directionSnap(start, mouse: mouse, endSnap)
        var to: Vec
        let endName: String
        if let dirSnap {
            let resolved = construction.resolve()
            let refObject = construction.object(dirSnap.ref)
            let refGeom = refObject.flatMap { curveGeom($0, resolved) }
            var refDir = 0.0
            if case let .straight(a, b, _)? = refGeom { refDir = angleOf(a, b) }
            let newDir = refDir + dirSnap.offset
            let hit = typedValue == nil ? directionHit(start, dirSnap, mouse: mouse) : nil
            if let hit { out.highlighted.insert(hit.curve) }
            to = hit?.pos ?? polar(start.pos, typedValue ?? dist(start.pos, mouse), newDir)
            endName = takeName()
            out.ghosts.append((to, true))
            if case let .straight(a, b, ext)? = refGeom {
                let markDir = dirSnap.kind == .perpendicular ? armDirection(a, b, ext, from: start.pos) : refDir
                out.directionMark = DirectionMark(kind: dirSnap.kind, touching: dirSnap.touching, at: start.pos, refDir: markDir, newDir: newDir,
                                                  refMid: Vec(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
            }
        } else if let typedValue, shape == .segment {
            // Over an existing point the segment aims through it.
            let aim = throughPoint(start, endSnap).map { _ in endSnap.pos } ?? mouse
            if throughPoint(start, endSnap) != nil { out.highlighted.formUnion(endSnap.targets) }
            to = polar(start.pos, typedValue, dist(start.pos, aim) == 0 ? 0 : angleOf(start.pos, aim))
            endName = takeName()
            out.ghosts.append((to, false))
        } else {
            to = endSnap.pos
            if case .free = endSnap { out.ghosts.append((to, false)) } else { out.ghosts.append((to, true)) }
            out.highlighted.formUnion(endSnap.targets)
            endName = label(endSnap)
        }

        // A line or ray that crosses another one can be given an angle to it instead of a length.
        var from = start.pos
        if shape != .segment, dirSnap == nil, let cross = lineCrossing(start.pos, to, shape) {
            let at = crossingPoint(cross, from, to, shape) ?? from
            out.live = live("α", liveAngle(cross, at, to), unit: "°")
            if let typedValue, typedValue > 0, typedValue < 180, let turned = pivoted(cross, degrees: typedValue, start.pos, to, shape) {
                from = turned.a
                to = turned.b
            }
        }
        out.straight = (from, to, shape)
        // Lines and rays are infinite: no length to show or type.
        if shape == .segment { out.live = live("|\(startName)\(endName)|", dist(start.pos, to)) }
    }

    /// Curves of `next` that differ from the current drawing, for the faded preview.
    private func changedShapes(_ next: Construction, _ resolved: Resolved) -> [CurveGeom] {
        let after = next.resolve()
        return next.objects.compactMap { o in
            guard o.isCurve, let g = curveGeom(o, after) else { return nil }
            guard let old = construction.object(o.id), let g0 = curveGeom(old, resolved) else { return g }
            return Self.sameGeom(g, g0) ? nil : g
        }
    }

    private static func sameGeom(_ x: CurveGeom, _ y: CurveGeom) -> Bool {
        func near(_ a: Vec, _ b: Vec) -> Bool { dist(a, b) < 1e-6 }
        switch (x, y) {
        case let (.straight(a, b, _), .straight(c, d, _)): return near(a, c) && near(b, d)
        case let (.circle(c1, r1), .circle(c2, r2)): return near(c1, c2) && abs(r1 - r2) < 1e-6
        default: return false
        }
    }

    // MARK: Dimensions and marks in the drawing

    var dimensionLabels: [DimensionLabel] {
        guard let viewport else { return [] }
        let positions = construction.resolve()
        var out: [DimensionLabel] = construction.objects.compactMap { o in
            guard construction.isLocked(o), let geom = curveGeom(o, positions) else { return nil }
            switch geom {
            case let .straight(a, b, .segment):
                guard let sa = screen(a), let sb = screen(b) else { return nil }
                let length = max(hypot(sb.x - sa.x, sb.y - sa.y), 1)
                var nx = -(sb.y - sa.y) / length
                var ny = (sb.x - sa.x) / length
                if ny > 0 { nx = -nx; ny = -ny }
                return DimensionLabel(id: o.id, position: CGPoint(x: (sa.x + sb.x) / 2 - nx * 16, y: (sa.y + sb.y) / 2 - ny * 16),
                                      text: "\(dim(dist(a, b))) cm")
            case let .circle(center, radius):
                guard let c = screen(center) else { return nil }
                let r = radius * viewport.scale
                let end = CGPoint(x: c.x + r * cos(0.6), y: c.y + r * sin(0.6))
                return DimensionLabel(id: o.id, position: CGPoint(x: (c.x + end.x) / 2 + 8, y: (c.y + end.y) / 2 - 11),
                                      text: "r = \(dim(radius)) cm", radiusLine: (c, end))
            default:
                return nil
            }
        }
        out += angleLabels(positions)
        return out
    }

    private func geomOfLinear(_ id: Id, _ positions: Resolved) -> (a: Vec, b: Vec, ext: Extent)? {
        guard let o = construction.object(id), case let .straight(a, b, ext)? = curveGeom(o, positions) else { return nil }
        return (a, b, ext)
    }

    private func pivotOnReference(_ rel: Relation, _ positions: Resolved) -> Vec? {
        guard let x = positions[rel.pivot], let gp = geomOfLinear(rel.p, positions) else { return nil }
        let dP = angleOf(gp.a, gp.b)
        let dx = x.x - gp.a.x
        let dy = x.y - gp.a.y
        return abs(dx * sin(dP) - dy * cos(dP)) < 1e-3 ? x : nil
    }

    /// The two visible arms (world directions) an angle mark sits between. Rays and segments use the side
    /// they are drawn on; a full line may use either direction, whichever makes the related angle.
    private func angleArms(_ rel: Relation, _ x: Vec, _ positions: Resolved) -> (u: Double, v: Double)? {
        guard let gp = geomOfLinear(rel.p, positions), let gq = geomOfLinear(rel.q.id, positions) else { return nil }
        func candidates(_ g: (a: Vec, b: Vec, ext: Extent)) -> [Double] {
            let d = armDirection(g.a, g.b, g.ext, from: x)
            return g.ext == .line ? [d, d + .pi] : [d]
        }
        func between(_ u: Double, _ v: Double) -> Double { abs(atan2(sin(v - u), cos(v - u))) }
        var best: (u: Double, v: Double)?
        for u in candidates(gp) {
            for v in candidates(gq) where best == nil || abs(between(u, v) - rel.angle) < abs(between(best!.u, best!.v) - rel.angle) {
                best = (u, v)
            }
        }
        return best
    }

    private func angleLabels(_ positions: Resolved) -> [DimensionLabel] {
        construction.allRelations().compactMap { rel in
            guard rel.kind == .angle, let x = pivotOnReference(rel, positions), let sx = screen(x), let arms = angleArms(rel, x, positions) else { return nil }
            let u = screenDirection(arms.u)
            let v = screenDirection(arms.v)
            let length = max(hypot(u.dx + v.dx, u.dy + v.dy), 1e-9)
            let shown = abs(atan2(sin(arms.v - arms.u), cos(arms.v - arms.u)))
            let degrees = (shown * 180 / .pi * 100).rounded() / 100
            return DimensionLabel(id: rel.q.id, position: CGPoint(x: sx.x + 38 * (u.dx + v.dx) / length, y: sx.y + 38 * (u.dy + v.dy) / length),
                                  text: "\(dim(degrees))°", isAngle: true)
        }
    }

    var relationMarks: [RelationMark] {
        let positions = construction.resolve()
        let relations = construction.allRelations()

        // Parallel lines share a group, and each group has its own number of ticks.
        var groupOf: [Id: Int] = [:]
        var nextGroup = 0
        func merge(_ x: Id, _ y: Id) {
            switch (groupOf[x], groupOf[y]) {
            case (nil, nil):
                groupOf[x] = nextGroup
                groupOf[y] = nextGroup
                nextGroup += 1
            case (nil, let gy?): groupOf[x] = gy
            case (let gx?, nil): groupOf[y] = gx
            case let (gx?, gy?):
                if gx != gy { for (k, v) in groupOf where v == gy { groupOf[k] = gx } }
            }
        }
        for rel in relations where rel.kind == .parallel { merge(rel.p, rel.q.id) }
        var rank: [Int: Int] = [:]
        for object in construction.objects {
            if let g = groupOf[object.id], rank[g] == nil { rank[g] = rank.count }
        }

        var ticked = Set<Id>()
        var marks: [RelationMark] = []
        for rel in relations {
            guard let gp = geomOfLinear(rel.p, positions), let gq = geomOfLinear(rel.q.id, positions) else { continue }
            let dP = angleOf(gp.a, gp.b)
            if rel.kind == .parallel {
                let count = ((groupOf[rel.q.id].flatMap { rank[$0] } ?? 0) % 3) + 1
                for id in [rel.p, rel.q.id] where !ticked.contains(id) {
                    guard let g = geomOfLinear(id, positions), let mid = screen(Vec(x: (g.a.x + g.b.x) / 2, y: (g.a.y + g.b.y) / 2)) else { continue }
                    ticked.insert(id)
                    marks.append(.ticks(at: mid, dir: screenDirection(angleOf(g.a, g.b)), count: count, id: id))
                }
                continue
            }
            guard let x = pivotOnReference(rel, positions), let sx = screen(x) else {
                if rel.kind == .perpendicular, let mid = screen(Vec(x: (gq.a.x + gq.b.x) / 2, y: (gq.a.y + gq.b.y) / 2)) {
                    marks.append(.perpendicularSign(at: CGPoint(x: mid.x + 12, y: mid.y - 12), id: rel.q.id))
                }
                continue
            }
            if rel.kind == .perpendicular {
                marks.append(.rightAngle(at: sx, u: screenDirection(armDirection(gp.a, gp.b, gp.ext, from: x)),
                                         v: screenDirection(armDirection(gq.a, gq.b, gq.ext, from: x)), id: rel.q.id))
            } else if let arms = angleArms(rel, x, positions) {
                marks.append(.arc(at: sx, u: screenDirection(arms.u), v: screenDirection(arms.v), id: rel.q.id))
            }
        }
        return marks
    }

    var hint: String {
        if let message { return message }
        switch tool {
        case .move: return t("hint.move")
        case .point: return t("hint.point")
        case .segment: return t(lineStart == nil ? "hint.segmentStart" : "hint.segmentEnd")
        case .line: return t(lineStart == nil ? "hint.lineStart" : "hint.lineEnd")
        case .ray: return t(lineStart == nil ? "hint.rayStart" : "hint.rayEnd")
        case .circle: return t(circleCenter == nil ? "hint.circleCenter" : "hint.circleRadius")
        case .perp: return t(relFirst == nil ? "hint.perpFirst" : "hint.perpSecond")
        case .parallel: return t(relFirst == nil ? "hint.parallelFirst" : "hint.parallelSecond")
        case .angle: return t(relFirst == nil ? "hint.angleFirst" : (relSecond == nil ? "hint.angleSecond" : "hint.angleType"))
        }
    }
}
