import AppKit
import Foundation
import GeoEngine

/// What the sidebar's selected item does on the canvas.
enum GraphTool: Equatable {
    case move
    /// A function being clicked into the grid.
    case place(FunctionKind)
    /// Restrict: pick a graph, then click where the piece starts and ends (a circle: then the arc to keep).
    case cut
    /// Intersect: pick two graphs; a row keeps where they cross.
    case intersect
    /// Fill: pick the graphs round an area, then click inside it.
    case fill
}

/// What is drawn over the graphs while a tool is on.
struct GraphOverlay {
    var points: [Vec] = []
    var guides: [Guide] = []
    var cursor: Vec?
    /// The graph through the pointer (when cutting: the piece kept, drawn bold instead of dashed).
    var preview: Drawn?
    var cutting = false
    /// When cutting: all of the graph picked, faint, so that a piece can be made longer too.
    var faint: Drawn?
    /// Intersect: the graph picked first; Fill: the graphs round the area. Drawn bold in their own colours.
    var picked: [(drawn: Drawn, color: String)] = []
    /// Fill: the area a click would fill.
    var fill: Region?
    /// Where graphs cross each other and the axes: a click there lands exactly on it.
    var crossings: [Vec] = []
    var color: String
}

extension GraphStore {
    /// A click this close (px) to where graphs cross lands exactly there.
    static let crossingSnap = 12.0

    /// The forms of the families with several, in order.
    static let forms: [String: [FunctionKind]] = [
        "parabola": [.parabolaVertex, .parabolaIntercept, .parabolaGeneral],
        "cubic": [.cubicInflection, .cubicIntercept, .cubicGeneral],
        "trig": [.sin, .cos, .tan],
    ]

    /// The form of a family used last.
    func lastForm(_ family: String) -> FunctionKind {
        let forms = Self.forms[family] ?? []
        if let saved = UserDefaults.standard.string(forKey: "geoscript.\(family)Form"),
           let kind = FunctionKind(rawValue: "\(family).\(saved)"), forms.contains(kind) { return kind }
        return forms.first ?? .linear
    }

    /// Starts placing a function (the same one again stops); a form is remembered for its family.
    func pick(_ kind: FunctionKind) {
        if Self.forms[kind.family] != nil {
            UserDefaults.standard.set(String(kind.rawValue.dropFirst(kind.family.count + 1)), forKey: "geoscript.\(kind.family)Form")
        }
        selected = nil
        focused = nil
        tool = .place(kind)
    }

    func resetTool() {
        placed = []
        cursor = nil
        rawCursor = nil
        refused = nil
        cutId = nil
        intersectFirst = nil
        fillPicks = []
        hoverId = nil
        if tool != .move {
            selected = nil
            focused = nil
        }
    }

    var placingKind: FunctionKind? {
        if case .place(let kind) = tool { return kind }
        return nil
    }

    var kindRules: PlacingKind? { placingKind.map { GeoEngine.placingKind($0, sideways: sideways) } }

    /// Which axis is marked in multiples of π: while placing a sine, cosine or tangent.
    var piAxisX: Bool? {
        guard let kind = placingKind, kind.usesPi else { return nil }
        return !sideways
    }

    /// The colour the next row gets.
    var nextColor: String { state.nextColor }

    // MARK: Snapping

    /// The grid steps along one axis: the usual ones, or the π grid.
    func axisStep(pi: Bool, _ scale: Double) -> (major: Double, minor: Double) {
        pi ? piGridStep(scale) : GraphCanvas.gridStep(scale)
    }

    /// A click lands on the nearest crossing of the fine grid lines.
    func snapToGrid(_ p: Vec, _ scale: Double) -> Vec {
        func round(_ v: Double, _ minor: Double) -> Double { jsPrecision12(jsRound(v / minor) * minor) }
        return Vec(x: round(p.x, axisStep(pi: piAxisX == true, scale).minor), y: round(p.y, axisStep(pi: piAxisX == false, scale).minor))
    }

