import CoreGraphics
import Foundation
import GeoEngine
import Observation

/// Graphs mode of one document: the function rows with their own undo history (separate from the
/// drawing's, as on the web), the view of the plane, and what is selected.
@MainActor @Observable
final class GraphStore {
    /// Pixels per unit the view can zoom between.
    static let zoomRange = 1e-3...1e6
    /// A click this close (px) to a graph picks it.
    static let pickReach = 10.0
    /// The pointer this close (px) to a marked point shows its coordinates.
    static let markReach = 9.0
    /// A press that moves less than this is a click, not a pan.
    static let clickSlop = 4.0

    private(set) var state = GraphState() {
        didSet {
            compiled = compileRows(state.rows)
            revision += 1
        }
    }
    private(set) var compiled: [CompiledRow] = []
    private(set) var history = History<GraphState>()
    /// Goes up whenever the rows change.
    private(set) var revision = 0

    var viewport: Viewport?
    var canvasSize: CGSize = .zero
    /// The selected row: its graph is drawn bolder, with where it crosses the others.
    var selected: String? {
        didSet { if selected != oldValue { pinned = [] } }
    }
    /// Marked points whose coordinates stay shown.
    var pinned: [Vec] = []
    /// The marked point under the pointer.
    var hoveredMark: Vec?
    /// The row being typed into, and whether it has already recorded its undo step.
    var focused: String? {
        didSet { if focused != oldValue { edited = false } }
    }
    @ObservationIgnored private var edited = false
    /// The style being dragged (a slider or the colour picker) has recorded its undo step.
    @ObservationIgnored private var styleEditing = false

    /// Called after every change of the rows, so the document is saved.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Numbers in new rows are written with a decimal comma (Czech).
    @ObservationIgnored var usesComma = true
    @ObservationIgnored var crossingCache: (key: String, points: [Vec])?
    @ObservationIgnored var dragLast: CGPoint?
    @ObservationIgnored private var dragMoved = false

    // MARK: Tools of the sidebar (see GraphStore+Tools.swift)

    var tool: GraphTool = .move {
        didSet { if tool != oldValue { resetTool() } }
    }
    /// Functions are placed as x = f(y).
    var sideways = false {
        didSet {
            // A function being placed starts again, the other way round.
            placed = []
            refused = nil
        }
    }
    /// Points clicked so far while placing (or the ends of a piece while restricting).
    var placed: [Vec] = []
    /// Where a click would land, and the pointer exactly.
    var cursor: Vec?
    var rawCursor: Vec?
    /// Why the last click did nothing, shown as a warning instead of the hint.
    var refused: String?
    /// Restrict: the row picked. Intersect: the row picked first. Fill: the rows round the area.
    var cutId: String?
    var intersectFirst: String?
    var fillPicks: [String] = []
    /// The graph under the pointer while picking one.
    var hoverId: String?

    // MARK: Rows and history

    var rows: [GraphRow] { state.rows }
    /// The id the next row gets: the empty row waiting at the bottom already has it.
    var newId: String { "g\(state.nextId)" }

    func load(_ rows: [GraphRow]) {
        state = GraphState(fromRows: rows)
        history = History()
        selected = nil
        tool = .move
    }

    private func set(_ next: GraphState) {
        guard next != state else { return }
        state = next
        onChange?()
    }

    /// Replaces the rows as one undo step.
    func commit(_ next: GraphState) {
        guard next != state else { return }
        history.record(state)
        set(next)
    }

    func undo() {
        focused = nil
        if let previous = history.undo(from: state) { set(previous) }
        dropStale()
    }

    func redo() {
        focused = nil
        if let next = history.redo(from: state) { set(next) }
        dropStale()
    }

    private func dropStale() {
        if let selected, !rows.contains(where: { $0.id == selected }) { self.selected = nil }
    }

    /// Typing into a row: the first change since it got the focus is the undo step; a new row at the bottom is made.
    func type(_ text: String, in id: String) {
        if id == newId {
            guard !text.isEmpty else { return }
            commit(state.adding(text))
            edited = true
            return
        }
        if !edited { history.record(state) }
        edited = true
        set(state.updating(id) { $0.text = text })
    }

    func remove(_ id: String) {
        if selected == id { selected = nil }
        commit(state.removing(id))
    }

    func deleteAll() {
        selected = nil
        focused = nil
        commit(GraphState(rows: [], nextId: state.nextId))
    }

    func toggleHidden(_ id: String) {
        commit(state.updating(id) { $0.hidden.toggle() })
    }

