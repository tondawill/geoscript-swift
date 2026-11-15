/// Parser for typed construction steps. It reads the notation the protocol prints ("AB; |AB| = 6 cm",
/// "k; k(A, r = 4 cm)", "C; C ∈ k ∩ l", "p; A ∈ p ∧ p ⊥ q" …) plus short forms without the "head;" part.

/// A reference to an existing (or new) object: a lowercase name, segment AB, or ray ↦AB.
enum Ref: Equatable {
    case name(String)
    case seg(String, String)
    case ray(String, String)

    var text: String {
        switch self {
        case .name(let n): n
        case let .seg(a, b): a + b
        case let .ray(a, b): "↦" + a + b
        }
    }

    /// The two points of a segment or ray reference.
    var points: (a: String, b: String)? {
        switch self {
        case .name: nil
        case let .seg(a, b), let .ray(a, b): (a, b)
        }
    }

    var head: Head? {
        switch self {
        case .name: nil
        case let .seg(a, b): .seg(a, b)
        case let .ray(a, b): .ray(a, b)
        }
    }
}

enum Radius: Equatable {
    case value(Double)
    case span(String, String)
}

enum RelSymbol { case perp, par }
enum NamedShape { case segment, line, ray }

enum Clause {
    case names([String], lower: Bool)
    case length(a: String, b: String, value: Double, lines: (String, String)?)
    case equal(a: [String], b: [String])
    case dist(line: String, ref: Ref, value: Double)
    case within(points: [String], target: Ref)
    case cap(point: String, a: Ref, b: Ref)
    case rel(RelSymbol, left: Ref, right: Ref)
    case angle3(a: String, v: String, b: String, deg: Double)
    case angle2(left: Ref, right: Ref, deg: Double)
    case circle(name: String, center: String, radius: Radius)
    case named(name: String, shape: NamedShape, a: String, b: String)
    case linear(shape: NamedShape, a: String, b: String)
    case triangle([String])
}

/// What the step creates, written before ";".
enum Head {
    case point(String)
    case seg(String, String)
    case ray(String, String)
    case name(String)
}

struct Statement {
    let head: Head?
    let clauses: [Clause]
}

private enum Tok: Equatable {
    /// `sp`: whitespace before the name. "C E" is two separate names, "CE" a segment.
    case up(String, sp: Bool)
    case low(String, sp: Bool)
    case num(Double)
    case sym(Character)
}

private let subscripts = Array("₀₁₂₃₄₅₆₇₈₉")
private let symbols = Array(";,|=()∈∩⊥∥∠△°↦↔∧")

private func isASCIILetter(_ c: Character) -> Bool { c.isASCII && c.isLetter }
private func isASCIIDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

/// Splits the text into names (one letter + subscript + primes), numbers and symbols.
private func tokenize(_ text: String) -> [Tok]? {
    let src = Array(text)
    var out: [Tok] = []
    var i = 0
    func at(_ k: Int) -> Character? { k < src.count ? src[k] : nil }
    func lastIsNum() -> Bool {
        if case .num? = out.last { return true }
        return false
    }
    while i < src.count {
        let ch = src[i]
        if ch.isWhitespace {
            i += 1
        } else if isASCIILetter(ch) {
            // "cm" after a number is a unit, not two names.
            if ch == "c", at(i + 1) == "m", lastIsNum(), !(at(i + 2).map(isASCIILetter) ?? false) {
                i += 2
                continue
            }
            let sp = i > 0 && src[i - 1].isWhitespace
            var name = String(ch)
            i += 1
            while let c = at(i), subscripts.contains(c) || isASCIIDigit(c) {
                name.append(isASCIIDigit(c) ? subscripts[c.wholeNumberValue!] : c)
                i += 1
            }
            while at(i) == "'" || at(i) == "′" {
                name += "'"
                i += 1
            }
            out.append(ch.isUppercase ? .up(name, sp: sp) : .low(name, sp: sp))
        } else if isASCIIDigit(ch) || ((ch == "." || ch == ",") && (at(i + 1).map(isASCIIDigit) ?? false) && lastIsNum()) {
            var s = ""
            while let c = at(i), isASCIIDigit(c) {
                s.append(c)
                i += 1
            }
            // A decimal comma is followed directly by a digit ("3,5"); a list comma has a space after it.
            if at(i) == "." || at(i) == ",", at(i + 1).map(isASCIIDigit) ?? false {
                s += "."
                i += 1
                while let c = at(i), isASCIIDigit(c) {
                    s.append(c)
                    i += 1
                }
            }
            out.append(.num(Double(s.isEmpty ? "0" : (s.hasPrefix(".") ? "0" + s : s)) ?? 0))
        } else if symbols.contains(ch) || ch == "^" {
            // "^" is the keyboard spelling of ∧.
            out.append(.sym(ch == "^" ? "∧" : ch))
            i += 1
        } else {
            return nil
        }
    }
    return out
}

