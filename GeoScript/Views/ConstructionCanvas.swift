import GeoEngine
import SwiftUI

/// Draws the construction and turns pointer input into store actions.
struct ConstructionCanvas: View {
    let store: DrawingStore
    @Environment(\.colorScheme) private var colorScheme

    private static let pointRadius = 4.5

    var body: some View {
        let construction = store.construction
        let viewport = store.viewport
        let progress = store.progress
        let showGrid = store.showGrid
        let clean = store.clean
        let showPoints = !clean || store.cleanPoints
        let labels = clean ? [] : store.dimensionLabels
        let marks = clean ? [] : store.relationMarks
        let selection = store.selection
        let isDark = colorScheme == .dark

        Canvas { context, size in
            guard let viewport else { return }
            if showGrid { drawGrid(&context, size, viewport) }

            let positions = construction.resolve()
            let reach = (size.width + size.height) * 2

            func shading(_ id: Id) -> Color {
                progress.highlighted.contains(id) ? .accentColor : geoColor(construction.styleOf(id).color, isDark: isDark)
            }

            for object in construction.objects where object.isCurve {
                guard let geom = curveGeom(object, positions) else { continue }
                let style = construction.styleOf(object.id)
                let exercise = construction.isExercise(object.id)
                let width = exercise ? 3.6 : (progress.highlighted.contains(object.id) ? 2.4 : 1.6)
                let stroke = StrokeStyle(lineWidth: width, dash: style.dashed ? [7, 5] : [])
                let color = shading(object.id).opacity(style.opacity)
                let name = clean ? "" : (object.name ?? "")
                switch geom {
                case let .straight(a, b, ext):
                    let sa = screenPoint(a, viewport), sb = screenPoint(b, viewport)
                    let ends = extent(sa, sb, shape(ext), reach)
                    context.stroke(line(ends.0, ends.1), with: .color(color), style: stroke)
                    if !name.isEmpty { drawLowerName(&context, name, near: sa, sb, color, bold: exercise) }
                case let .circle(center, radius):
                    let c = screenPoint(center, viewport)
                    let r = radius * viewport.scale
                    context.stroke(circle(c, r), with: .color(color), style: stroke)
                    if !name.isEmpty {
                        context.draw(Text(name).italic().fontWeight(exercise ? .bold : .regular).font(.system(size: 15)).foregroundStyle(color),
                                     at: CGPoint(x: c.x + (r + 10) * 0.71, y: c.y - (r + 10) * 0.71))
                    }
                }
            }

            for mark in marks { draw(mark, &context, shading) }

            for label in labels {
                if let radius = label.radiusLine {
                    context.stroke(line(radius.0, radius.1), with: .color(.secondary), lineWidth: 1)
                }
                let color: Color = progress.highlighted.contains(label.id) ? .accentColor : .secondary
                context.draw(Text(label.text).font(.system(size: 13)).foregroundStyle(color), at: label.position)
            }

            drawPreview(&context, progress, viewport, reach)

            if showPoints {
                for object in construction.objects where object.isPoint && !object.isHidden {
                    guard let world = positions[object.id] else { continue }
                    let style = construction.styleOf(object.id)
                    let exercise = construction.isExercise(object.id)
                    let p = screenPoint(world, viewport)
                    if object.id == selection {
                        context.fill(circle(p, Self.pointRadius + 5), with: .color(.accentColor.opacity(0.3)))
                    }
                    let color = shading(object.id).opacity(style.opacity)
                    context.fill(circle(p, exercise ? Self.pointRadius + 1.5 : Self.pointRadius), with: .color(color))
                    if !clean {
                        context.draw(Text(object.name ?? "").font(.system(size: 15, weight: exercise ? .bold : .medium)).foregroundStyle(color),
                                     at: CGPoint(x: p.x + 12, y: p.y - 13))
                    }
                }
            }

            for ghost in progress.ghosts {
                let p = screenPoint(ghost.pos, viewport)
                context.fill(circle(p, Self.pointRadius), with: .color(.accentColor.opacity(0.55)))
                if ghost.snapped {
                    context.stroke(circle(p, Self.pointRadius + 6), with: .color(.accentColor), lineWidth: 1.5)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            TrackpadCatcher(onPan: { store.pan(dx: $0, dy: $1) },
                            onZoom: { store.zoom(at: $0, factor: $1) },
                            onKey: { store.keyPressed(code: $0, characters: $1, editingText: $2) })
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): store.hover = location
            case .ended: store.hover = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { store.dragChanged(from: $0.startLocation, to: $0.location) }
                .onEnded { store.dragEnded(at: $0.location) }
        )
        .overlay { FloatingInputLayer(store: store, live: progress.live) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { store.sizeChanged($0) }
    }

    private func shape(_ ext: Extent) -> LineShape {
        switch ext {
        case .segment: .segment
        case .ray: .ray
        case .line: .line
        }
    }

    private func screenPoint(_ world: Vec, _ viewport: Viewport) -> CGPoint {
        let s = viewport.toScreen(world)
        return CGPoint(x: s.x, y: s.y)
    }

    private func circle(_ center: CGPoint, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    /// The drawn ends of a straight object: rays and lines reach past the edge of the canvas.
    private func extent(_ a: CGPoint, _ b: CGPoint, _ shape: LineShape, _ reach: Double) -> (CGPoint, CGPoint) {
        if shape == .segment { return (a, b) }
        let length = max(hypot(b.x - a.x, b.y - a.y), .leastNonzeroMagnitude)
        let ux = (b.x - a.x) / length
        let uy = (b.y - a.y) / length
        let end = CGPoint(x: a.x + ux * reach, y: a.y + uy * reach)
        return shape == .ray ? (a, end) : (CGPoint(x: a.x - ux * reach, y: a.y - uy * reach), end)
    }

    /// Lowercase names sit beside the middle of the object, on its upper side.
    private func drawLowerName(_ context: inout GraphicsContext, _ name: String, near a: CGPoint, _ b: CGPoint, _ color: Color, bold: Bool) {
        let length = max(hypot(b.x - a.x, b.y - a.y), 1)
        var nx = -(b.y - a.y) / length
        var ny = (b.x - a.x) / length
        if ny > 0 { nx = -nx; ny = -ny }
        context.draw(Text(name).italic().fontWeight(bold ? .bold : .regular).font(.system(size: 15)).foregroundStyle(color),
                     at: CGPoint(x: (a.x + b.x) / 2 + nx * 12, y: (a.y + b.y) / 2 + ny * 12))
    }

    /// Arc around `at`, from direction u to direction v, the smaller way round.
    private func arc(_ at: CGPoint, _ u: CGVector, _ v: CGVector, radius: Double) -> Path {
        let start = atan2(u.dy, u.dx)
        let delta = atan2(sin(atan2(v.dy, v.dx) - start), cos(atan2(v.dy, v.dx) - start))
        var path = Path()
        for i in 0...24 {
            let angle = start + delta * Double(i) / 24
            let p = CGPoint(x: at.x + radius * cos(angle), y: at.y + radius * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private func draw(_ mark: RelationMark, _ context: inout GraphicsContext, _ shading: (Id) -> Color) {
        switch mark {
        case let .rightAngle(at, u, v, id):
            drawRightAngle(&context, at, u, v, shading(id))
        case let .ticks(at, dir, count, id):
            context.stroke(ticks(at, dir, count), with: .color(shading(id)), lineWidth: 1.4)
        case let .arc(at, u, v, id):
            context.stroke(arc(at, u, v, radius: 24), with: .color(shading(id)), lineWidth: 1.2)
        case let .perpendicularSign(at, id):
            context.draw(Text("⊥").font(.system(size: 13)).foregroundStyle(shading(id)), at: at)
        }
    }

    /// Czech right-angle mark: a quarter arc with a dot in the middle.
    private func drawRightAngle(_ context: inout GraphicsContext, _ at: CGPoint, _ u: CGVector, _ v: CGVector, _ color: Color) {
        let radius = 15.0
        context.stroke(arc(at, u, v, radius: radius), with: .color(color), lineWidth: 1.2)
        let length = max(hypot(u.dx + v.dx, u.dy + v.dy), 1e-9)
        let dot = CGPoint(x: at.x + radius * 0.55 * (u.dx + v.dx) / length, y: at.y + radius * 0.55 * (u.dy + v.dy) / length)
        context.fill(circle(dot, 1.8), with: .color(color))
    }

    /// `count` small arrow ticks (›) across a line, pointing along `dir`.
    private func ticks(_ at: CGPoint, _ dir: CGVector, _ count: Int) -> Path {
        var path = Path()
        for i in 0..<count {
            let shift = (Double(i) - Double(count - 1) / 2) * 6
            let c = CGPoint(x: at.x + dir.dx * shift, y: at.y + dir.dy * shift)
            func p(_ a: Double, _ b: Double) -> CGPoint {
                CGPoint(x: c.x + dir.dx * a - dir.dy * b, y: c.y + dir.dy * a + dir.dx * b)
            }
            path.move(to: p(-2.5, -4.5))
            path.addLine(to: p(2.5, 0))
            path.addLine(to: p(-2.5, 4.5))
        }
        return path
    }

    private func drawPreview(_ context: inout GraphicsContext, _ progress: DrawProgress, _ viewport: Viewport, _ reach: Double) {
        let style = StrokeStyle(lineWidth: 1.5, dash: [5, 4])
        let color = GraphicsContext.Shading.color(.accentColor)
        if let straight = progress.straight {
            let ends = extent(screenPoint(straight.from, viewport), screenPoint(straight.to, viewport), straight.shape, reach)
            context.stroke(line(ends.0, ends.1), with: color, style: style)
        }
        if let c = progress.circle {
            context.stroke(circle(screenPoint(c.center, viewport), c.radius * viewport.scale), with: color, style: style)
        }
        for geom in progress.result {
            switch geom {
            case let .straight(a, b, ext):
                let ends = extent(screenPoint(a, viewport), screenPoint(b, viewport), shape(ext), reach)
                context.stroke(line(ends.0, ends.1), with: .color(.accentColor.opacity(0.6)), style: style)
            case let .circle(center, radius):
                context.stroke(circle(screenPoint(center, viewport), radius * viewport.scale), with: .color(.accentColor.opacity(0.6)), style: style)
            }
        }
        if let arc = progress.angleArc {
            let at = screenPoint(arc.at, viewport)
            // Screen y points down, so the counter-clockwise world arc runs clockwise on screen.
            let path = self.arc(at, screenDirection(arc.from), screenDirection(arc.from + arc.size), radius: 28)
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        if let mark = progress.directionMark, !store.clean {
            let at = screenPoint(mark.at, viewport)
            let accent = Color.accentColor
            if mark.kind == .perpendicular {
                if mark.touching {
                    drawRightAngle(&context, at, screenDirection(mark.refDir), screenDirection(mark.newDir), accent)
                } else {
                    context.draw(Text("⊥").font(.system(size: 13)).foregroundStyle(accent), at: CGPoint(x: at.x + 14, y: at.y - 14))
                }
            } else {
                context.stroke(ticks(screenPoint(mark.refMid, viewport), screenDirection(mark.refDir), 1), with: color, lineWidth: 1.4)
                context.stroke(ticks(at, screenDirection(mark.newDir), 1), with: color, lineWidth: 1.4)
            }
        }
    }

    /// Grid spacing is 1, 2 or 5 × a power of ten cm, the smallest that stays at least 24 px apart.
    private func gridStep(scale: Double) -> Double {
        var magnitude = 0.01
        while true {
            for factor in [1.0, 2.0, 5.0] where factor * magnitude * scale >= 24 {
                return factor * magnitude * scale
            }
            magnitude *= 10
        }
    }

    private func drawGrid(_ context: inout GraphicsContext, _ size: CGSize, _ viewport: Viewport) {
        let step = gridStep(scale: viewport.scale)
        var grid = Path()
        var x = viewport.tx.truncatingRemainder(dividingBy: step)
        if x < 0 { x += step }
        while x < size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y = viewport.ty.truncatingRemainder(dividingBy: step)
        if y < 0 { y += step }
        while y < size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
    }
}

/// An object's colour: a palette name (with a dark-mode variant), "#rrggbb", or the default ink.
func geoColor(_ name: String?, isDark: Bool) -> Color {
    guard let name else { return .primary }
    let palette: [String: (light: UInt32, dark: UInt32)] = [
        "red": (0xC74440, 0xEF6B66), "blue": (0x3358C4, 0x7F9CF0), "green": (0x2E8B57, 0x5CC28A),
        "orange": (0xD9822B, 0xF0A050), "purple": (0x7B4FB8, 0xA885E0), "pink": (0xC2418A, 0xE070B0), "gray": (0x8A8A90, 0x9A9AA2),
    ]
    var value: UInt32
    if let entry = palette[name] {
        value = isDark ? entry.dark : entry.light
    } else if name.hasPrefix("#"), let parsed = UInt32(name.dropFirst(), radix: 16) {
        value = parsed
    } else {
        return .primary
    }
    let blue = Double(value & 0xFF) / 255
    value >>= 8
    let green = Double(value & 0xFF) / 255
    value >>= 8
    let red = Double(value & 0xFF) / 255
    // A custom colour too dark to see on the dark canvas: the same hue, its lightness flipped.
    if isDark && palette[name] == nil && luminance(red, green, blue) < 0.12 {
        let (r, g, b) = flipLightness(red, green, blue)
        return Color(.sRGB, red: r, green: g, blue: b)
    }
    return Color(.sRGB, red: red, green: green, blue: blue)
}

/// Relative luminance of an sRGB colour (0 black … 1 white).
private func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

/// The colour with its HSL lightness L turned into 1 − L: hue and saturation stay.
private func flipLightness(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let hi = max(r, g, b), lo = min(r, g, b)
    let l = (hi + lo) / 2
    let flipped = 1 - l
    guard hi > lo else { return (flipped, flipped, flipped) }
    // Each channel keeps its place between the lightest and darkest, scaled to the new lightness.
    let chroma = hi - lo
    let s = chroma / (1 - abs(2 * l - 1))
    let newChroma = (1 - abs(2 * flipped - 1)) * s
    let newLo = flipped - newChroma / 2
    func map(_ c: Double) -> Double { min(1, max(0, newLo + (c - lo) / chroma * newChroma)) }
    return (map(r), map(g), map(b))
}
