import Foundation

/// Formats a length with 2 decimals and the language's decimal separator (6,00 / 6.00).
public func formatNumber(_ n: Double, comma: Bool = false) -> String {
    let s = String(format: "%.2f", n)
    return comma ? s.replacingOccurrences(of: ".", with: ",") : s
}

/// Compact dimension label: up to 2 decimals without trailing zeros (6 / 6,5 / 6,25).
public func formatDimension(_ n: Double, comma: Bool = false) -> String {
    let rounded = (n * 100).rounded() / 100
    let s = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    return comma ? s.replacingOccurrences(of: ".", with: ",") : s
}

/// Parses a positive number; accepts both "," and "." and an optional "cm" suffix. Returns nil if invalid.
public func parseNumber(_ raw: String) -> Double? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.lowercased().hasSuffix("cm") {
        s = String(s.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let comma = s.firstIndex(of: ",") { s.replaceSubrange(comma...comma, with: ".") }
    guard s.wholeMatch(of: /[0-9]*\.?[0-9]+|[0-9]+\./) != nil, let n = Double(s), n.isFinite, n > 0 else { return nil }
    return n
}
