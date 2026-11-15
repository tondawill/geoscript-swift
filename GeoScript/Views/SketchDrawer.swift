import GeoEngine
import SwiftUI

/// A scratch area saved with the drawing. It is not geometry.
struct SketchDrawer: View {
    let store: DrawingStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var tool = "pen"
    @State private var color = "ink"
    @State private var current: [Double] = []

    private static let penWidth = 2.5
    private static let eraserWidth = 18.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.t("sketch.title")).font(.title3.bold())
                Spacer()
                Button(store.t("sketch.close"), systemImage: "xmark") { store.showSketch = false }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            HStack {
                Picker(store.t("sketch.title"), selection: $tool) {
                    Label(store.t("sketch.pen"), systemImage: "pencil").tag("pen")
                    Label(store.t("sketch.eraser"), systemImage: "eraser").tag("eraser")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Spacer()
                Button(store.t("sketch.clear")) { store.clearSketch() }
            }
            HStack(spacing: 10) {
                ForEach(["ink", "red", "blue"], id: \.self) { name in
                    Button {
                        color = name
                        tool = "pen"
                    } label: {
                        Circle()
                            .fill(strokeColor(name))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: color == name && tool == "pen" ? 2.5 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            Canvas(opaque: false) { context, _ in
                for stroke in store.sketch {
                    draw(stroke, &context)
                }
                if !current.isEmpty {
                    draw(SketchStroke(tool: tool, color: color, pts: current), &context)
                }
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in current += [value.location.x, value.location.y] }
                    .onEnded { _ in
                        store.addSketchStroke(SketchStroke(tool: tool, color: color, pts: current))
                        current = []
                    }
            )
            Text(store.t("sketch.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private func strokeColor(_ name: String) -> Color {
        name == "ink" ? .primary : geoColor(name, isDark: colorScheme == .dark)
    }

    private func draw(_ stroke: SketchStroke, _ context: inout GraphicsContext) {
        var path = Path()
        var i = 0
        while i + 1 < stroke.pts.count {
            let p = CGPoint(x: stroke.pts[i], y: stroke.pts[i + 1])
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            i += 2
        }
        let eraser = stroke.tool == "eraser"
        var layer = context
        layer.blendMode = eraser ? .destinationOut : .normal
        layer.stroke(path, with: .color(eraser ? .black : strokeColor(stroke.color)),
                     style: StrokeStyle(lineWidth: eraser ? Self.eraserWidth : Self.penWidth, lineCap: .round, lineJoin: .round))
    }
}