    /// Changes a row's style: one undo step, or during a drag (`live`) one step for the whole drag.
    func restyle(_ id: String, live: Bool = false, _ change: (inout GraphRow) -> Void) {
        let next = state.updating(id, change)
        if live {
            if !styleEditing { history.record(state) }
            styleEditing = true
            set(next)
        } else {
            styleEditing = false
            commit(next)
        }
    }

    /// The end of a slider or colour-picker drag.
    func endStyleEdit() {
        styleEditing = false
    }

    func row(_ id: String) -> GraphRow? { rows.first { $0.id == id } }
    func compiledRow(_ id: String) -> CompiledRow? { compiled.first { $0.id == id } }

    /// The number of a row as shown (1, 2, …).
    func number(_ id: String) -> Int { (rows.firstIndex { $0.id == id } ?? -1) + 1 }

    // MARK: View

    func sizeChanged(_ size: CGSize) {
        canvasSize = size
        if viewport == nil, size.width > 0 { home() }
    }

    /// Start view: about −11…11 across the canvas, the origin in the middle.
    func home() {
        guard canvasSize.width > 0 else { return }
        viewport = Viewport(scale: max(20, canvasSize.width / 22), tx: canvasSize.width / 2, ty: canvasSize.height / 2)
    }

    func pan(dx: Double, dy: Double) {
        viewport?.pan(dx: dx, dy: dy)
    }

    func zoom(at p: CGPoint, factor: Double) {
        viewport?.zoom(at: Vec(x: p.x, y: p.y), factor: factor, range: Self.zoomRange)
    }

