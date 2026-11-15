import SwiftUI

/// Small picture of each kind of function.
struct FamilyIcon: View {
    let name: String

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var path = Path()
            func plot(_ f: (Double) -> Double) {
                for i in 0...30 {
                    let x = Double(i) / 30
                    let p = CGPoint(x: x * w, y: h - f(x) * h)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
            switch name {
            case "Restrict":
                // The whole graph faint, the piece kept between the two ends solid.
                var whole = Path()
                for i in 0...30 {
                    let x = Double(i) / 30
                    let y: Double = 0.1 + 2.72 * x * (1 - x)
                    let p = CGPoint(x: x * w, y: h - y * h)
                    if i == 0 { whole.move(to: p) } else { whole.addLine(to: p) }
                }
                context.stroke(whole, with: .foreground, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                for i in 9...21 {
                    let x = Double(i) / 30
                    let y: Double = 0.1 + 2.72 * x * (1 - x)
                    let p = CGPoint(x: x * w, y: h - y * h)
                    if i == 9 { path.move(to: p) } else { path.addLine(to: p) }
                }
            case "Intersect":
                plot { 0.9 - 3.2 * pow($0 - 0.5, 2) }
                path.move(to: CGPoint(x: 0, y: h * 0.85))
                path.addLine(to: CGPoint(x: w, y: h * 0.2))
            case "Fill":
                var area = Path()
                for i in 4...26 {
                    let x = Double(i) / 30
                    let y: Double = 0.05 + 3.2 * (x - 0.5) * (x - 0.5)
                    let p = CGPoint(x: x * w, y: h - y * h)
                    if i == 4 { area.move(to: p) } else { area.addLine(to: p) }
                }
                area.closeSubpath()
                var faded = context
                faded.opacity = 0.35
                faded.fill(area, with: .foreground)
                plot { x in 0.05 + 3.2 * (x - 0.5) * (x - 0.5) }
                path.move(to: CGPoint(x: 0, y: h * 0.25))
                path.addLine(to: CGPoint(x: w, y: h * 0.25))
            case "Linear": plot { 0.1 + 0.8 * $0 }
            case "Parabola": plot { 0.9 - 3.2 * pow($0 - 0.5, 2) }
            case "Cubic": plot { 0.5 + 3 * pow($0 - 0.5, 3) + 0.3 * ($0 - 0.5) }
            case "Trig": plot { 0.5 + 0.4 * sin($0 * 2 * .pi) }
            case "Hyperbola":
                for i in 0...14 {
                    let x = 0.53 + Double(i) / 30
                    let p = CGPoint(x: x * w, y: h - (0.5 + 0.03 / (x - 0.5)) * h)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                for i in 0...14 {
                    let x = 0.03 + Double(i) / 30
                    let p = CGPoint(x: x * w, y: h - (0.5 + 0.03 / (x - 0.5)) * h)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            case "Circle": path.addEllipse(in: CGRect(x: w / 2 - h * 0.42, y: h * 0.08, width: h * 0.84, height: h * 0.84))
            default: path.addEllipse(in: CGRect(x: w * 0.1, y: h * 0.22, width: w * 0.8, height: h * 0.56))
            }
            context.stroke(path, with: .foreground, lineWidth: 1.6)
        }
    }
}
