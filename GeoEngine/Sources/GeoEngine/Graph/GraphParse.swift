import Foundation

// Reads what is typed into a row of the graphing calculator, the way it is written in school:
// `y = 2x`, `x^2 + 2x + 3`, `f(x) = sin x`, `y = 2f(x) − 3`, `√(x + 1)`, `|x|`, `3,5x`.
// Multiplication may be left out (2x, 3(x + 1), x sin x), `^` is right-associative and −x² = −(x²).
// Also `x = 2y + 1` (sideways), other equations in x and y (`x^2/4 + y^2 = 1`), inequalities that
// shade (`y ≤ x^2`, `-1 ≤ y ≤ 2`) and restrictions at the end like in Desmos: `y = x^2 {0 ≤ x ≤ 3}`.
// A port of the web app's src/engine/graph/parse.ts.

/// Words that are split out of a run of letters, longest first ("xsinx" → x sin x).
private let words = ["sqrt", "sin", "cos", "tan", "abs", "exp", "log", "ln", "pi"]
/// Letters that can't name a function.
let reservedNames: Set<String> = ["x", "y", "e"]
/// Comparison signs as typed: <= and ⩽ are ≤.
private let compareSigns: [(String, Compare)] = [("<=", .le), (">=", .ge), ("≤", .le), ("≥", .ge), ("⩽", .le), ("⩾", .ge), ("<", .lt), (">", .gt)]

private enum Tok: Equatable {
    case num(Double)
    case name(String)
    case op(String)

    var compare: Compare? {
        if case .op(let v) = self { return Compare(rawValue: v) }
        return nil
    }
}

private func isDigit(_ c: Character?) -> Bool { c.map { $0.isASCII && $0.isNumber } ?? false }
private func isLetter(_ c: Character) -> Bool { c.isASCII && c.isLetter }

private func tokenize(_ src: String) -> [Tok]? {
    let s = Array(src)
    var out: [Tok] = []
    var i = 0
    func startsWith(_ word: String, _ at: Int) -> Bool {
        let w = Array(word)
        return at + w.count <= s.count && Array(s[at..<at + w.count]) == w
    }
    while i < s.count {
        let ch = s[i]
        if ch.isWhitespace {
            i += 1
        } else if isDigit(ch) || ((ch == "." || ch == ",") && isDigit(i + 1 < s.count ? s[i + 1] : nil)) {
            // A comma between digits is the Czech decimal comma.
            var j = i
            while j < s.count, isDigit(s[j]) { j += 1 }
            if j + 1 < s.count, s[j] == "." || s[j] == ",", isDigit(s[j + 1]) {
                j += 1
                while j < s.count, isDigit(s[j]) { j += 1 }
            }
            out.append(.num(Double(String(s[i..<j]).replacingOccurrences(of: ",", with: ".")) ?? .nan))
            i = j
        } else if isLetter(ch) {
            var end = i
            while end < s.count, isLetter(s[end]) { end += 1 }
            var j = i
            while j < end {
                let piece = words.first { w in j + w.count <= end && startsWith(w, j) } ?? String(s[j])
                out.append(.name(piece))
                j += piece.count
            }
            i = end
        } else if ch == "π" {
            out.append(.name("pi"))
            i += 1
        } else if ch == "√" {
            out.append(.name("sqrt"))
            i += 1
        } else if ch == "²" || ch == "³" {
            out += [.op("^"), .num(ch == "²" ? 2 : 3)]
            i += 1
        } else if let (typed, op) = compareSigns.first(where: { startsWith($0.0, i) }) {
            out.append(.op(op.rawValue))
            i += typed.count
        } else if "+-*/^()|={}".contains(ch) {
            out.append(.op(String(ch)))
            i += 1
        } else if ch == "−" || ch == "–" {
            out.append(.op("-"))
            i += 1
        } else if ch == "·" || ch == "×" || ch == "⋅" {
            out.append(.op("*"))
            i += 1
        } else if ch == "÷" || ch == ":" {
            out.append(.op("/"))
            i += 1
        } else {
            return nil
        }
    }
    return out
}

private struct Vars {
    var x: Bool
    var y: Bool
    static let x = Vars(x: true, y: false)
    static let y = Vars(x: false, y: true)
    static let xy = Vars(x: true, y: true)
}

private final class Parser {
    private let toks: [Tok]
    private let vars: Vars
    private var i = 0
    /// Open |…| brackets: inside one, `|` closes instead of starting a new one.
    private var absDepth = 0

    init(_ toks: [Tok], _ vars: Vars = .x) {
        self.toks = toks
        self.vars = vars
    }

    private func peek(_ k: Int = 0) -> Tok? { i + k < toks.count ? toks[i + k] : nil }

