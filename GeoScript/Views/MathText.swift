import GeoEngine
import SwiftUI

/// A piece of a typeset row: text (with italics and superscripts), or a fraction stacked like on paper.
indirect enum MathPiece {
    case text(Text)
    case frac([MathPiece], [MathPiece])
}

/// A parsed row typeset the way it's written on paper: y = x² + 2x + 3, f(x) = sin x, √(x + 1).
/// Brackets appear only where the order of operations needs them. A port of the web's MathText.tsx.
struct MathBuilder {
    let comma: Bool

    /// Long decimals (a line through where graphs cross) are cut to two digits after any zeros: 7,10…, 0,0040…
    private func number(_ v: Double) -> String {
        let s = jsString(v).replacing(#/(\.0*[1-9][0-9])[0-9]+$/#) { match in "\(match.1)…" }
        return comma ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    private func t(_ s: String) -> [MathPiece] { [.text(Text(s))] }
    private func italic(_ s: String) -> [MathPiece] { [.text(Text(s).italic())] }
    /// = + − · with a little room on both sides.
    private func op(_ s: String) -> [MathPiece] { t(" \(s) ") }
    private func paren(_ inner: [MathPiece]) -> [MathPiece] { t("(") + inner + t(")") }

    /// An argument that needs no brackets after a function name: sin x, √2.
    private func simple(_ e: Expr) -> Bool {
        switch e {
        case .num, .x, .pi, .e: return true
        default: return false
        }
    }

    /// Does the expression, written out, start with a digit? (Then 2 · 3 needs its dot.)
    private func startsWithDigit(_ e: Expr) -> Bool {
        switch e {
        case .num: return true
        case .bin(let op, let a, _) where op == .pow || op == .mul || op == .div: return startsWithDigit(a)
        default: return false
        }
    }

    /// Strength of the outermost operation: + − 1, · / 2, unary minus 3, ^ 4, atoms 5.
    private func prec(_ e: Expr) -> Int {
        switch e {
        case .bin(let op, _, _):
            switch op {
            case .add, .sub: return 1
            case .mul, .div: return 2
            case .pow: return 4
            }
        case .neg: return 3
        case .num(let v) where v < 0: return 3
        default: return 5
        }
    }

    private func show(_ e: Expr, _ min: Int = 0) -> [MathPiece] {
        prec(e) < min ? paren(body(e)) : body(e)
    }

    private func fnName(_ f: BuiltIn) -> String { f.rawValue }

    /// sin x, sin(2x), √2, |x|; `brackets`: always sin(x), when something follows.
    private func fnCall(_ f: BuiltIn, _ a: Expr, brackets: Bool = false) -> [MathPiece] {
        switch f {
        case .abs: return t("|") + show(a) + t("|")
        case .sqrt: return t("√") + (simple(a) ? show(a) : paren(show(a)))
        default: return t(fnName(f)) + (simple(a) && !brackets ? t(" ") + show(a) : paren(show(a)))
        }
    }

    private func named(_ e: Expr) -> Bool {
        if case .fn(let f, _) = e { return f != .abs && f != .sqrt }
        return false
    }

    private func body(_ e: Expr) -> [MathPiece] {
        switch e {
        case .num(let v): return t(number(v))
        case .x: return italic("x")
        case .y: return italic("y")
        case .pi: return t("π")
        case .e: return italic("e")
        case .neg(let a): return t("−") + show(a, 3)
        case .call(let name, let a): return italic(name) + paren(show(a))
        case .fn(let f, let a): return fnCall(f, a)
        case .bin(let op, let a, let b):
            switch op {
            case .add: return show(a, 1) + self.op("+") + show(b, 2)
            case .sub: return show(a, 1) + self.op("−") + show(b, 2)
            case .div:
                // Stacked; a minus in front of the numerator goes in front of the bar.
                if case .neg(let inner) = a { return t("−") + [.frac(show(inner), show(b))] }
                return [.frac(show(a), show(b))]
            case .pow:
                // (√5)², not √5²: a function under a power keeps its brackets.
                var base: [MathPiece]
                if case .fn(let f, _) = a, f != .abs { base = paren(show(a)) } else { base = show(a, 5) }
                return base + [.text(flat(show(b)).font(.system(size: 10)).baselineOffset(7))]
            case .mul:
                // 2x, 3(x + 1), x sin x, sin x cos x; but 2 · 3 keeps its dot and sin(x)·x its brackets.
                var left: [MathPiece]
                if named(a) && !named(b), case .fn(let f, let arg) = a { left = fnCall(f, arg, brackets: true) } else { left = show(a, 2) }
                var neg = false
                if case .neg = b { neg = true }
                let sep: [MathPiece] = startsWithDigit(b) || neg ? self.op("·") : named(b) ? t(" ") : []
                return left + sep + show(b, 2)
            }
        }
    }

    /// Pieces as one line of text (a fraction in an exponent as a/b).
    private func flat(_ pieces: [MathPiece]) -> Text {
        pieces.reduce(Text("")) { result, piece in
            switch piece {
            case .text(let text): return result + text
            case .frac(let top, let bottom): return result + flat(top) + Text("/") + flat(bottom)
            }
        }
    }

    private func chain(_ r: Restriction) -> [MathPiece] {
        r.terms.enumerated().flatMap { j, term in (j > 0 ? op(r.ops[j - 1].rawValue) : []) + show(term) }
    }

    func pieces(_ row: ParsedRow) -> [MathPiece] {
        var out: [MathPiece]
        switch row.kind {
        case .circle(let lhs, let rhs, _, _), .curve(let lhs, let rhs): out = show(lhs) + op("=") + show(rhs)
        case .region(let r): out = chain(r)
        case .def(let name, let e): out = italic(name) + t("(") + italic("x") + t(")") + op("=") + show(e)
        case .x(let e): out = italic("x") + op("=") + show(e)
        case .y(let e, let bare): out = (bare ? [] : italic("y") + op("=")) + show(e)
        }
        for r in row.restrictions { out += t(" {") + chain(r) + t("}") }
        return out
    }
}

/// Draws typeset pieces: runs of text in one line, fractions stacked.
struct MathView: View {
    let pieces: [MathPiece]
    var size: CGFloat = 14

    /// Adjacent text joined into one run.
    private var runs: [MathPiece] {
        var out: [MathPiece] = []
        for p in pieces {
            if case .text(let next) = p, case .text(let last)? = out.last {
                out[out.count - 1] = .text(last + next)
            } else {
                out.append(p)
            }
        }
        return out
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .text(let text):
                    text.font(.system(size: size))
                case .frac(let top, let bottom):
                    VStack(spacing: 1) {
                        MathView(pieces: top, size: size * 0.85)
                        Rectangle().frame(height: 1)
                        MathView(pieces: bottom, size: size * 0.85)
                    }
                    .fixedSize()
                    .padding(.horizontal, 1)
                }
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }
}