private struct Fail: Error {}

/// Point name from a token; a lowercase letter in a point position is read as a capital.
private func cap(_ v: String) -> String {
    v.prefix(1).uppercased() + v.dropFirst()
}

private enum AngleHead {
    case three(a: String, v: String, b: String)
    case two(left: Ref, right: Ref)
}

private struct NameToken {
    let value: String
    let upper: Bool
    let sp: Bool
}

private struct Parser {
    let toks: [Tok]
    var i = 0

    func peek(_ o: Int = 0) -> Tok? {
        i + o < toks.count ? toks[i + o] : nil
    }

    func isSym(_ v: Character, _ o: Int = 0) -> Bool {
        peek(o) == .sym(v)
    }

    mutating func sym(_ v: Character) throws {
        guard isSym(v) else { throw Fail() }
        i += 1
    }

    func nameAt(_ o: Int = 0) -> NameToken? {
        switch peek(o) {
        case let .up(v, sp)?: NameToken(value: v, upper: true, sp: sp)
        case let .low(v, sp)?: NameToken(value: v, upper: false, sp: sp)
        default: nil
        }
    }

    mutating func name() throws -> NameToken {
        guard let t = nameAt() else { throw Fail() }
        i += 1
        return t
    }

    mutating func point() throws -> String {
        cap(try name().value)
    }

    mutating func num() throws -> Double {
        guard case .num(let v)? = peek(), v >= 0 else { throw Fail() }
        i += 1
        return v
    }

    /// Names written together (AB, not A B).
    mutating func names() -> [NameToken] {
        var out: [NameToken] = []
        while let t = nameAt(), !(!out.isEmpty && t.sp) {
            out.append(t)
            i += 1
        }
        return out
    }

    /// p, AB or ↦AB.
    mutating func ref() throws -> Ref {
        if isSym("↦") {
            i += 1
            let a = try point()
            return .ray(a, try point())
        }
        let ns = names()
        if ns.count == 1, !ns[0].upper { return .name(ns[0].value) }
        if ns.count == 2 { return .seg(cap(ns[0].value), cap(ns[1].value)) }
        throw Fail()
    }

    /// |AB|
    mutating func bars() throws -> (a: String, b: String) {
        try sym("|")
        let a = try point()
        let b = try point()
        try sym("|")
        return (a, b)
    }

    mutating func head() throws -> Head {
        if isSym("↦") {
            i += 1
            let a = try point()
            return .ray(a, try point())
        }
        let ns = names()
        if ns.count == 1 { return ns[0].upper ? .point(ns[0].value) : .name(ns[0].value) }
        if ns.count == 2 { return .seg(cap(ns[0].value), cap(ns[1].value)) }
        throw Fail()
    }

