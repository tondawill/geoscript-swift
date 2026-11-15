import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case move, point, segment, line, ray, perp, parallel, angle, circle

    var id: String { rawValue }

}

/// Draws the same 28×28 icons as the web toolbar.
struct ToolIcon: View {
    let tool: Tool

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 28
            context.scaleBy(x: scale, y: scale)
            let color = GraphicsContext.Shading.foreground
            let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)

            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))
                context.stroke(path, with: color, style: stroke)
            }
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: color)
            }

            switch tool {
            case .move:
                var path = Path()
                path.addLines([(8, 4), (8, 22), (12.5, 17.5), (15.5, 24), (18, 23), (15, 16.5), (21, 16.5)]
                    .map { CGPoint(x: $0.0, y: $0.1) })
                path.closeSubpath()
                context.fill(path, with: color)
            case .point:
                dot(14, 16, 4)
                context.draw(Text("A").font(.system(size: 9, weight: .semibold)), at: CGPoint(x: 21, y: 8))
            case .segment:
                line(6, 22, 22, 8); dot(6, 22, 2.6); dot(22, 8, 2.6)
            case .line:
                line(2, 23, 26, 6); dot(9, 18, 2.4); dot(19, 11, 2.4)
            case .ray:
                line(6, 22, 26, 8); dot(6, 22, 2.8); dot(16, 15, 2.2)
            case .perp:
                line(3, 22, 25, 22); line(11, 4, 11, 22); line(11, 17, 16, 17); line(16, 17, 16, 22)
            case .parallel:
                line(3, 11, 24, 6); line(4, 23, 25, 18)
            case .angle:
                line(4, 22, 25, 22); line(4, 22, 20, 6)
                var arc = Path()
                arc.addArc(center: CGPoint(x: 4, y: 22), radius: 9,
                           startAngle: .degrees(0), endAngle: .degrees(-45), clockwise: true)
                context.stroke(arc, with: color, lineWidth: 1.4)
            case .circle:
                context.stroke(Path(ellipseIn: CGRect(x: 5, y: 6, width: 18, height: 18)), with: color, style: stroke)
                dot(14, 15, 2.4)
            }
        }
        .frame(width: 22, height: 22)
    }
}
