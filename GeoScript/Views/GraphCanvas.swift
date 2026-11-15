import GeoEngine
import SwiftUI

/// The graphs on a pannable, zoomable grid. Clicking a graph selects it and marks where it crosses the others.
struct GraphCanvas: View {
    let store: DrawingStore
    @Environment(\.colorScheme) private var colorScheme

    private var graph: GraphStore { store.graph }

    var body: some View {
        let graph = graph
        // Read here so the canvas redraws when they change.
        let viewport = graph.viewport
        let _ = graph.revision
        let _ = graph.selected
        let hovered = graph.hoveredMark
        let pinned = graph.pinned
        let rows = graph.rows
        let comma = store.usesComma
        let isDark = colorScheme == .dark
        let overlay = graph.overlay()
        let piAxisX = graph.piAxisX

        Canvas { context, size in
            guard let viewport else { return }
            drawGrid(&context, size, viewport, comma: comma, piAxisX: piAxisX)
            let picture = graph.picture(viewport, size)
            func pt(_ p: Vec) -> CGPoint {
                let s = viewport.toScreen(p)
                return CGPoint(x: s.x, y: s.y)
            }
            func path(_ lines: [[Vec]], closed: Bool = false) -> Path {
                var path = Path()
                for l in lines where !l.isEmpty {
                    path.move(to: pt(l[0]))
                    for p in l.dropFirst() { path.addLine(to: pt(p)) }
                    if closed { path.closeSubpath() }
                }
                return path
            }

            // Shading first, then the lines over it.
            for (i, fill) in picture.fills.enumerated() {
                guard let fill, i < rows.count else { continue }
                context.fill(path(fill, closed: true), with: .color(geoColor(rows[i].color, isDark: isDark).opacity(rows[i].fill ?? graphDefaultFill)))
            }
            for (i, pieces) in picture.lines.enumerated() where i < rows.count {
                let row = rows[i]
                let isSelected = row.id == graph.selected
                let w = row.width ?? graphDefaultWidth
                // Without a line (width 0) a graph shows only when selected, thinly.
                if w == 0 && !isSelected { continue }
                let color = geoColor(row.color, isDark: isDark)
                for piece in pieces {
                    let shape = shape(row, piece.lines, graph.compiled[i], viewport, path)
                    if isSelected {
                        // The selected graph: bolder, with a soft halo.
                        context.stroke(shape, with: .color(color.opacity(0.18)), style: StrokeStyle(lineWidth: w + 9.5, lineCap: .round, lineJoin: .round))
                    }
                    context.stroke(shape, with: .color(color), style: stroke(row, strict: piece.strict, width: w + (isSelected ? 1.5 : 0)))
                }
            }

            let background = Color(nsColor: .textBackgroundColor)
            if let overlay {
                drawOverlay(&context, overlay, viewport, size, isDark: isDark, background: background, pt: pt, path: path)
                return
            }

            // Points marked on the graphs, and their coordinates.
            for mark in picture.marks {
                for p in mark.points {
                    let s = pt(p)
                    let dot = Path(ellipseIn: CGRect(x: s.x - 5.5, y: s.y - 5.5, width: 11, height: 11))
                    if let color = mark.color {
                        context.fill(dot, with: .color(geoColor(color, isDark: isDark)))
                    } else {
                        context.fill(dot, with: .color(background))
                        context.stroke(dot, with: .color(.gray), lineWidth: 2)
                    }
                }
            }
            var labelled = pinned
            if let selected = graph.selected, graph.row(selected)?.between != nil { labelled += picture.kept[selected] ?? [] }
            if let hovered, !labelled.contains(where: { samePoint($0, hovered) }) { labelled.append(hovered) }
            for p in labelled {
                let s = pt(p)
                let text = context.resolve(Text(pointText(p, comma: comma)).font(.system(size: 12)).monospacedDigit())
                let textSize = text.measure(in: CGSize(width: 400, height: 40))
                let w = textSize.width + 14
                // Above and to the right of the point, flipped inside the canvas near its edges.
                let x = s.x + 10 + w > size.width ? s.x - 10 - w : s.x + 10
                let y = s.y - 32 < 0 ? s.y + 10 : s.y - 32
                let box = Path(roundedRect: CGRect(x: x, y: y, width: w, height: 22), cornerRadius: 5)
                context.fill(box, with: .color(background.opacity(0.92)))
                context.stroke(box, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                context.draw(text, at: CGPoint(x: x + 7, y: y + 11), anchor: .leading)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            TrackpadCatcher(onPan: { graph.pan(dx: $0, dy: $1) },
                            onZoom: { graph.zoom(at: $0, factor: $1) },
                            onKey: { code, _, editing in graph.keyPressed(code: code, editingText: editing) })
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): graph.hover(location)
            case .ended: graph.hover(nil)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { graph.dragChanged(from: $0.startLocation, to: $0.location) }
                .onEnded { graph.dragEnded(at: $0.location) }
        )
        .onGeometryChange(for: CGSize.self) { $0.size } action: { graph.sizeChanged($0) }
    }

    /// What a tool draws over the graphs: guides, the shaded area, the graphs picked, the preview and the points.
    private func drawOverlay(_ context: inout GraphicsContext, _ o: GraphOverlay, _ v: Viewport, _ size: CGSize, isDark: Bool,
                             background: Color, pt: (Vec) -> CGPoint, path: ([[Vec]], Bool) -> Path) {
        let color = geoColor(o.color, isDark: isDark)
        let topLeft = v.toWorld(Vec(x: 0, y: 0)), bottomRight = v.toWorld(Vec(x: size.width, y: size.height))
        let view = GraphView(xMin: topLeft.x, xMax: bottomRight.x, yMin: bottomRight.y, yMax: topLeft.y)
        func shape(_ d: Drawn) -> Path {
            if let c = d.circle, c.inside == nil {
                let s = pt(Vec(x: c.m, y: c.n))
                let r = c.r * v.scale
                return Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r))
            }
            return path(drawnLines(d, view, scale: v.scale), false)
        }
        var guides = Path()
        for g in o.guides {
            switch g {
            case .x(let x):
                let sx = pt(Vec(x: x, y: 0)).x
                guard sx >= -10 && sx <= size.width + 10 else { continue }
                guides.move(to: CGPoint(x: sx, y: 0))
                guides.addLine(to: CGPoint(x: sx, y: size.height))
            case .y(let y):
                let sy = pt(Vec(x: 0, y: y)).y
                guides.move(to: CGPoint(x: 0, y: sy))
                guides.addLine(to: CGPoint(x: size.width, y: sy))
            case .segment(let a, let b):
                guides.move(to: pt(a))
                guides.addLine(to: pt(b))
            }
        }
        context.stroke(guides, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        if let fill = o.fill {
            context.fill(path(fillPolygons(fill.margin, view, scale: v.scale), true), with: .color(color.opacity(graphDefaultFill)))
        }
        if let faint = o.faint {
            context.stroke(shape(faint), with: .color(color.opacity(0.3)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        for p in o.picked {
            context.stroke(shape(p.drawn), with: .color(geoColor(p.color, isDark: isDark)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        if let preview = o.preview {
            let style = o.cutting ? StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                : StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [8, 6])
            context.stroke(shape(preview), with: .color(color), style: style)
        }
        for c in o.crossings {
            let s = pt(c)
            let dot = Path(ellipseIn: CGRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8))
            context.fill(dot, with: .color(background))
            context.stroke(dot, with: .color(.gray), lineWidth: 1.5)
        }
        for p in o.points {
            let s = pt(p)
            context.fill(Path(ellipseIn: CGRect(x: s.x - 5.5, y: s.y - 5.5, width: 11, height: 11)), with: .color(color))
        }
        if let cursor = o.cursor {
            let s = pt(cursor)
            context.fill(Path(ellipseIn: CGRect(x: s.x - 5, y: s.y - 5, width: 10, height: 10)), with: .color(color.opacity(0.5)))
        }
    }

    /// A whole circle as a circle; everything else as its sampled lines.
    private func shape(_ row: GraphRow, _ lines: [[Vec]], _ c: CompiledRow, _ v: Viewport, _ path: ([[Vec]], Bool) -> Path) -> Path {
        if let circle = c.circle, circle.inside == nil {
            let s = v.toScreen(Vec(x: circle.m, y: circle.n))
            let r = circle.r * v.scale
            return Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r))
        }
        return path(lines, false)
    }

    /// A row's line: its width and dashes (scaled to the width; a strict inequality's border is dashed).
    private func stroke(_ row: GraphRow, strict: Bool, width w: Double) -> StrokeStyle {
        let dash = row.dash ?? (strict ? .dashed : nil)
        let u = max(w, 1.5)
        switch dash {
        case .dashed: return StrokeStyle(lineWidth: w, lineCap: .butt, lineJoin: .round, dash: [u * 3.2, u * 2.2])
        case .dotted: return StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: [0, u * 2.2])
        case nil: return StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        }
    }

    // MARK: Grid

    /// Major grid step: 1, 2 or 5 × 10ⁿ units, at least ~90 px apart; and the minor step.
    static func gridStep(_ scale: Double) -> (major: Double, minor: Double) {
        let raw = 90 / scale
        let p = pow(10, (log10(raw)).rounded(.down))
        let m = [1.0, 2, 5, 10].first { $0 * p >= raw * 0.999 } ?? 10
        let major = m * p
        return (major, major / (m == 2 ? 4 : 5))
    }

    /// `piAxisX`: the x-axis (true) or the y-axis (false) is marked in multiples of π.
    private func drawGrid(_ context: inout GraphicsContext, _ size: CGSize, _ v: Viewport, comma: Bool, piAxisX: Bool?) {
        let usual = Self.gridStep(v.scale)
        let pi = piGridStep(v.scale)
        let xStep = piAxisX == true ? pi : usual
        let yStep = piAxisX == false ? pi : usual
        let topLeft = v.toWorld(Vec(x: 0, y: 0))
        let bottomRight = v.toWorld(Vec(x: size.width, y: size.height))
        /// Multiples of `step` inside [from, to], counted from 0 so they never drift.
        func ticks(_ from: Double, _ to: Double, _ step: Double) -> [Double] {
            var out: [Double] = []
            var i = (from / step).rounded(.up)
            while i * step <= to && out.count < 2000 {
                out.append(i * step)
                i += 1
            }
            return out
        }
        func px(_ v: Double) -> Double { v.rounded() + 0.5 }
        func lines(_ sx: Double, _ sy: Double) -> Path {
            var path = Path()
            for x in ticks(topLeft.x, bottomRight.x, sx) {
                let sx = px(v.toScreen(Vec(x: x, y: 0)).x)
                path.move(to: CGPoint(x: sx, y: 0))
                path.addLine(to: CGPoint(x: sx, y: size.height))
            }
            for y in ticks(bottomRight.y, topLeft.y, sy) {
                let sy = px(v.toScreen(Vec(x: 0, y: y)).y)
                path.move(to: CGPoint(x: 0, y: sy))
                path.addLine(to: CGPoint(x: size.width, y: sy))
            }
            return path
        }
        context.stroke(lines(xStep.minor, yStep.minor), with: .color(.secondary.opacity(0.10)), lineWidth: 1)
        context.stroke(lines(xStep.major, yStep.major), with: .color(.secondary.opacity(0.28)), lineWidth: 1)

        let origin = v.toScreen(Vec(x: 0, y: 0))
        var axes = Path()
        axes.move(to: CGPoint(x: origin.x, y: 0))
        axes.addLine(to: CGPoint(x: origin.x, y: size.height))
        axes.move(to: CGPoint(x: 0, y: origin.y))
        axes.addLine(to: CGPoint(x: size.width, y: origin.y))
        context.stroke(axes, with: .color(.primary.opacity(0.75)), lineWidth: 1.4)

        // Numbers on the axes; when an axis is off screen its numbers stay at the nearest edge.
        /// A number on an axis: 2, 0,5, or π/2, 3π on the π axis.
        func label(_ value: Double, pi: Bool, major: Double) -> Text {
            if pi { return Text(piLabel(value)).font(.system(size: 11)).foregroundStyle(.secondary) }
            let decimals = max(0, -Int((log10(major) + 1e-9).rounded(.down)))
            var s = String(format: "%.\(decimals)f", value).replacingOccurrences(of: "-", with: "−")
            if comma { s = s.replacingOccurrences(of: ".", with: ",") }
            return Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        func near0(_ value: Double, _ major: Double) -> Bool { abs(value) < major / 2 }
        let xLabelY = min(max(origin.y + 6, 6), size.height - 22)
        let leftAxis = origin.x < 40
        let yLabelX = leftAxis ? max(origin.x + 6, 6) : min(origin.x - 6, size.width - 6)
        for x in ticks(topLeft.x, bottomRight.x, xStep.major) where !near0(x, xStep.major) {
            context.draw(label(x, pi: piAxisX == true, major: xStep.major), at: CGPoint(x: v.toScreen(Vec(x: x, y: 0)).x, y: xLabelY), anchor: .top)
        }
        for y in ticks(bottomRight.y, topLeft.y, yStep.major) where !near0(y, yStep.major) {
            context.draw(label(y, pi: piAxisX == false, major: yStep.major), at: CGPoint(x: yLabelX, y: v.toScreen(Vec(x: 0, y: y)).y), anchor: leftAxis ? .leading : .trailing)
        }
        if origin.x > 0 && origin.x < size.width && origin.y > 0 && origin.y < size.height {
            context.draw(Text("0").font(.system(size: 11)).foregroundStyle(.secondary), at: CGPoint(x: origin.x - 6, y: origin.y + 6), anchor: .topTrailing)
        }
    }
}
