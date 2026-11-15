import AppKit
import CoreGraphics
import Foundation
import GeoEngine

extension DrawingStore {
    var lineShape: LineShape? {
        switch tool {
        case .segment: .segment
        case .line: .line
        case .ray: .ray
        default: nil
        }
    }

    var typedValue: Double? { typed.flatMap(parseNumber) }

    func finishDrawing() {
        cancel()
    }

    // MARK: Drag gesture

    func dragChanged(from start: CGPoint, to location: CGPoint) {
        hover = location
        if drag == nil {
            closePromptKeepingValid()
            // Clicking the drawing ends typing in the panels, which keeps their focus otherwise.
            NSApp.keyWindow?.makeFirstResponder(nil)
            pressLocation = start
            dragMoved = false
            drag = beginDrag(at: start)
            dragStart = construction
        }
        if hypot(location.x - start.x, location.y - start.y) >= Self.dragThreshold { dragMoved = true }
        guard dragMoved else { return }
        switch drag {
        case .point(let id):
            if let target = world(location) { construction.dragPoint(id, to: target) }
        case .circle(let id):
            if let target = world(location), let k = construction.object(id),
               case let .circle(center, _)? = curveGeom(k, construction.resolve()) {
                construction.resizeCircle(id, radius: dist(center, target))
            }
        case let .segment(id, last):
            if let target = world(location) {
                construction.translateSegment(id, dx: target.x - last.x, dy: target.y - last.y)
                drag = .segment(id, last: target)
            }
        case .pan(let last):
            pan(dx: location.x - last.x, dy: location.y - last.y)
            drag = .pan(last: location)
        default:
            break
        }
    }

    func dragEnded(at location: CGPoint) {
        if let dragStart, dragStart != construction { recordUndo(from: dragStart) }
        dragStart = nil
        if case .click = drag { click(at: location) }
        if tool == .move, !dragMoved { registerMoveClick(at: location) }
        drag = nil
    }

    private func label(at p: CGPoint) -> DimensionLabel? {
        dimensionLabels.first { abs($0.position.x - p.x) < 36 && abs($0.position.y - p.y) < 12 }
    }

    private func beginDrag(at start: CGPoint) -> Drag {
        switch tool {
        case .move:
            if !clean, let label = label(at: start) {
                selection = label.id
                return .ignored
            }
            guard let p = world(start),
                  let hit = construction.hitTest(construction.resolve(), at: p, tolerance: tolerance) else {
                selection = nil
                return .pan(last: start)
            }
            selection = hit.id
            let exercise = construction.isExercise(hit.id)
            if isDraggable(hit) {
                if exercise {
                    _ = refuseExercise(hit.id)
                    return .ignored
                }
                return .point(hit.id)
            }
            switch hit {
            case .circle(let k):
                if exercise {
                    _ = refuseExercise(hit.id)
                    return .ignored
                }
                if k.through == nil, k.span == nil, !k.locked { return .circle(k.id) }
            case .segment(let s):
                if !exercise, construction.canTranslateSegment(s.id), let p = world(start) { return .segment(s.id, last: p) }
            default:
                break
            }
            return .ignored
        case .point, .segment, .line, .ray, .circle, .perp, .parallel, .angle:
            return .click
        }
    }

    private func registerMoveClick(at location: CGPoint) {
        if let last = lastClick, Date().timeIntervalSince(last.time) < Self.doubleClickSeconds,
           hypot(location.x - last.location.x, location.y - last.location.y) < 5 {
            lastClick = nil
            doubleClick(at: location)
        } else {
            lastClick = (Date(), location)
        }
    }

    private func doubleClick(at location: CGPoint) {
        if !clean, let label = label(at: location), let o = construction.object(label.id) {
            guard !refuseExercise(o.id) else { return }
            if label.isAngle { openAnglePrompt(o) } else { openDimensionPrompt(o) }
            return
        }
        guard let p = world(location), let hit = construction.hitTest(construction.resolve(), at: p, tolerance: tolerance) else { return }
        selection = hit.id
        guard !refuseExercise(hit.id) else { return }
        switch hit {
        case .segment, .circle: openDimensionPrompt(hit)
        default: openNamePrompt(hit)
        }
    }

