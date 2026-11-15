import Foundation

// Numbers written the way the web app writes them (JavaScript's String(n), toFixed and
// toPrecision), so that rows made here read the same as rows made on the web. Also the linear
// function through two points (src/engine/graph/linear.ts), which the Restrict tool writes.

public let graphEps = 1e-9
private let maxDenominator = 100

/// JavaScript's String(n): the shortest text that reads back as n, without exponent for 1e-6 ≤ |n| < 1e21.
public func jsString(_ n: Double) -> String {
    if n.isNaN { return "NaN" }
    if n.isInfinite { return n < 0 ? "-Infinity" : "Infinity" }
    if n == 0 { return "0" }
    let a = abs(n)
    let sign = n < 0 ? "-" : ""
    // Swift's description is also the shortest round trip, only written differently.
    var s = "\(a)"
    var exponent = 0
    if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        exponent = Int(s[s.index(after: e)...]) ?? 0
        s = String(s[..<e])
    }
    var digits = s.replacingOccurrences(of: ".", with: "")
    let point = (s.firstIndex(of: ".").map { s.distance(from: s.startIndex, to: $0) } ?? s.count) + exponent
    // Digits without leading zeros; `dot`: where the decimal point goes, counted from the first digit.
    var dot = point
    while digits.hasPrefix("0") && digits.count > 1 {
        digits.removeFirst()
        dot -= 1
    }
    while digits.hasSuffix("0") && digits.count > 1 { digits.removeLast() }
    if a >= 1e21 || a < 1e-6 {
        let e = dot - 1
        let mantissa = digits.count > 1 ? "\(digits.first!).\(digits.dropFirst())" : digits
        return "\(sign)\(mantissa)e\(e < 0 ? "-" : "+")\(abs(e))"
    }
    if dot <= 0 { return "\(sign)0.\(String(repeating: "0", count: -dot))\(digits)" }
    if dot >= digits.count { return sign + digits + String(repeating: "0", count: dot - digits.count) }
    let i = digits.index(digits.startIndex, offsetBy: dot)
    return "\(sign)\(digits[..<i]).\(digits[i...])"
}

/// +n.toFixed(d): n rounded to d decimals.
public func jsToFixedNumber(_ n: Double, _ d: Int) -> Double {
    guard n.isFinite, abs(n) < 1e21 else { return n }
    return Double(String(format: "%.\(d)f", n)) ?? n
}

/// +n.toPrecision(12): n to 12 significant digits.
public func jsPrecision12(_ n: Double) -> Double {
    guard n.isFinite else { return n }
    return Double(String(format: "%.11e", n)) ?? n
}

/// |v| written for a formula: short decimals stay (2, 0,5, 1,25), longer ones become a fraction
/// when there is one with a small denominator (1/3, 7/8), otherwise kept to 10 decimals so the graph
/// still goes through the point.
public func formatAbs(_ v: Double, comma: Bool) -> String {
    let a = abs(v)
    func decimal(_ d: Int) -> String {
        let s = jsString(jsToFixedNumber(a, d))
        return comma ? s.replacingOccurrences(of: ".", with: ",") : s
    }
    if abs(a - jsToFixedNumber(a, 2)) < graphEps { return decimal(2) }
    for q in 2...maxDenominator {
        let p = (a * Double(q) + 0.5).rounded(.down)
        if abs(a - p / Double(q)) < graphEps { return "\(jsString(p))/\(q)" }
    }
    return decimal(10)
}

/// Slope and y-intercept of the line through a and b, or nil when it's vertical (no y = …).
public func lineThrough(_ a: Vec, _ b: Vec) -> (m: Double, c: Double)? {
    if abs(a.x - b.x) < 1e-12 { return nil }
    let m = (b.y - a.y) / (b.x - a.x)
    return (m, a.y - m * a.x)
}

/// The row text y = mx + c through a and b, or nil for a vertical line.
public func linearThrough(_ a: Vec, _ b: Vec, comma: Bool) -> String? {
    guard let line = lineThrough(a, b) else { return nil }
    // Float noise from the grid (0.30000000000000004) counts as zero / one.
    let m = abs(line.m) < graphEps ? 0 : line.m
    let c = abs(line.c) < graphEps ? 0 : line.c
    if m == 0 { return "y = \(c < 0 ? "-" : "")\(formatAbs(c, comma: comma))" }
    let mx = (m < 0 ? "-" : "") + (abs(abs(m) - 1) < graphEps ? "" : formatAbs(m, comma: comma)) + "x"
    return c == 0 ? "y = \(mx)" : "y = \(mx) \(c < 0 ? "-" : "+") \(formatAbs(c, comma: comma))"
}

/// The vertical line x = c through a point.
public func verticalThrough(_ a: Vec, comma: Bool) -> String {
    let c = abs(a.x) < graphEps ? 0 : a.x
    return "x = \(c < 0 ? "-" : "")\(formatAbs(c, comma: comma))"
}

/// A point as [x; y]: up to two decimals, with the language's decimal separator and a real minus.
public func pointText(_ p: Vec, comma: Bool) -> String {
    "[\([p.x, p.y].map { formatDimension($0, comma: comma).replacingOccurrences(of: "-", with: "−") }.joined(separator: "; "))]"
}