    private func isOp(_ v: String, _ tok: Tok?) -> Bool { tok == .op(v) }

    private func take(_ v: String) -> Bool {
        guard isOp(v, peek()) else { return false }
        i += 1
        return true
    }

    private func expect(_ v: String) throws {
        if take(v) { return }
        throw GraphError(peek() != nil ? "graph.error.syntax" : "graph.error.end")
    }

    /// A comparison sign next: <, ≤, >, ≥.
    func compare() -> Compare? {
        guard let c = peek()?.compare else { return nil }
        i += 1
        return c
    }

    var done: Bool { i >= toks.count }

    /// expr := term (('+' | '−') term)*
    func expr() throws -> Expr {
        var a = try term()
        while true {
            if take("+") { a = .bin(.add, a, try term()) }
            else if take("-") { a = .bin(.sub, a, try term()) }
            else { return a }
        }
    }

    /// Can the next token start a factor (so that leaving out "·" means multiplying)?
    private func startsFactor() -> Bool {
        guard let tok = peek() else { return false }
        guard case .op(let v) = tok else { return true }
        return v == "(" || (v == "|" && absDepth == 0)
    }

    /// term := unary (('·' | '/' | nothing) unary)*
    private func term() throws -> Expr {
        var a = try unary()
        while true {
            if take("*") { a = .bin(.mul, a, try unary()) }
            else if take("/") { a = .bin(.div, a, try unary()) }
            else if startsFactor() { a = .bin(.mul, a, try power()) }
            else { return a }
        }
    }

    /// unary := ('−' | '+') unary | power — so −x² is −(x²).
    private func unary() throws -> Expr {
        if take("-") { return .neg(try unary()) }
        if take("+") { return try unary() }
        return try power()
    }

    /// power := primary ('^' unary)? — right-associative, 2^−x works.
    private func power() throws -> Expr {
        let base = try primary()
        if take("^") { return .bin(.pow, base, try unary()) }
        return base
    }

    /// The argument of `sin x`, `√2`, `ln 2x` written without brackets: the factors that follow, up to
    /// the next function name (sin x cos x is sin(x)·cos(x)).
    private func bareArgument(_ name: BuiltIn) throws -> Expr {
        if name == .sqrt { return try primary() }
        var a = try power()
        while startsFactor() && !startsFunction() { a = .bin(.mul, a, try power()) }
        return a
    }

    private func startsFunction() -> Bool {
        guard case .name(let v) = peek() else { return false }
        return BuiltIn(rawValue: v) != nil || (!reservedNames.contains(v) && v != "pi" && isOp("(", peek(1)))
    }

    private func primary() throws -> Expr {
        guard let tok = peek() else { throw GraphError("graph.error.end") }
        i += 1
        switch tok {
        case .num(let v):
            return .num(v)
        case .op(let v):
            if v == "(" {
                let e = try expr()
                try expect(")")
                return e
            }
            if v == "|" {
                absDepth += 1
                let e = try expr()
                absDepth -= 1
                try expect("|")
                return .fn(.abs, e)
            }
            i -= 1
            throw GraphError("graph.error.syntax")
        case .name(let name):
            if name == "x" && vars.x { return .x }
            if name == "y" && vars.y { return .y }
            if name == "x" || name == "y" { throw GraphError("graph.error.form") }
            if name == "e" { return .e }
            if name == "pi" { return .pi }
            if let builtIn = BuiltIn(rawValue: name) {
                // sin²x and sin^2 x mean (sin x)².
                var exponent: Expr?
                if take("^") { exponent = try unary() }
                let a = isOp("(", peek()) ? try primary() : try bareArgument(builtIn)
                let call = Expr.fn(builtIn, a)
                return exponent.map { .bin(.pow, call, $0) } ?? call
            }
            if isOp("(", peek()) {
                i += 1
                let a = try expr()
                try expect(")")
                return .call(name, a)
            }
            throw GraphError("graph.error.unknownName", name: name)
        }
    }
}

/// Parses one row. An empty row is a syntax error here; the caller skips empty rows.
public func parseRow(_ src: String) -> Result<ParsedRow, GraphError> {
    guard let all = tokenize(src), !all.isEmpty else { return .failure(GraphError("graph.error.syntax")) }
    // Restrictions come last: {…}{…}.
    let brace = all.firstIndex(of: .op("{"))
    let toks = brace.map { Array(all[..<$0]) } ?? all
    if toks.isEmpty { return .failure(GraphError("graph.error.syntax")) }
    do {
        let restrictions = try brace.map { try restrictionsOf(Array(all[$0...])) } ?? []
        var row = try parseMain(toks)
        row.restrictions = restrictions
        return .success(row)
    } catch let error as GraphError {
        return .failure(error)
    } catch {
        return .failure(GraphError("graph.error.syntax"))
    }
}