    // MARK: Clicks

    private func click(at location: CGPoint) {
        guard let snap = snap(at: location), let mouse = world(location) else { return }
        message = nil
        switch tool {
        case .point: clickPoint(snap)
        case .segment, .line, .ray: clickLine(snap, mouse: mouse)
        case .circle: clickCircle(snap, mouse: mouse)
        case .perp: clickRelation(.perpendicular, mouse: mouse)
        case .parallel: clickRelation(.parallel, mouse: mouse)
        case .angle: clickAngle(mouse: mouse)
        case .move: break
        }
    }

    private func clickPoint(_ snap: Snap) {
        if case .point(let id, _) = snap {
            selection = id
            return
        }
        var placed: Id?
        commit {
            placed = $0.placePoint(snap)
            return placed != nil
        }
        if let placed {
            selection = placed
            if let o = construction.object(placed) { openNamePrompt(o, fresh: true) }
        }
    }

    private func clickLine(_ snap: Snap, mouse: Vec) {
        guard let shape = lineShape else { return }
        guard let start = lineStart else {
            lineStart = snap
            typed = nil
            return
        }
        if let dirSnap = directionSnap(start, mouse: mouse, snap) {
            commitLine(start, directionEnd(start, dirSnap, mouse: mouse, typedLength: typedValue), shape)
        } else if let typedValue {
            if shape == .segment, let through = throughPoint(start, snap) {
                commitLine(start, .lengthThrough(typedValue, point: through), shape)
            } else if shape == .segment {
                commitLine(start, .length(typedValue, toward: mouse), shape)
            } else {
                commitLineAngle(start, mouse: mouse, degrees: typedValue, shape)
            }
        } else if case .point(let end, _) = snap, case .point(let begin, _) = start, end == begin {
            return // clicked the start point again
        } else {
            commitLine(start, .snap(snap), shape)
        }
    }

    private func commitLine(_ start: Snap, _ end: SegmentEnd, _ shape: LineShape) {
        commit { $0.finishSegment(start: start, end: end, shape: shape) }
        finishDrawing()
    }

    private func clickCircle(_ snap: Snap, mouse: Vec) {
        guard let center = circleCenter else {
            if case .point(let id, _) = snap {
                circleCenter = id
                typed = nil
            } else {
                flash("hint.needExistingCenter")
            }
            return
        }
        if let typedValue {
            commit { $0.finishCircle(center: center, radius: typedValue, locked: true) }
        } else if case .point(let id, _) = snap, id != center {
            commit { $0.finishCircleThrough(center: center, through: id) }
        } else if let centerPos = construction.resolve()[center] {
            let radius = dist(centerPos, circleTarget(snap, mouse: mouse))
            commit { $0.finishCircle(center: center, radius: radius, locked: false) }
        } else {
            return
        }
        selection = nil
        finishDrawing()
    }

    /// The point the radius reaches to; the centre itself cannot be its own target.
    func circleTarget(_ snap: Snap, mouse: Vec) -> Vec {
        if case .point(let id, _) = snap, id == circleCenter { return mouse }
        return snap.pos
    }

    private func clickRelation(_ kind: RelationTool, mouse: Vec) {
        let resolved = construction.resolve()
        guard let first = relFirst else {
            relFirst = construction.hitTest(resolved, at: mouse, tolerance: tolerance) { $0.isLinear }?.id
            return
        }
        guard let target = construction.hitTest(resolved, at: mouse, tolerance: tolerance), target.id != first else { return }
        switch construction.finishRelation(kind, first, target: target.id, resolved) {
        case .success(let next):
            commit {
                $0 = next
                return true
            }
            selection = target.id
            cancel()
        case .failure(let error):
            flash(key(for: error))
        }
    }