    mutating func clause() throws -> Clause {
        // |∠BAC| = 60°: the size of an angle, in bars.
        if isSym("|"), isSym("∠", 1) {
            i += 1
            let a = try angle()
            try sym("|")
            return try angleSize(a)
        }
        // |p AB|, |p ↦AB|, |p q|: line p and another straight object (|pq| is read as a length below).
        let t1 = nameAt(1)
        let t2 = nameAt(2)
        if isSym("|"), let t1, !t1.upper, isSym("↦", 2) || (t2?.upper ?? false) || (t2.map { !$0.upper && $0.sp } ?? false) {
            i += 1
            let line = try name().value
            let r = try ref()
            try sym("|")
            try sym("=")
            return .dist(line: line, ref: r, value: try num())
        }
        if isSym("|") {
            let lower = t1.map { !$0.upper } == true && t2.map { !$0.upper } == true
            let names: (String, String)? = lower ? (t1!.value, t2!.value) : nil
            let (a, b) = try bars()
            try sym("=")
            if isSym("|"), !lower {
                let other = try bars()
                return .equal(a: [a, b], b: [other.a, other.b])
            }
            return .length(a: a, b: b, value: try num(), lines: names)
        }
        if isSym("∠") {
            let a = try angle()
            return try angleSize(a)
        }
        if isSym("△") {
            i += 1
            return .triangle([try point(), try point(), try point()])
        }
        if isSym("↔") || isSym("↦") {
            let shape: NamedShape = isSym("↔") ? .line : .ray
            i += 1
            let a = try point()
            let b = try point()
            if isSym("⊥") || isSym("∥") {
                if shape == .line { throw Fail() }
                return try relRest(.ray(a, b))
            }
            return .linear(shape: shape, a: a, b: b)
        }
        // Starts with names.
        let start = i
        let ns = names()
        if ns.isEmpty { throw Fail() }

        // k(S, …)
        if ns.count == 1, !ns[0].upper, isSym("(") {
            i += 1
            let center = try point()
            try sym(",")
            if let n = nameAt(), !n.upper, n.value == "r", isSym("=", 1) { i += 2 }
            let radius: Radius
            if isSym("|") {
                let (a, b) = try bars()
                radius = .span(a, b)
            } else {
                radius = .value(try num())
            }
            try sym(")")
            return .circle(name: ns[0].value, center: center, radius: radius)
        }
        // a = BC, p = ↔AB, p = ↦AB
        if ns.count == 1, !ns[0].upper, isSym("=") {
            i += 1
            var shape = NamedShape.segment
            if isSym("↔") { shape = .line }
            if isSym("↦") { shape = .ray }
            if shape != .segment { i += 1 }
            let a = try point()
            return .named(name: ns[0].value, shape: shape, a: a, b: try point())
        }
        // C ∈ … / A, B ∈ …
        if ns.count == 1, isSym("∈") || isSym(",") {
            var points = [cap(ns[0].value)]
            while isSym(",") {
                // A list comma only if more names and then ∈ follow; otherwise the clause ends here.
                var j = 1
                while nameAt(j) != nil { j += 1 }
                if j != 2 || !(isSym(",", j) || isSym("∈", j)) { break }
                i += 1
                points.append(try point())
            }
            if isSym("∈") {
                i += 1
                let a = try ref()
                if isSym("∩") {
                    i += 1
                    if points.count != 1 { throw Fail() }
                    return .cap(point: points[0], a: a, b: try ref())
                }
                return .within(points: points, target: a)
            }
            if points.count > 1 { throw Fail() }
        }
        // AB ⊥ p, p ∥ q
        if isSym("⊥") || isSym("∥") {
            i = start
            let left = try ref()
            return try relRest(left)
        }
        return .names(ns.map(\.value), lower: ns.allSatisfy { !$0.upper })
    }

    /// ∠BAC or ∠(AB, p), without its size.
    mutating func angle() throws -> AngleHead {
        try sym("∠")
        if isSym("(") {
            i += 1
            let left = try ref()
            try sym(",")
            let right = try ref()
            try sym(")")
            return .two(left: left, right: right)
        }
        let a = try point()
        let v = try point()
        return .three(a: a, v: v, b: try point())
    }

    /// "= 60°" after an angle.
    mutating func angleSize(_ angle: AngleHead) throws -> Clause {
        try sym("=")
        let deg = try num()
        if isSym("°") { i += 1 }
        switch angle {
        case let .three(a, v, b): return .angle3(a: a, v: v, b: b, deg: deg)
        case let .two(left, right): return .angle2(left: left, right: right, deg: deg)
        }
    }

    mutating func relRest(_ left: Ref) throws -> Clause {
        let rel: RelSymbol = isSym("⊥") ? .perp : .par
        i += 1
        return .rel(rel, left: left, right: try ref())
    }

    mutating func statement() throws -> Statement {
        var head: Head?
        if toks.contains(.sym(";")) {
            head = try self.head()
            try sym(";")
        }
        var clauses = [try clause()]
        while isSym(",") || isSym("∧") {
            i += 1
            clauses.append(try clause())
        }
        if i < toks.count { throw Fail() }
        return Statement(head: head, clauses: clauses)
    }
}

func parseStep(_ src: String) -> Statement? {
    guard let toks = tokenize(src), !toks.isEmpty else { return nil }
    var parser = Parser(toks: toks)
    return try? parser.statement()
}
