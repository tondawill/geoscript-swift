import Foundation

/// A line style of a graph row other than solid.
public enum Dash: String, Equatable, Sendable {
    case dashed, dotted
}

/// One row of the graphing calculator: what was typed, and how its graph is drawn. A row made by the
/// Intersect tool has no text; `between` holds the ids of the two rows whose crossings it keeps.
/// `width` (px, 0: no line), `dash` and `fill` (the opacity of a shaded row) come from the swatch menu.
public struct GraphRow: Equatable, Sendable {
    public var id: String
    public var text: String
    public var color: String
    public var hidden: Bool
    public var between: [String]?
    public var width: Double?
    public var dash: Dash?
    public var fill: Double?

    public init(id: String, text: String, color: String, hidden: Bool = false, between: [String]? = nil,
                width: Double? = nil, dash: Dash? = nil, fill: Double? = nil) {
        self.id = id
        self.text = text
        self.color = color
        self.hidden = hidden
        self.between = between
        self.width = width
        self.dash = dash
        self.fill = fill
    }
}

/// Line width and fill when a row doesn't set them.
public let graphDefaultWidth = 2.5
public let graphDefaultFill = 0.4
public let graphMaxWidth = 10.0
/// Colours the graphing calculator gives its rows, in turn.
public let graphColors = ["red", "blue", "green", "orange", "purple", "pink"]

public struct GraphState: Equatable, Sendable {
    public var rows: [GraphRow]
    public var nextId: Int

    public init(rows: [GraphRow] = [], nextId: Int = 1) {
        self.rows = rows
        self.nextId = nextId
    }

    /// Rows read from a file: ids are kept, the next id follows the highest one.
    public init(fromRows rows: [GraphRow]) {
        self.rows = rows
        nextId = rows.reduce(1) { n, r in max(n, (Int(r.id.dropFirst()) ?? 0) + 1) }
    }

    public var nextColor: String { graphColors[(nextId - 1) % graphColors.count] }

    /// A new row at the end, in the next colour (`width`: its line, 0 for none).
    public func adding(_ text: String, width: Double? = nil) -> GraphState {
        var g = self
        g.rows.append(GraphRow(id: "g\(nextId)", text: text, color: nextColor, width: width))
        g.nextId += 1
        return g
    }

    /// A row that keeps the crossings of rows a and b, in the next colour.
    public func addingCrossing(_ a: String, _ b: String) -> GraphState {
        var g = self
        g.rows.append(GraphRow(id: "g\(nextId)", text: "", color: nextColor, between: [a, b]))
        g.nextId += 1
        return g
    }

    public func updating(_ id: String, _ change: (inout GraphRow) -> Void) -> GraphState {
        var g = self
        if let i = g.rows.firstIndex(where: { $0.id == id }) { change(&g.rows[i]) }
        return g
    }

    /// Removes the row, and the crossings kept of it.
    public func removing(_ id: String) -> GraphState {
        var g = self
        g.rows.removeAll { $0.id == id || ($0.between?.contains(id) ?? false) }
        return g
    }
}

/// Only crossing rows whose two rows are there (and aren't crossing rows themselves).
public func soundCrossings(_ rows: [GraphRow]) -> [GraphRow] {
    let typed = Set(rows.filter { $0.between == nil }.map(\.id))
    return rows.compactMap { r in
        guard let b = r.between else { return r }
        guard b.count == 2, b[0] != b[1], b.allSatisfy(typed.contains) else { return nil }
        var row = r
        row.text = ""
        return row
    }
}

// MARK: JSON, the web's format

extension GraphRow {
    /// The row as the web app stores it: optional fields only when set.
    public var json: [String: Any] {
        var d: [String: Any] = ["id": id, "text": text, "color": color]
        if hidden { d["hidden"] = true }
        if let between { d["between"] = between }
        if let width { d["width"] = width }
        if let dash { d["dash"] = dash.rawValue }
        if let fill { d["fill"] = fill }
        return d
    }

    /// A row read from a file; nil when it isn't sound. Style fields that aren't valid are left out.
    public init?(json g: [String: Any]) {
        guard let id = g["id"] as? String, id.wholeMatch(of: #/g[0-9]+/#) != nil, let text = g["text"] as? String,
              isColor(g["color"]), let color = g["color"] as? String else { return nil }
        if let h = g["hidden"] {
            guard let n = h as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        }
        func num(_ v: Any?, _ max: Double) -> Double? {
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            return d.isFinite && d >= 0 && d <= max ? d : nil
        }
        self.init(id: id, text: text, color: color, hidden: (g["hidden"] as? Bool) ?? false,
                  between: g["between"] as? [String], width: num(g["width"], graphMaxWidth),
                  dash: (g["dash"] as? String).flatMap(Dash.init(rawValue:)), fill: num(g["fill"], 1))
        // A malformed `between` (not two strings) is dropped with the row by soundCrossings.
        if g["between"] != nil, between == nil { self.between = [] }
    }
}

/// The rows of a file's JSON: sound ones only, ids unique.
public func validGraphs(_ x: Any?) -> [GraphRow] {
    guard let list = x as? [Any] else { return [] }
    var ids = Set<String>()
    var rows: [GraphRow] = []
    for item in list {
        guard let d = item as? [String: Any], let row = GraphRow(json: d), !ids.contains(row.id) else { continue }
        ids.insert(row.id)
        rows.append(row)
    }
    return soundCrossings(rows)
}

// MARK: Parsed rows

public enum BuiltIn: String, CaseIterable, Sendable {
    case sin, cos, tan, sqrt, abs, ln, log, exp
}

public enum BinOp: String, Sendable {
    case add = "+", sub = "-", mul = "*", div = "/", pow = "^"
}

/// Expression tree. `x` is the only variable of a function; `y` appears on the left of a circle,
/// on the right of an x = … row, in equations in both and in restrictions.
public indirect enum Expr: Equatable, Sendable {
    case num(Double)
    case x
    case y
    case pi
    case e
    case neg(Expr)
    case bin(BinOp, Expr, Expr)
    case fn(BuiltIn, Expr)
    case call(String, Expr)
}

public enum Compare: String, Sendable {
    case lt = "<", le = "≤", gt = ">", ge = "≥"
}

/// One restriction in braces, a chain of comparisons: {0 ≤ x ≤ 10} is terms [0, x, 10], ops [≤, ≤].
public struct Restriction: Equatable, Sendable {
    public var terms: [Expr]
    public var ops: [Compare]
}

/// What a row is: `y = …` (`bare`: typed without "y ="), a definition `f(x) = …`, `x = …` (a function
/// of y, drawn sideways), a circle (x − m)² + (y − n)² = r² (its two sides as typed, m and n read off
/// the brackets), any other equation in x and y (`curve`), or an inequality (`region`, shaded).
public enum RowKind: Equatable, Sendable {
    case y(Expr, bare: Bool)
    case def(name: String, Expr)
    case x(Expr)
    case circle(lhs: Expr, rhs: Expr, m: Expr, n: Expr)
    case curve(lhs: Expr, rhs: Expr)
    case region(Restriction)
}

/// A parsed row; `restrictions` ({0 ≤ x ≤ 10}{y > 2}) limit where it is drawn.
public struct ParsedRow: Equatable, Sendable {
    public var kind: RowKind
    public var restrictions: [Restriction]
}

/// Why a row can't be drawn: a message key (graph.error.…) and the name it is about.
public struct GraphError: Error, Equatable, Sendable {
    public var key: String
    public var name: String?

    public init(_ key: String, name: String? = nil) {
        self.key = key
        self.name = name
    }
}
