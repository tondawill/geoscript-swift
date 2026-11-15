import Foundation

private let subscriptDigits = Array("₀₁₂₃₄₅₆₇₈₉")
private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
private let lineLetters = Array("pqrstuvwxyzabcdefghijklmno")

public func toSubscript(_ n: Int) -> String {
    String(String(n).compactMap { $0.wholeNumberValue.map { subscriptDigits[$0] } })
}

/// Trims the name and turns plain digits into subscripts: "k1" → "k₁".
public func normalizeName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(trimmed.map { c in
        if c.isASCII, let d = c.wholeNumberValue { subscriptDigits[d] } else { c }
    })
}

/// One letter from `first`, then any subscript digits, then any primes.
private func matchesNamePattern(_ name: String, first: ClosedRange<Character>) -> Bool {
    var rest = Substring(name)
    guard let head = rest.popFirst(), first.contains(head) else { return false }
    while let c = rest.first, subscriptDigits.contains(c) { rest.removeFirst() }
    while rest.first == "'" { rest.removeFirst() }
    return rest.isEmpty
}

/// Point names: one capital letter, optionally followed by a subscript index and/or primes (A, A₁, A').
public func isValidPointName(_ name: String) -> Bool {
    matchesNamePattern(name, first: "A"..."Z")
}

/// Names of lines, segments and circles: one lowercase letter, optional subscript index and/or primes.
public func isValidLowerName(_ name: String) -> Bool {
    matchesNamePattern(name, first: "a"..."z")
}

private func nextName(from alphabet: [Character], used: Set<String>) -> String {
    var index = 0
    while true {
        let suffix = index == 0 ? "" : toSubscript(index)
        for letter in alphabet {
            let name = String(letter) + suffix
            if !used.contains(name) { return name }
        }
        index += 1
    }
}

/// Next free point name: A … Z, then A₁ … Z₁, A₂ …
public func nextPointName(_ used: Set<String>) -> String {
    nextName(from: letters, used: used)
}

/// Next free circle name: k, k₁, k₂ …
public func nextCircleName(_ used: Set<String>) -> String {
    nextName(from: ["k"], used: used)
}

/// Next free line / ray name: p, q, r, s … then p₁, q₁ …
public func nextLineName(_ used: Set<String>) -> String {
    nextName(from: lineLetters, used: used)
}