    private func clickAngle(mouse: Vec) {
        let resolved = construction.resolve()
        // Both lines chosen: a click sets the angle it is in, to the typed value or the shown one rounded.
        if relSecond != nil {
            guard let sector = pendingAngle else { return }
            if typed != nil, typedValue == nil { return }
            commitAngle(sector, degrees: typedValue ?? (sector.size * 180 / .pi).rounded())
            return
        }
        guard relSecond == nil, let line = construction.hitTest(resolved, at: mouse, tolerance: tolerance, filter: { $0.isLinear }) else { return }
        guard let first = relFirst else {
            relFirst = line.id
            return
        }
        guard line.id != first, let p = construction.object(first), let gp = curveGeom(p, resolved),
              let gq = curveGeom(line, resolved) else { return }
        if intersect(gp, gq).first ?? nil != nil {
            relSecond = line.id
            typed = nil
        } else {
            flash("error.noIntersection")
        }
    }

    func key(for error: RelationError) -> String {
        switch error {
        case .cannotRotate: "error.cannotRotate"
        case .noIntersection: "error.noIntersection"
        }
    }

    /// A segment of a typed length aims at the existing point under the mouse (not the start itself).
    func throughPoint(_ start: Snap, _ snap: Snap) -> Id? {
        guard case .point(let id, let pos) = snap, dist(start.pos, pos) > 0 else { return nil }
        if case .point(let startId, _) = start, startId == id { return nil }
        return id
    }

    // MARK: Direction snapping

    func directionSnap(_ start: Snap, mouse: Vec, _ snap: Snap) -> DirectionSnap? {
        if case .point = snap { return nil }
        return construction.findDirectionSnap(construction.resolve(), start: start.pos, mouse: mouse)
    }

    func snapHeading(_ d: DirectionSnap) -> Double {
        (construction.directionOf(d.ref, construction.resolve()) ?? 0) + d.offset
    }

    func directionHit(_ start: Snap, _ d: DirectionSnap, mouse: Vec) -> DirectionHit? {
        construction.findDirectionHit(construction.resolve(), start: start.pos, dir: snapHeading(d), mouse: mouse, tolerance: tolerance)
    }

    /// End of a ⊥ / ∥ line: on the curve it meets near the mouse, else at the typed / eyeballed distance.
    func directionEnd(_ start: Snap, _ d: DirectionSnap, mouse: Vec, typedLength: Double?) -> SegmentEnd {
        let hit = typedLength == nil ? directionHit(start, d, mouse: mouse) : nil
        let distance = typedLength ?? hit.map { dist(start.pos, $0.pos) } ?? dist(start.pos, mouse)
        return .direction(ref: d.ref, offset: d.offset, distance: distance, locked: typedLength != nil,
                          onCurve: hit.map { OnCurve(id: $0.curve, index: $0.index) })
    }

    // MARK: Lines at a typed angle

    private func drawnGeom(_ start: Vec, _ to: Vec, _ shape: LineShape) -> CurveGeom {
        .straight(a: start, b: to, ext: shape == .ray ? .ray : (shape == .line ? .line : .segment))
    }

    /// The first other straight object that a line / ray drawn from `start` towards `to` crosses.
    func lineCrossing(_ start: Vec, _ to: Vec, _ shape: LineShape) -> GeoObject? {
        if dist(start, to) == 0 { return nil }
        let resolved = construction.resolve()
        let drawn = drawnGeom(start, to, shape)
        return construction.objects.first { o in
            guard o.isLinear, let g = curveGeom(o, resolved) else { return false }
            return intersect(drawn, g).contains { $0 != nil }
        }
    }

    func crossingPoint(_ cross: GeoObject, _ start: Vec, _ to: Vec, _ shape: LineShape) -> Vec? {
        guard let g = curveGeom(cross, construction.resolve()) else { return nil }
        return intersect(drawnGeom(start, to, shape), g).first ?? nil
    }

    private func direction(of o: GeoObject) -> Double {
        construction.directionOf(o.id, construction.resolve()) ?? 0
    }