    func zoomCentre(_ factor: Double) {
        zoom(at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), factor: factor)
    }

    /// The part of the plane in view.
    func view(_ v: Viewport, _ size: CGSize) -> GraphView {
        let topLeft = v.toWorld(Vec(x: 0, y: 0))
        let bottomRight = v.toWorld(Vec(x: size.width, y: size.height))
        return GraphView(xMin: topLeft.x, xMax: bottomRight.x, yMin: bottomRight.y, yMax: topLeft.y)
    }

    // MARK: What is drawn, worked out once per view

    struct Picture {
        /// Per row (same order as the rows): its lines (a shaded row: each border, strict or not) and its fill.
        var lines: [[(lines: [[Vec]], strict: Bool)]]
        var fills: [[[Vec]]?]
        /// Crossings of the selected graph (grey) and of each kept row (in its colour).
        var marks: [(points: [Vec], color: String?)]
        /// Where each row of kept crossings has its points, by row id.
        var kept: [String: [Vec]]
    }

    private struct PictureKey: Equatable {
        var revision: Int
        var viewport: Viewport
        var size: CGSize
        var selected: String?
    }

    @ObservationIgnored private var cache: (key: PictureKey, picture: Picture)?

    func picture(_ v: Viewport, _ size: CGSize) -> Picture {
        let key = PictureKey(revision: revision, viewport: v, size: size, selected: selected)
        if let cache, cache.key == key { return cache.picture }
        let view = view(v, size)
        let scale = v.scale
        var lines: [[(lines: [[Vec]], strict: Bool)]] = []
        var fills: [[[Vec]]?] = []
        for (row, c) in zip(rows, compiled) {
            guard !row.hidden, c.error == nil else {
                lines.append([])
                fills.append(nil)
                continue
            }
            if let region = c.region {
                lines.append(region.edges.map { (drawnLines($0.drawn, view, scale: scale), $0.strict) })
                fills.append(fillPolygons(region.margin, view, scale: scale))
            } else {
                lines.append([(drawnLines(c.drawn, view, scale: scale), false)])
                fills.append(nil)
            }
        }

        var kept: [String: [Vec]] = [:]
        for r in rows {
            guard let between = r.between, between.count == 2,
                  let a = compiledRow(between[0]), let b = compiledRow(between[1]), a.error == nil, b.error == nil else { continue }
            kept[r.id] = crossingsBetween(a.drawn, b.drawn, view, scale: scale)
        }
        let shown = Set(rows.filter { !$0.hidden && $0.between == nil }.map(\.id))
        var ofSelected: [Vec] = []
        if let selected, let row = row(selected), row.between == nil, !row.hidden, let own = compiledRow(selected), own.error == nil {
            for c in compiled where c.id != selected && shown.contains(c.id) && c.error == nil && c.parsed != nil {
                ofSelected += crossingsBetween(own.drawn, c.drawn, view, scale: scale)
            }
        }
        var marks: [(points: [Vec], color: String?)] = [(ofSelected, nil)]
        for r in rows {
            if let between = r.between, !r.hidden, between.allSatisfy(shown.contains) { marks.append((kept[r.id] ?? [], r.color)) }
        }
        let picture = Picture(lines: lines, fills: fills, marks: marks, kept: kept)
        cache = (key, picture)
        return picture
    }

    /// Marked points whose coordinates are shown: the pinned ones, a selected row of crossings, and the one under the pointer.
    func labelled(_ picture: Picture) -> [Vec] {
        var out = pinned
        if let selected, row(selected)?.between != nil { out += picture.kept[selected] ?? [] }
        if let hoveredMark, !out.contains(where: { samePoint($0, hoveredMark) }) { out.append(hoveredMark) }
        return out
    }

    // MARK: Pointer

    func world(_ p: CGPoint) -> Vec? { viewport?.toWorld(Vec(x: p.x, y: p.y)) }

    /// The marked point nearest the pointer, within reach.
    private func markAt(_ p: CGPoint) -> Vec? {
        guard let v = viewport else { return nil }
        let picture = picture(v, canvasSize)
        var best: Vec?
        var bestDist = Self.markReach
        for q in picture.marks.flatMap(\.points) {
            let s = v.toScreen(q)
            let d = hypot(s.x - p.x, s.y - p.y)
            if d < bestDist { (best, bestDist) = (q, d) }
        }
        return best
    }

    /// The drawn graph nearest the point, within reach; else the shaded area under it (the one drawn last).
    func graphAt(_ p: Vec, _ which: (CompiledRow) -> Bool = { _ in true }) -> String? {
        guard let v = viewport else { return nil }
        let picture = picture(v, canvasSize)
        var best: String?
        var bestDist = Self.pickReach / v.scale
        for (i, c) in compiled.enumerated() where !rows[i].hidden && c.error == nil && which(c) {
            let d = picture.lines[i].map { distanceToLines($0.lines, p) }.min() ?? .infinity
            if d < bestDist { (best, bestDist) = (c.id, d) }
        }
        return best
    }

    /// The shaded area under the point, the one drawn last when they overlap.
    func fillAt(_ p: Vec) -> String? {
        for (i, c) in compiled.enumerated().reversed() where !rows[i].hidden && c.error == nil {
            if let region = c.region, region.margin(p.x, p.y) >= 0 { return c.id }
        }
        return nil
    }

    func hover(_ p: CGPoint?) {
        guard dragLast == nil else { return }
        if tool != .move { return toolHover(p) }
        let mark = p.flatMap(markAt)
        if mark != hoveredMark { hoveredMark = mark }
    }

    func dragChanged(from start: CGPoint, to p: CGPoint) {
        if dragLast == nil {
            dragLast = start
            dragMoved = false
        }
        if hypot(p.x - start.x, p.y - start.y) >= Self.clickSlop { dragMoved = true }
        guard dragMoved, let last = dragLast else { return }
        pan(dx: p.x - last.x, dy: p.y - last.y)
        dragLast = p
    }

    func dragEnded(at p: CGPoint) {
        let moved = dragMoved
        dragLast = nil
        dragMoved = false
        guard !moved else { return }
        click(at: p)
    }

    /// A click: a marked point keeps (or drops) its label, a graph is selected, else nothing is.
    private func click(at p: CGPoint) {
        focused = nil
        if tool != .move { return toolClick(at: p) }
        if let mark = markAt(p) {
            if pinned.contains(where: { samePoint($0, mark) }) { pinned.removeAll { samePoint($0, mark) } } else { pinned.append(mark) }
            return
        }
        selected = world(p).flatMap { graphAt($0) ?? fillAt($0) }
    }

    /// Returns true when the key was used.
    func keyPressed(code: UInt16, editingText: Bool) -> Bool {
        if editingText { return false }
        switch code {
        case DrawingStore.Key.escape:
            if tool != .move {
                tool = .move
                return true
            }
            guard selected != nil else { return false }
            selected = nil
            return true
        case DrawingStore.Key.backspace, DrawingStore.Key.forwardDelete:
            guard let selected else { return false }
            remove(selected)
            return true
        default:
            return false
        }
    }
}

func samePoint(_ p: Vec, _ q: Vec) -> Bool {
    abs(p.x - q.x) < 1e-9 * (1 + abs(p.x)) && abs(p.y - q.y) < 1e-9 * (1 + abs(p.y))
}