    /// The point under the pointer: a nearby crossing of graphs, else the grid; with ⌥, exactly there.
    private func snapped(_ screen: CGPoint, _ raw: Vec) -> Vec {
        guard let v = viewport else { return raw }
        if NSEvent.modifierFlags.contains(.option) { return raw }
        var best: Vec?
        var bestDist = Self.crossingSnap
        for c in snapCrossings() {
            let s = v.toScreen(c)
            let d = hypot(s.x - screen.x, s.y - screen.y)
            if d < bestDist { (best, bestDist) = (c, d) }
        }
        return best ?? snapToGrid(raw, v.scale)
    }

    /// Where the shown graphs (and, while cutting, the whole graph picked) cross each other and the axes.
    func snapCrossings() -> [Vec] {
        guard let v = viewport, tool != .move, tool != .intersect, tool != .fill else { return [] }
        if tool == .cut && cutId == nil { return [] }
        let key = "\(revision) \(v.scale) \(v.tx) \(v.ty) \(canvasSize) \(cutId ?? "")"
        if let cached = crossingCache, cached.key == key { return cached.points }
        let view = view(v, canvasSize)
        var shown: [Drawn] = zip(rows, compiled).filter { !$0.0.hidden && $0.1.error == nil }.map(\.1.drawn)
        if let full = cutWhole() { shown.append(full.drawn) }
        let fns = shown.compactMap(\.fn), circles = shown.compactMap(\.circle), gs = shown.compactMap(\.fnOfY)
        let width = canvasSize.width, height = canvasSize.height
        let points = (sidewaysCrossings(gs, fns, circles, view.yMin, view.yMax, samples: height).filter { $0.x >= view.xMin && $0.x <= view.xMax }
            + snapPoints(fns, view.xMin, view.xMax, samples: width)
            + circleCrossings(circles, fns, perUnit: v.scale).filter { $0.x >= view.xMin && $0.x <= view.xMax })
            .filter { $0.y >= view.yMin && $0.y <= view.yMax }
        crossingCache = (key, points)
        return points
    }

    // MARK: Pointer

    func toolHover(_ screen: CGPoint?) {
        guard let screen, let raw = world(screen) else {
            cursor = nil
            rawCursor = nil
            hoverId = nil
            return
        }
        let at = snapped(screen, raw)
        switch tool {
        case .move:
            break
        case .place:
            guard let k = kindRules else { return }
            let p = k.constrain(placed, at)
            cursor = p
            // The warning stays until the pointer is somewhere a click would work.
            if k.reject(placed, p) == nil { refused = nil }
        case .cut:
            rawCursor = raw
            if cutId == nil {
                hoverId = graphAt(raw) { $0.region == nil }
                if hoverId != nil { refused = nil }
            } else {
                cursor = landCut(at, raw)
                if cursor != nil { refused = nil }
            }
        case .intersect:
            hoverId = graphAt(raw)
            if let hoverId, hoverId != intersectFirst { refused = nil }
        case .fill:
            rawCursor = raw
            hoverId = graphAt(raw, canBound)
            if hoverId != nil || fillResult(raw) != nil { refused = nil }
        }
    }

    func toolClick(at screen: CGPoint) {
        guard let raw = world(screen) else { return }
        let at = snapped(screen, raw)
        switch tool {
        case .move: break
        case .place: place(at)
        case .cut: cutClick(at, raw)
        case .intersect: intersectClick(raw)
        case .fill: fillClick(raw)
        }
    }

    private func place(_ at: Vec) {
        guard let k = kindRules else { return }
        let p = k.constrain(placed, at)
        if let reason = k.reject(placed, p) { return refused = reason }
        refused = nil
        if placed.count + 1 < k.hints.count { return placed.append(p) }
        guard let text = k.through(placed, p, usesComma) else { return }
        commit(state.adding(text))
        tool = .move
    }