/// {0 ≤ x ≤ 10}{y > 2}: each a chain of comparisons, x and y both allowed.
private func restrictionsOf(_ toks: [Tok]) throws -> [Restriction] {
    var out: [Restriction] = []
    let bad = GraphError("graph.error.restriction")
    var i = 0
    while i < toks.count {
        guard toks[i] == .op("{") else { throw bad }
        guard let close = toks.indices.first(where: { $0 > i && (toks[$0] == .op("}") || toks[$0] == .op("{")) }),
              toks[close] == .op("}") else { throw bad }
        out.append(try chain(Array(toks[(i + 1)..<close]), "graph.error.restriction"))
        i = close + 1
    }
    return out
}

/// A chain of comparisons in x and y, 0 ≤ x ≤ 10 or y > x^2; `bad`: the error when it's something else.
private func chain(_ toks: [Tok], _ bad: String) throws -> Restriction {
    let p = Parser(toks, .xy)
    var terms = [try p.expr()]
    var ops: [Compare] = []
    while let op = p.compare() {
        ops.append(op)
        terms.append(try p.expr())
    }
    if ops.isEmpty || !p.done { throw GraphError(bad) }
    return Restriction(terms: terms, ops: ops)
}

private func parseMain(_ toks: [Tok]) throws -> ParsedRow {
    func row(_ kind: RowKind) -> ParsedRow { ParsedRow(kind: kind, restrictions: []) }
    let eq = toks.firstIndex(of: .op("="))
    // An inequality shades: y ≤ x^2, x^2 + y^2 < 4, -1 ≤ y ≤ 2.
    if toks.contains(where: { $0.compare != nil }) {
        if eq != nil { throw GraphError("graph.error.syntax") }
        return row(.region(try chain(toks, "graph.error.syntax")))
    }
    guard let eq else { return row(.y(try whole(toks), bare: true)) }
    if toks[(eq + 1)...].contains(.op("=")) { throw GraphError("graph.error.syntax") }
    let lhs = Array(toks[..<eq])
    let rhs = Array(toks[(eq + 1)...])
    if rhs.isEmpty { throw GraphError("graph.error.end") }
    if lhs == [.name("y")] { return row(.y(try whole(rhs), bare: false)) }
    if lhs == [.name("x")] { return row(.x(try whole(rhs, .y))) }
    // f(x) = …
    if lhs.count == 4, case .name(let n) = lhs[0], n.count == 1, lhs[1] == .op("("), lhs[2] == .name("x"), lhs[3] == .op(")") {
        if reservedNames.contains(n) { throw GraphError("graph.error.reserved", name: n) }
        return row(.def(name: n, try whole(rhs)))
    }
    // A circle, or any other equation in x and y: x^2/4 + y^2 = 1, 2y = x.
    let l = try whole(lhs, .xy)
    let r = try whole(rhs, .xy)
    if let circle = circleOf(l, r) { return row(circle) }
    if usesVariable(l) || usesVariable(r) { return row(.curve(lhs: l, rhs: r)) }
    throw GraphError("graph.error.form")
}

private func whole(_ toks: [Tok], _ vars: Vars = .x) throws -> Expr {
    let p = Parser(toks, vars)
    let e = try p.expr()
    if !p.done { throw GraphError("graph.error.syntax") }
    return e
}

/// Does the expression use x or y?
public func usesVariable(_ e: Expr) -> Bool {
    switch e {
    case .x, .y: return true
    case .neg(let a), .fn(_, let a), .call(_, let a): return usesVariable(a)
    case .bin(_, let a, let b): return usesVariable(a) || usesVariable(b)
    default: return false
    }
}

/// (x − m)², (x + m)² or x²: which variable (true: x), and m. Nil: not such a square.
private func square(_ e: Expr) -> (isX: Bool, at: Expr)? {
    guard case .bin(.pow, let base, .num(2)) = e else { return nil }
    if base == .x || base == .y { return (base == .x, .num(0)) }
    guard case .bin(let op, let v, let m) = base, op == .sub || op == .add, v == .x || v == .y, !usesVariable(m) else { return nil }
    return (v == .x, op == .sub ? m : .neg(m))
}

/// The circle (x − m)² + (y − n)² = r², the squares in either order, or nil when it's something else.
public func circleOf(_ lhs: Expr, _ rhs: Expr) -> RowKind? {
    guard case .bin(.add, let first, let second) = lhs, !usesVariable(rhs),
          let a = square(first), let b = square(second), a.isX != b.isX else { return nil }
    let (sx, sy) = a.isX ? (a, b) : (b, a)
    return .circle(lhs: lhs, rhs: rhs, m: sx.at, n: sy.at)
}