    /// The angle is measured on the side of `cross` the mouse is on: between the ray towards the mouse
    /// and the ray of `cross` that points left.
    private func angleSide(_ cross: GeoObject, _ x: Vec, _ mouse: Vec) -> (rho: Double, left: Double, toMouse: Double, turn: Double) {
        let rho = direction(of: cross)
        let toMouse = dist(x, mouse) == 0 ? rho : angleOf(x, mouse)
        let side: Double = sin(toMouse - rho) >= 0 ? 1 : -1
        let c = cos(rho)
        let leftward = c < -1e-9 || (abs(c) <= 1e-9 && sin(rho) > 0)
        return (rho, leftward ? rho : rho + .pi, toMouse, leftward ? side : -side)
    }

    func liveAngle(_ cross: GeoObject, _ x: Vec, _ mouse: Vec) -> Double {
        let (_, left, toMouse, _) = angleSide(cross, x, mouse)
        let d = abs(atan2(sin(toMouse - left), cos(toMouse - left)))
        return (d * 180 / .pi * 100).rounded() / 100
    }

    /// A line from `start` towards `mouse` turned about where it meets `cross` to make `degrees` with it.
    func pivoted(_ cross: GeoObject, degrees: Double, _ start: Vec, _ mouse: Vec, _ shape: LineShape) -> (a: Vec, b: Vec, offset: Double)? {
        guard let x = crossingPoint(cross, start, mouse, shape) else { return nil }
        let (rho, left, _, turn) = angleSide(cross, x, mouse)
        let dir = left + turn * degrees * .pi / 180
        let heading = angleOf(start, mouse)
        func along(_ p: Vec) -> Double { (p.x - x.x) * cos(heading) + (p.y - x.y) * sin(heading) }
        return (polar(x, along(start), dir), polar(x, along(mouse), dir), dir - rho)
    }

    private func commitLineAngle(_ start: Snap, mouse: Vec, degrees: Double, _ shape: LineShape) {
        guard let cross = lineCrossing(start.pos, mouse, shape), degrees > 0, degrees < 180,
              let turn = pivoted(cross, degrees: degrees, start.pos, mouse, shape) else { return }
        var drawn = construction
        guard drawn.finishSegment(start: start, end: .snap(.free(pos: mouse)), shape: shape), let made = drawn.objects.last else { return }
        switch drawn.rotateRelativeTo(cross.id, made.id, offset: turn.offset, pivot: .intersection, drawn.resolve()) {
        case .success(let next):
            commit {
                $0 = next
                return true
            }
            selection = made.id
        case .failure(let error):
            flash(key(for: error))
        }
        finishDrawing()
    }

    // MARK: Enter in the dimension box

    func commitTyped() {
        guard let live = progress.live, typed == nil || typedValue != nil, let hover, let mouse = world(hover) else { return }
        let value = typedValue ?? live.number
        if tool == .angle, relFirst != nil, relSecond != nil {
            if let sector = pendingAngle { commitAngle(sector, degrees: value) }
        } else if let start = lineStart, let shape = lineShape {
            if shape != .segment {
                commitLineAngle(start, mouse: mouse, degrees: value, shape)
            } else if let snap = snap(at: hover), let dirSnap = directionSnap(start, mouse: mouse, snap) {
                commitLine(start, directionEnd(start, dirSnap, mouse: mouse, typedLength: typedValue), shape)
            } else if let typedValue, let snap = snap(at: hover), let through = throughPoint(start, snap) {
                commitLine(start, .lengthThrough(typedValue, point: through), shape)
            } else {
                commitLine(start, .length(value, toward: mouse), shape)
            }
        } else if let center = circleCenter {
            commit { $0.finishCircle(center: center, radius: value, locked: true) }
            selection = nil
            finishDrawing()
        }
    }

    private func commitAngle(_ sector: AngleSector, degrees: Double) {
        switch construction.finishSectorAngle(sector, angle: degrees * .pi / 180, construction.resolve()) {
        case .success(let next):
            commit {
                $0 = next
                return true
            }
            selection = sector.end
            cancel()
        case .failure(let error):
            flash(degrees > 0 && degrees < 180 ? key(for: error) : "error.angle")
        }
    }
}