    // MARK: Restrict

    /// The row being restricted, all of it: its restrictions left out, so that a piece can grow too.
    func cutWhole() -> CompiledRow? {
        guard tool == .cut, let id = cutId, let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
        var whole = rows
        whole[i].text = withoutWhere(whole[i].text)
        return compileRows(whole)[i]
    }

    private func landCut(_ snapped: Vec, _ raw: Vec) -> Vec? {
        guard let full = cutWhole(), let v = viewport else { return nil }
        return landOn(full.drawn, snapped: snapped, raw: raw, grid: GraphCanvas.gridStep(v.scale).minor, reach: Self.pickReach / v.scale)
    }

    /// The row text once the next click is at p (`raw` for the arc of a circle), or nil while more ends are needed.
    func cutResult(_ p: Vec, _ raw: Vec) -> String? {
        guard let id = cutId, let text = row(id)?.text, let full = cutWhole() else { return nil }
        if let alongX = cutAlongX(full.drawn) {
            return placed.first.map { intervalText(text, alongX: alongX, $0, p, comma: usesComma) }
        }
        return placed.count == 2 ? arcText(text, placed[0], placed[1], keep: raw, comma: usesComma) : nil
    }

    private func cutClick(_ snapped: Vec, _ raw: Vec) {
        guard let id = cutId else {
            guard let id = graphAt(raw, { $0.region == nil }) else { return refused = "graph.hint.cut.miss" }
            refused = nil
            hoverId = nil
            cutId = id
            placed = []
            return
        }
        guard let p = landCut(snapped, raw) else { return refused = "graph.hint.cut.off" }
        if placed.count == 1, hypot(p.x - placed[0].x, p.y - placed[0].y) < graphEps { return refused = "graph.hint.cut.same" }
        let needed = cutWhole().flatMap { cutAlongX($0.drawn) } != nil ? 2 : 3
        if placed.count + 1 < needed {
            refused = nil
            return placed.append(p)
        }
        guard let text = cutResult(p, raw) else { return refused = "graph.hint.cut.onChord" }
        commit(state.updating(id) { $0.text = text })
        tool = .move
    }

    // MARK: Intersect

    private func intersectClick(_ raw: Vec) {
        guard let id = graphAt(raw) else { return refused = "graph.hint.cut.miss" }
        // Crossings are found for functions, x = … and circles only.
        if let c = compiledRow(id), c.region != nil || c.implicit != nil { return refused = "graph.hint.cross.curve" }
        if id == intersectFirst { return refused = "graph.hint.cross.same" }
        if let first = intersectFirst, rows.contains(where: { ($0.between ?? []).contains(first) && ($0.between ?? []).contains(id) }) {
            return refused = "graph.hint.cross.twice"
        }
        refused = nil
        guard let first = intersectFirst else { return intersectFirst = id }
        commit(state.addingCrossing(first, id))
        // Ready for the next two.
        intersectFirst = nil
    }

    // MARK: Fill

    /// Graphs that can bound an area (not a shaded row or a row of crossings).
    private var canBound: (CompiledRow) -> Bool {
        { $0.fn != nil || $0.fnOfY != nil || $0.circle != nil || $0.implicit != nil }
    }

    /// A picked row compiled whole (its restrictions left out): it bounds the area all along.
    private func whole(_ id: String) -> CompiledRow? {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return nil }
        var all = rows
        all[i].text = withoutWhere(all[i].text)
        return compileRows(all)[i]
    }

    /// The row that fills the area round p, or nil (p on a picked graph, or one isn't defined there).
    func fillResult(_ p: Vec) -> String? {
        guard !fillPicks.isEmpty else { return nil }
        var sides: [String] = []
        for id in fillPicks {
            guard let row = row(id), let c = whole(id), let side = sideText(row.text, c, p) else { return nil }
            sides.append(side)
        }
        return fillText(sides)
    }

    private func fillClick(_ raw: Vec) {
        if let id = graphAt(raw, canBound) {
            // A graph picked again is dropped.
            refused = nil
            if fillPicks.contains(id) { fillPicks.removeAll { $0 == id } } else { fillPicks.append(id) }
            return
        }
        if fillPicks.isEmpty { return refused = "graph.hint.fill.pickFirst" }
        guard let text = fillResult(raw) else { return refused = "graph.hint.fill.outside" }
        // Its borders are the graphs picked, already drawn: the new row has no line of its own.
        commit(state.adding(text, width: 0))
        fillPicks = []
    }

    // MARK: What is shown

    private func compileOne(_ text: String) -> CompiledRow { compileRows([GraphRow(id: "preview", text: text, color: "")])[0] }

    /// The row being placed as it would be with the pointer where it is: its text, and whether it is the
    /// function itself (else a helper, and the panel shows the template).
    var placingPreview: PlacingPreview? {
        guard let k = kindRules, let cursor else { return nil }
        return k.preview(placed, cursor, usesComma)
    }

    func overlay() -> GraphOverlay? {
        switch tool {
        case .move:
            return nil
        case .place:
            let k = kindRules
            return GraphOverlay(points: placed, guides: k?.guides(placed, cursor) ?? [], cursor: cursor,
                                preview: placingPreview?.text.map { compileOne($0).drawn }, crossings: snapCrossings(), color: nextColor)
        case .cut:
            let full = cutWhole()
            var preview = hoverId.flatMap(compiledRow)?.drawn
            if cutId != nil, let cursor, let rawCursor {
                preview = cutResult(cursor, rawCursor).flatMap { text in
                    guard let i = rows.firstIndex(where: { $0.id == cutId }) else { return nil }
                    var all = rows
                    all[i].text = text
                    return compileRows(all)[i].drawn
                }
            }
            return GraphOverlay(points: placed, cursor: cutId != nil ? cursor : nil, preview: preview, cutting: true,
                                faint: full?.drawn, crossings: snapCrossings(), color: row(cutId ?? hoverId ?? "")?.color ?? nextColor)
        case .intersect:
            let first = intersectFirst.flatMap { id in compiledRow(id).map { ($0.drawn, row(id)?.color ?? "gray") } }
            return GraphOverlay(preview: hoverId.flatMap(compiledRow)?.drawn, cutting: true, picked: first.map { [$0] } ?? [],
                                color: row(hoverId ?? "")?.color ?? nextColor)
        case .fill:
            let picked = fillPicks.compactMap { id in whole(id).map { ($0.drawn, row(id)?.color ?? "gray") } }
            let area = hoverId == nil ? rawCursor.flatMap(fillResult).flatMap { compileRows(rows + [GraphRow(id: "preview", text: $0, color: "")]).last?.region } : nil
            return GraphOverlay(preview: hoverId.flatMap(compiledRow)?.drawn, cutting: true, picked: picked, fill: area,
                                color: hoverId != nil ? row(hoverId!)?.color ?? nextColor : nextColor)
        }
    }

    /// The hint under the canvas, and whether it is a warning.
    var hint: (key: String, warning: Bool) {
        if let refused { return (refused, true) }
        switch tool {
        case .move: return (selected == nil ? "graph.hint" : "graph.hint.selected", false)
        case .place: return (kindRules?.hints[min(placed.count, (kindRules?.hints.count ?? 1) - 1)] ?? "graph.hint", false)
        case .cut:
            if cutId == nil { return ("graph.hint.cut.pick", false) }
            return (["graph.hint.cut.start", "graph.hint.cut.end", "graph.hint.cut.arc"][min(placed.count, 2)], false)
        case .intersect: return (intersectFirst == nil ? "graph.hint.cross.first" : "graph.hint.cross.second", false)
        case .fill: return (fillPicks.isEmpty ? "graph.hint.fill.pick" : "graph.hint.fill.inside", false)
        }
    }
}
